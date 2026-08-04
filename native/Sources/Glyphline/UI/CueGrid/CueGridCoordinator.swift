// NSTableView data source/delegate + inline editing + selection sync + context
// menu + I/O/P live timing (ported from ../../../src/components/CueList/*.tsx).

import AppKit
import GlyphlineCore

@MainActor
final class CueGridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let document: DocumentModel
    weak var tableView: NSTableView?

    private var rows: [Cue] = []
    private var lastActiveCueId: String?
    private var lastSelectedIds: Set<String> = []
    private var isApplyingExternalSelection = false

    /// Injected by M4 once mpv playback exists; nil until then (I/O/P no-op).
    var playheadProvider: (() -> Double?)?
    /// Live from Settings ▸ 품질 검사 기준 (default until the panel changes it).
    var qualityThresholds: QualityThresholds = DEFAULT_THRESHOLDS
    /// Called when a cue becomes active via click or arrow-key navigation
    /// (mirrors CueRow.tsx: selecting a row seeks the playhead to its start).
    var onRowActivated: ((Cue) -> Void)?
    /// Context menu "Play from Here" — seeks without changing selection.
    var onPlayHere: ((Cue) -> Void)?
    /// Whether media is loaded (gates "Play from Here" and reflects mediaPath != nil).
    var mediaAvailable: (() -> Bool)?
    /// Context menu "Edit Inline Tags" — makes the row active, then opens the panel.
    var onEditTags: ((Cue) -> Void)?

    init(document: DocumentModel) {
        self.document = document
    }

    // ── SwiftUI → AppKit sync ───────────────────────────────────────────────────

    func sync(activeCueId: String?, selectedIds: Set<String>) {
        lastActiveCueId = activeCueId
        lastSelectedIds = selectedIds
    }

    func reload() {
        rows = sortedCues(document.doc.cues)
        tableView?.reloadData()
        applySelectionFromModel()
    }

    private func applySelectionFromModel() {
        guard let tableView else { return }
        let indices = IndexSet(rows.enumerated().compactMap { lastSelectedIds.contains($1.id) ? $0 : nil })
        isApplyingExternalSelection = true
        tableView.selectRowIndexes(indices, byExtendingSelection: false)
        isApplyingExternalSelection = false
    }

    // ── NSTableViewDataSource ────────────────────────────────────────────────────

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    // ── NSTableViewDelegate ──────────────────────────────────────────────────────

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let colId = tableColumn?.identifier,
              let column = CueColumn.allCases.first(where: { $0.identifier == colId }) else { return nil }
        let cue = rows[row]

        switch column {
        case .flag:
            return makeFlagView(cue: cue, prev: row > 0 ? rows[row - 1] : nil)
        case .index:
            return makeLabel("\(row + 1)", alignment: .right, mono: true, dim: true)
        case .start:
            return makeEditableField(cue: cue, column: column, text: formatDisplayTime(cue.start), mono: true, alignment: .right)
        case .end:
            return makeEditableField(cue: cue, column: column, text: formatDisplayTime(cue.end), mono: true, alignment: .right)
        case .duration:
            let d = cueDuration(cue)
            let c = cps(cue)
            return makeLabel(String(format: "%.2fs %.0fcps", d, c), alignment: .right, mono: true, dim: true)
        case .style:
            return makeEditableField(cue: cue, column: column, text: cue.style ?? "", mono: false, alignment: .left)
        case .actor:
            return makeEditableField(cue: cue, column: column, text: cue.actor ?? "", mono: false, alignment: .left)
        case .text:
            return makeEditableField(cue: cue, column: column, text: cue.text, mono: false, alignment: .left)
        case .translation:
            return makeEditableField(cue: cue, column: column, text: cue.translation ?? "", mono: false, alignment: .left)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingExternalSelection, let tableView else { return }
        let selectedRows = tableView.selectedRowIndexes
        let ids = Set(selectedRows.compactMap { $0 < rows.count ? rows[$0].id : nil })
        document.selectedIds = ids
        if let last = selectedRows.max(), last < rows.count {
            let cue = rows[last]
            document.setActiveCue(cue.id)
            onRowActivated?(cue)
        } else if ids.isEmpty {
            document.setActiveCue(nil)
        }
    }

    // ── Cell construction ───────────────────────────────────────────────────────

    private func makeLabel(_ text: String, alignment: NSTextAlignment, mono: Bool, dim: Bool) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.alignment = alignment
        field.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 12)
        field.textColor = dim ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    /// Encodes (column, cue id) in the field's identifier so the delegate can
    /// route a commit without a per-row closure allocation dance.
    private func makeEditableField(cue: Cue, column: CueColumn, text: String, mono: Bool, alignment: NSTextAlignment) -> NSView {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = alignment
        field.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier("\(column)\u{1}\(cue.id)")
        return field
    }

    /// Decodes the (column, cue id) pair packed into a cell's identifier.
    private func decodeFieldIdentifier(_ field: NSTextField) -> (column: CueColumn, cueId: String)? {
        guard let raw = field.identifier?.rawValue else { return nil }
        let parts = raw.split(separator: "\u{1}", maxSplits: 1)
        guard parts.count == 2,
              let column = CueColumn.allCases.first(where: { "\($0)" == parts[0] }) else { return nil }
        return (column, String(parts[1]))
    }

    private func makeFlagView(cue: Cue, prev: Cue?) -> NSView {
        let q = evaluateCue(cue, prev: prev, thresholds: qualityThresholds)
        let container = NSView()
        if hasAnyIssue(q) {
            let dot = NSView(frame: NSRect(x: 4, y: 9, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            dot.layer?.cornerRadius = 3
            container.addSubview(dot)
        }
        return container
    }

    // ── Inline edit commit (NSTextFieldDelegate) ────────────────────────────────

    /// Spell checking lives on the field editor (an NSTextView shared per
    /// window), not on NSTextField, so it has to be configured per editing
    /// session rather than once at cell construction.
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let (column, _) = decodeFieldIdentifier(field),
              let editor = field.currentEditor() as? NSTextView else { return }
        // Only the prose columns. Timecodes, style names and actor names are
        // codes and identifiers — every value would be flagged.
        editor.isContinuousSpellCheckingEnabled = (column == .text || column == .translation)
        // Never let macOS silently rewrite subtitle text: a "correction" applied
        // behind the translator's back is a wrong subtitle shipped. Underline
        // and offer, don't change.
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isGrammarCheckingEnabled = false
        // Source and translation columns hold different languages, so let the
        // checker pick per field rather than pinning one language document-wide.
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let (column, cueId) = decodeFieldIdentifier(field) else { return }
        let value = field.stringValue

        switch column {
        case .start:
            guard let t = parseTimestampInput(value) else { reload(); return }
            document.updateCue(cueId) { $0.start = t }
        case .end:
            guard let t = parseTimestampInput(value) else { reload(); return }
            document.updateCue(cueId) { $0.end = t }
        case .style:
            document.updateCue(cueId) { $0.style = value.isEmpty ? nil : value }
        case .actor:
            document.updateCue(cueId) { $0.actor = value.isEmpty ? nil : value }
        case .text:
            document.updateCue(cueId) { $0.text = value }
        case .translation:
            document.updateCue(cueId) { $0.translation = value.isEmpty ? nil : value }
        case .flag, .index, .duration:
            break
        }
    }

    // ── I/O/P live timing (ported from CueList.tsx keydown handler) ────────────

    func handleTimingKey(_ key: Character) {
        guard let tNow = playheadProvider?(), let activeId = document.activeCueId,
              let idx = rows.firstIndex(where: { $0.id == activeId }) else { return }
        let active = rows[idx]
        let next = idx + 1 < rows.count ? rows[idx + 1] : nil

        switch key {
        case "i":
            document.updateCue(active.id) { $0.start = tNow }
        case "o":
            document.updateCue(active.id) { $0.end = tNow }
            if let next { document.setActiveCue(next.id) }
        case "p":
            var edits: [(id: String, edit: CueEdit)] = [(active.id, { $0.end = tNow })]
            if let next { edits.append((next.id, { $0.start = tNow })) }
            document.batchUpdateCues(edits)
            if let next { document.setActiveCue(next.id) }
        default:
            break
        }
    }

    // ── Context menu ─────────────────────────────────────────────────────────────

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: t("ctxPlayHere"), action: #selector(ctxPlayHere), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("ctxInsertAfter"), action: #selector(ctxInsertAfter), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("ctxDuplicate"), action: #selector(ctxDuplicate), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("splitCue"), action: #selector(ctxSplit), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("mergeCues"), action: #selector(ctxMerge), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("editTags"), action: #selector(ctxEditTags), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("deleteCue"), action: #selector(ctxDelete), keyEquivalent: "").target = self
        return menu
    }

    /// The row the context menu was opened on (falls back to the active cue).
    private var contextRow: Cue? {
        guard let tableView else { return nil }
        let row = tableView.clickedRow
        if row >= 0, row < rows.count { return rows[row] }
        return rows.first { $0.id == document.activeCueId }
    }

    @objc private func ctxPlayHere() {
        guard let cue = contextRow else { return }
        onPlayHere?(cue)
    }
    @objc private func ctxInsertAfter() {
        guard let cue = contextRow else { return }
        document.insertCueAfter(cue.id)
    }
    @objc private func ctxDuplicate() {
        guard let cue = contextRow else { return }
        document.duplicateCue(cue.id)
    }
    /// Splits at the playhead if it falls inside the cue, else at the midpoint
    /// (mirrors CueList.tsx's ContextMenu splitCue handler).
    @objc private func ctxSplit() {
        guard let cue = contextRow else { return }
        let tNow = playheadProvider?()
        let at = (tNow.map { $0 > cue.start && $0 < cue.end } == true) ? tNow! : (cue.start + cue.end) / 2
        document.splitCue(cue.id, atTime: at)
    }
    @objc private func ctxMerge() {
        let ids = document.selectedIds.isEmpty ? [] : Array(document.selectedIds)
        document.mergeCues(ids)
    }
    @objc private func ctxEditTags() {
        guard let cue = contextRow else { return }
        onEditTags?(cue)
    }
    @objc private func ctxDelete() {
        let ids = document.selectedIds.isEmpty
            ? contextRow.map { [$0.id] } ?? []
            : Array(document.selectedIds)
        document.deleteCues(ids)
    }
}

extension CueGridCoordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let selCount = document.selectedIds.count
        menu.items.first { $0.action == #selector(ctxPlayHere) }?.isEnabled = (mediaAvailable?() ?? false) && contextRow != nil
        menu.items.first { $0.action == #selector(ctxMerge) }?.isEnabled = selCount >= 2
        menu.items.first { $0.action == #selector(ctxDelete) }?.isEnabled = selCount >= 1 || contextRow != nil
    }
}
