// NSTableView data source/delegate + inline editing + selection sync + context
// menu + I/O/P live timing (ported from ../../../src/components/CueList/*.tsx).

import AppKit
import SwiftUI
import GlyphlineCore

@MainActor
final class CueGridCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let document: DocumentModel
    weak var tableView: NSTableView?

    private var rows: [Cue] = []
    /// cue id → overlapPalette index, recomputed alongside `rows` — see
    /// overlapColorSlots and CueRowView.overlapColor.
    private var overlapSlots: [String: Int] = [:]
    private var lastActiveCueId: String?
    private var lastSelectedIds: Set<String> = []
    private var isApplyingExternalSelection = false
    /// Thresholds `rows`/`overlapSlots` were last computed against — lets
    /// reload() skip the expensive rebuild when only selection/active-cue
    /// changed. Without this, every click ran a full tableView.reloadData()
    /// (SwiftUI's Observation re-invokes updateNSView → reload() on every
    /// activeCueId/selectedIds mutation), so a burst of rapid clicks queued
    /// reload after reload on the main thread faster than they could drain —
    /// the app appeared frozen, and any in-flight mpv seek visibly lagged far
    /// behind whatever row was actually clicked last.
    private var lastReloadedThresholds: QualityThresholds = DEFAULT_THRESHOLDS
    /// Rebuilding this NSMenu is also non-trivial; only needed when the UI
    /// language changes, tracked via one cheap localized-string comparison
    /// instead of unconditionally on every call — see CueGridView.
    var lastMenuLangSignature: String?

    /// Injected by M4 once mpv playback exists; nil until then (I/O/P no-op).
    var playheadProvider: (() -> Double?)?
    /// Live from Settings ▸ 품질 검사 기준 (default until the panel changes it).
    var qualityThresholds: QualityThresholds = DEFAULT_THRESHOLDS
    /// Non-nil when the grid should show/accept HH:MM:SS:FF instead of seconds
    /// (View ▸ 프레임 타임코드, and only once a rate is actually known).
    var frameRate: Double?
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
        if activeCueId != lastActiveCueId {
            refreshActiveRowHighlight(oldId: lastActiveCueId, newId: activeCueId)
        }
        lastActiveCueId = activeCueId
        lastSelectedIds = selectedIds
    }

    /// Repaints just the two row views whose "active" state changed, instead
    /// of the full reload() a plain click used to trigger — see
    /// lastReloadedThresholds' doc comment for why that mattered.
    private func refreshActiveRowHighlight(oldId: String?, newId: String?) {
        guard let tableView else { return }
        for id in Set([oldId, newId].compactMap { $0 }) {
            guard let idx = rows.firstIndex(where: { $0.id == id }),
                  let rowView = tableView.rowView(atRow: idx, makeIfNecessary: false) as? CueRowView
            else { continue }
            rowView.isActiveCue = (id == newId)
        }
    }

    /// Last cue we scrolled to, so an active cue that's already on screen
    /// doesn't get re-scrolled on every unrelated update.
    private var lastScrolledCueId: String?
    /// Cues currently under the playhead (more than one when they overlap).
    private var playingCueIds: Set<String> = []

    /// Marks the cues the playhead is inside and, while actually playing,
    /// scrolls the first of them into view — so the list follows the video
    /// without touching the selection. Runs on the ~80ms poll, so it exits
    /// early on the common case where the set hasn't changed.
    func syncPlayback(time: Double?, isPlaying: Bool) {
        var next: Set<String> = []
        var firstIdx: Int?
        if let time {
            for (i, cue) in rows.enumerated() {
                if cue.start > time { break } // rows are start-sorted
                if time < cue.end {
                    next.insert(cue.id)
                    if firstIdx == nil { firstIdx = i }
                }
            }
        }
        guard next != playingCueIds else { return }
        let affected = next.symmetricDifference(playingCueIds)
        playingCueIds = next
        for id in affected {
            guard let idx = rows.firstIndex(where: { $0.id == id }),
                  let rowView = tableView?.rowView(atRow: idx, makeIfNecessary: false) as? CueRowView
            else { continue }
            rowView.isPlayingCue = next.contains(id)
        }
        // Only while playing: when paused the user is free to scroll and read
        // elsewhere, matching how the waveform only re-centres during playback.
        if isPlaying, let firstIdx {
            tableView?.scrollRowToVisible(firstIdx)
        }
    }

    /// Brings the active cue into view. Find & Replace, Quality Issues,
    /// Proofreading and waveform selection all jump the active cue somewhere
    /// else in the document; without this the grid stayed put, so clicking a
    /// search hit or a flagged cue looked like it did nothing whenever the
    /// target was outside the visible rows.
    private func scrollActiveCueIntoView() {
        guard let tableView, let id = lastActiveCueId, id != lastScrolledCueId,
              let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        lastScrolledCueId = id
        tableView.scrollRowToVisible(idx)
    }

    /// Puts the caret in the newly added cue's Text cell. Deferred to the next
    /// runloop turn because the row doesn't exist until SwiftUI has pushed the
    /// document change back through updateNSView → reload().
    func beginEditingActiveCueText() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let tableView,
                  let id = document.activeCueId,
                  let row = rows.firstIndex(where: { $0.id == id }),
                  let column = tableView.tableColumns.firstIndex(where: {
                      $0.identifier == CueColumn.text.identifier
                  })
            else { return }
            tableView.editColumn(column, row: row, with: nil, select: true)
        }
    }

    /// `force` re-renders cells even when the model is unchanged. Needed when
    /// the CELLS have diverged from the model without the model moving — the
    /// rejected-timecode path below leaves the user's unparseable text sitting
    /// in the field editor, and only a real reloadData() rebuilds that cell
    /// from the document and discards it.
    func reload(force: Bool = false) {
        let newRows = sortedCues(document.doc.cues)
        let needsFullReload = force || newRows != rows || qualityThresholds != lastReloadedThresholds
        rows = newRows
        if needsFullReload {
            lastReloadedThresholds = qualityThresholds
            overlapSlots = overlapColorSlots(for: rows, paletteSize: GlyphColor.overlapPalette.count)
            tableView?.reloadData()
        }
        applySelectionFromModel()
        // After `rows` is current, so a freshly added cue (⌘Return) can be
        // found and scrolled to on the same pass that inserts it.
        scrollActiveCueIntoView()
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
        // Computed once per row and read by every column below, so a CPS
        // problem colors the CPS figure, a timing conflict colors the
        // timecodes, and a line-length problem colors the text itself —
        // each column shows the specific thing wrong with IT, not a single
        // undifferentiated "something's wrong" dot.
        let q = evaluateCue(cue, prev: row > 0 ? rows[row - 1] : nil, thresholds: qualityThresholds)
        let timingColor: Color = (q.negativeDuration || q.overlapsPrev) ? GlyphColor.warn : GlyphColor.ink

        switch column {
        case .flag:
            return makeFlagView(quality: q)
        case .index:
            return makeLabel("\(row + 1)", alignment: .right, mono: true, color: GlyphColor.quiet)
        case .start:
            return makeEditableField(cue: cue, column: column, text: displayTime(cue.start), mono: true, alignment: .right, color: timingColor)
        case .end:
            return makeEditableField(cue: cue, column: column, text: displayTime(cue.end), mono: true, alignment: .right, color: timingColor)
        case .duration:
            let d = cueDuration(cue)
            let c = cps(cue)
            return makeLabel(String(format: "%.2fs %.0fcps", d, c), alignment: .right, mono: true, color: durationColor(q))
        case .style:
            return makeEditableField(cue: cue, column: column, text: cue.style ?? "", mono: false, alignment: .left, color: GlyphColor.ink)
        case .actor:
            return makeEditableField(cue: cue, column: column, text: cue.actor ?? "", mono: false, alignment: .left, color: GlyphColor.ink)
        case .text:
            // lineTooLong/tooManyLines are measured against cue.text specifically
            // (see Quality.swift) — only this column's own text earns the tint.
            let textColor: Color = (q.lineTooLong || q.tooManyLines) ? GlyphColor.amber : GlyphColor.ink
            return makeEditableField(cue: cue, column: column, text: cue.text, mono: false, alignment: .left, color: textColor)
        case .translation:
            return makeEditableField(cue: cue, column: column, text: cue.translation ?? "", mono: false, alignment: .left, color: GlyphColor.ink)
        }
    }

    /// Frame timecode when a rate is in play, else the millisecond form.
    private func displayTime(_ seconds: Double) -> String {
        guard let frameRate else { return formatDisplayTime(seconds) }
        return formatFrameTimecode(seconds, fps: frameRate)
    }

    /// Accepts whichever form the grid is currently showing, but also still
    /// accepts the other one — someone pasting a timecode out of another tool
    /// shouldn't have to convert it by hand first.
    ///
    /// ONLY a full four-part value counts as a frame timecode. `00:01:23` is
    /// valid in both notations and means completely different things —
    /// 1m23s to the clock parser, 1s+23f (≈2s at 24fps) to the frame parser —
    /// so honouring the shorter form here would silently store a time 42×
    /// off from what the user typed. Four parts is also exactly what the grid
    /// displays in frame mode, so nothing legitimate is lost; anything shorter
    /// is read as a clock time and then snapped to the frame grid.
    private func parseTime(_ text: String) -> Double? {
        guard let frameRate else { return parseTimestampInput(text) }
        let isFullFrameTimecode = text.trimmingCharacters(in: .whitespaces)
            .split(separator: ":", omittingEmptySubsequences: false).count == 4
        if isFullFrameTimecode, let t = parseFrameTimecode(text, fps: frameRate) { return t }
        return parseTimestampInput(text).map { snapToFrame($0, fps: frameRate) }
    }

    private func durationColor(_ q: CueQuality) -> Color {
        if q.negativeDuration { return GlyphColor.warn }
        if q.durationTooShort || q.durationTooLong || q.cpsTooHigh { return GlyphColor.amber }
        return GlyphColor.quiet
    }

    /// Custom row background/selection/active-spine — see CueRowView.
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row < rows.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("CueRowView")
        let view = (tableView.makeView(withIdentifier: id, owner: self) as? CueRowView) ?? CueRowView()
        view.identifier = id
        let cue = rows[row]
        view.isActiveCue = cue.id == lastActiveCueId
        // Rows scrolled into view mid-playback must arrive already marked;
        // syncPlayback only touches rows that exist at the moment it runs.
        view.isPlayingCue = playingCueIds.contains(cue.id)
        view.overlapColor = overlapSlots[cue.id].map { GlyphColor.overlapPalette[$0] }
        return view
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

    private func makeLabel(_ text: String, alignment: NSTextAlignment, mono: Bool, color: Color) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.alignment = alignment
        field.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 12)
        field.textColor = NSColor(color)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    /// Encodes (column, cue id) in the field's identifier so the delegate can
    /// route a commit without a per-row closure allocation dance.
    private func makeEditableField(cue: Cue, column: CueColumn, text: String, mono: Bool, alignment: NSTextAlignment, color: Color) -> NSView {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = alignment
        field.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 12)
        field.textColor = NSColor(color)
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

    /// A hard issue (broken/conflicting timing) reads as rose; a soft one
    /// (a style-guide number exceeded — CPS, duration, line length) reads as
    /// amber, so the dot's color alone says how urgent the problem is before
    /// the tooltip even names it.
    private func makeFlagView(quality q: CueQuality) -> NSView {
        let container = NSView()
        // The dot is pure color with no text, so its meaning is invisible to
        // VoiceOver unless spelled out here.
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.staticText)
        guard hasAnyIssue(q) else {
            container.setAccessibilityLabel(t("a11yNoIssues"))
            return container
        }
        container.setAccessibilityLabel(t("a11yQualityIssues", issueSummary(q).replacingOccurrences(of: "\n", with: ", ")))
        let isHardIssue = q.negativeDuration || q.overlapsPrev
        let dot = NSView(frame: NSRect(x: 4, y: 9, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(isHardIssue ? GlyphColor.warn : GlyphColor.amber).cgColor
        dot.layer?.cornerRadius = 3
        container.addSubview(dot)
        container.toolTip = issueSummary(q)
        return container
    }

    private func issueSummary(_ q: CueQuality) -> String {
        var items: [String] = []
        if q.negativeDuration { items.append(t("negativeDuration")) }
        if q.overlapsPrev { items.append(t("overlap")) }
        if q.cpsTooHigh { items.append(t("cpsHigh")) }
        if q.durationTooShort { items.append(t("tooShort")) }
        if q.durationTooLong { items.append(t("tooLong")) }
        if q.lineTooLong { items.append(t("lineTooLong")) }
        if q.tooManyLines { items.append(t("tooManyLines")) }
        return items.joined(separator: "\n")
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
            guard let t = parseTime(value) else { reload(force: true); return }
            document.updateCue(cueId) { $0.start = t }
        case .end:
            guard let t = parseTime(value) else { reload(force: true); return }
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
        guard let rawNow = playheadProvider?(), let activeId = document.activeCueId,
              let idx = rows.firstIndex(where: { $0.id == activeId }) else { return }
        // The playhead lands wherever decode happened to stop; a boundary set
        // from it is only frame-exact if we quantize it here.
        let tNow = frameRate.map { snapToFrame(rawNow, fps: $0) } ?? rawNow
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
        menu.addItem(withTitle: menuLabel("inlineTagEditor"), action: #selector(ctxEditTags), keyEquivalent: "").target = self
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
