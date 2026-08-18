// The single editable document + undo/redo + every edit action (ported from
// ../../src/stores/useSubtitleStore.ts).
//
// Swift value semantics make undo/redo nearly free: `SubtitleDocument` is a
// struct, so snapshots are copy-on-write — no `structuredClone` equivalent
// needed. History holds `doc` snapshots only (matching the TS store, which
// does NOT snapshot selection/activeCue).
//
// Cue patches use a mutating-closure shape (`(inout Cue) -> Void`) rather than
// a JS-style partial-object patch — the natural Swift idiom, and it sidesteps
// the double-optional problem of distinguishing "unset" from "set to nil"
// (e.g. clearing `translation`).
//
// File I/O (open/save/export) is deferred to M6 (Platform/) — this model only
// covers in-memory document state, matching M1's scope.

import Observation
import Foundation

private let MAX_HISTORY = 50

public typealias CueEdit = (inout Cue) -> Void
public typealias StyleEdit = (inout AssStyle) -> Void

public enum CaseMode: String, Sendable { case upper, lower, sentence, title }
public enum EditScope: String, Sendable { case all, selected }

@Observable
public final class DocumentModel {
    public private(set) var doc: SubtitleDocument
    public var filePath: String?
    public var fileName: String?
    public private(set) var isDirty: Bool
    public var activeCueId: String?
    public var selectedIds: Set<String>
    /// Which translation "slot" the grid/editor-box/find-replace/spellcheck/
    /// term-consistency currently read and write — 0 is always the plain
    /// `translation` field, 1+ indexes into `doc.translationLanguages`. Pure
    /// session state (not persisted, not undo-tracked): resets to 0 whenever
    /// a document loads, same as `activeCueId`.
    public var activeTranslationLanguageIndex: Int = 0

    private var history: [SubtitleDocument] = []
    private var future: [SubtitleDocument] = []

    public init(doc: SubtitleDocument = .empty(.srt)) {
        self.doc = doc
        self.filePath = nil
        self.fileName = nil
        self.isDirty = false
        self.activeCueId = nil
        self.selectedIds = []
    }

    public var canUndo: Bool { !history.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// One entry per undoable step, oldest first, with the CURRENT state last.
    /// Cue counts are the only summary offered: history holds whole-document
    /// snapshots, so saying what actually changed at each step would mean
    /// diffing every pair, and a wrong label is worse than a plain one.
    public struct HistoryEntry: Sendable, Equatable, Identifiable {
        public let index: Int
        public let cueCount: Int
        /// Steps back from the present. 0 = current state.
        public let stepsBack: Int
        public var isCurrent: Bool { stepsBack == 0 }
        public var id: Int { index }
    }

    public var historyEntries: [HistoryEntry] {
        let all = history + [doc]
        return all.enumerated().map { i, snapshot in
            HistoryEntry(index: i, cueCount: snapshot.cues.count, stepsBack: all.count - 1 - i)
        }
    }

    /// Jumps to a point in history by replaying undo/redo, so the stacks stay
    /// consistent — reaching in and swapping `doc` directly would strand
    /// entries on the wrong side and make the next undo jump somewhere random.
    public func jumpToHistory(stepsBack: Int) {
        guard stepsBack > 0 else { return }
        for _ in 0..<stepsBack {
            guard canUndo else { return }
            undo()
        }
    }

    /// While a continuous gesture is in flight, only its FIRST mutation
    /// snapshots history — see beginInteractive().
    private var interactiveActive = false
    private var interactiveDidSnapshot = false

    /// Coalesces everything until `endInteractive()` into ONE undo entry.
    ///
    /// Continuous gestures (dragging a cue edge on the waveform) mutate the
    /// document on every mouse-move frame so the grid, waveform, and video
    /// overlay all track live. Without this, one drag would bury the user's
    /// real history under dozens of near-identical entries, making undo
    /// useless. Nesting is not supported: a second begin() without an
    /// intervening end() just continues the current group.
    public func beginInteractive() {
        guard !interactiveActive else { return }
        interactiveActive = true
        interactiveDidSnapshot = false
    }

    public func endInteractive() {
        interactiveActive = false
    }

    /// Snapshot current doc into history before a mutation.
    private func pushHistory() {
        if interactiveActive {
            guard !interactiveDidSnapshot else {
                isDirty = true
                return
            }
            interactiveDidSnapshot = true
        }
        history.append(doc)
        if history.count > MAX_HISTORY { history.removeFirst(history.count - MAX_HISTORY) }
        future = []
        isDirty = true
    }

    private func withCues(_ cues: [Cue]) {
        doc.cues = cues
    }

    // ── file lifecycle (in-memory only; disk I/O is M6) ─────────────────────────

    public func newDocument() {
        doc = .empty(.srt)
        filePath = nil
        fileName = nil
        isDirty = false
        activeCueId = nil
        selectedIds = []
        activeTranslationLanguageIndex = 0
        history = []
        future = []
    }

    /// Load an already-read document (parsing/decoding happens at the M6 I/O layer).
    public func loadParsed(_ newDoc: SubtitleDocument, filePath: String? = nil, fileName: String? = nil) {
        doc = newDoc
        self.filePath = filePath
        self.fileName = fileName
        isDirty = false
        activeCueId = newDoc.cues.first?.id
        selectedIds = []
        activeTranslationLanguageIndex = 0
        history = []
        future = []
    }

    public func loadFromRaw(_ raw: String, format: SubFormat) {
        let newDoc = adapterForFormat(format).parse(raw)
        pushHistory()
        doc = newDoc
        activeCueId = newDoc.cues.first?.id
        selectedIds = []
        activeTranslationLanguageIndex = 0
    }

    /// Restore a document from the crash-recovery autosave (stays dirty until saved).
    public func restoreDoc(_ restored: SubtitleDocument, filePath: String?, fileName: String?) {
        doc = restored
        self.filePath = filePath
        self.fileName = fileName
        isDirty = true // recovered content is unsaved by definition
        activeCueId = restored.cues.first?.id
        selectedIds = []
        activeTranslationLanguageIndex = 0
        history = []
        future = []
    }

    /// Restores a dirty flag captured before the document's content was
    /// swapped out — the multi-tab switcher needs this: `loadParsed` always
    /// resets to clean, but the tab being switched IN might have had unsaved
    /// edits at the moment it was switched away from.
    public func restoreDirtyFlag(_ dirty: Bool) {
        isDirty = dirty
    }

    public func markSaved(path: String, name: String) {
        filePath = path
        fileName = name
        isDirty = false
    }

    public func serializeCurrent() -> String {
        adapterForFormat(doc.format).serialize(doc)
    }

    /// Export doc content in `format`. `source: .translation` swaps the body to
    /// a translation column (falls back to `text`); ASS spans/tokens are
    /// dropped there since they describe the ORIGINAL text. `translationIndex`
    /// selects WHICH translation language — 0 (the default) is the plain
    /// `translation` field, exactly today's behavior; 1+ exports an
    /// additional language via `Cue.translationText(at:languages:)`.
    public enum ExportSource { case text, translation }
    public func exportContent(
        format: SubFormat,
        source: ExportSource = .text,
        translationIndex: Int = 0,
        scope: ExportScope = .all,
        rebaseToZero: Bool = false
    ) -> String {
        var exportDoc = subsetDocument(doc, scope: scope, rebaseToZero: rebaseToZero)
        if source == .translation {
            let languages = doc.translationLanguages ?? []
            exportDoc.cues = exportDoc.cues.map { cue in
                var c = cue
                if let t = cue.translationText(at: translationIndex, languages: languages), !t.trimmed().isEmpty {
                    c.text = t
                }
                c.assSpans = nil
                c.tokens = nil
                return c
            }
        }
        return adapterForFormat(format).serialize(exportDoc)
    }

    // ── selection ────────────────────────────────────────────────────────────

    public func setActiveCue(_ id: String?) { activeCueId = id }

    public func toggleSelect(_ id: String, additive: Bool) {
        var next = additive ? selectedIds : []
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        selectedIds = next
        activeCueId = id
    }

    /// Select every cue between the anchor and `toId` (inclusive, time-sorted).
    public func selectRange(anchorId: String, toId: String) {
        let order = sortedCues(doc.cues)
        guard let a = order.firstIndex(where: { $0.id == anchorId }),
              let b = order.firstIndex(where: { $0.id == toId }) else { return }
        let (lo, hi) = a <= b ? (a, b) : (b, a)
        selectedIds = Set(order[lo...hi].map(\.id))
        activeCueId = toId
    }

    public func clearSelection() { selectedIds = [] }

    // ── editing ──────────────────────────────────────────────────────────────

    public func updateCue(_ id: String, _ edit: CueEdit) {
        pushHistory()
        withCues(doc.cues.map { cue in
            guard cue.id == id else { return cue }
            var c = cue
            edit(&c)
            return c
        })
    }

    /// Apply many cue patches as ONE undo step (find&replace "replace all" etc.).
    public func batchUpdateCues(_ edits: [(id: String, edit: CueEdit)]) {
        guard !edits.isEmpty else { return }
        pushHistory()
        var byId: [String: CueEdit] = [:]
        for e in edits { byId[e.id] = e.edit }
        withCues(doc.cues.map { cue in
            guard let edit = byId[cue.id] else { return cue }
            var c = cue
            edit(&c)
            return c
        })
    }

    /// Shared by fixOverlaps (gapSec=0) and applyMinGap: shrink each cue's end so
    /// it's followed by at least `gapSec` before the next cue starts.
    @discardableResult
    private func applyGapClamps(_ gapSec: Double) -> Int {
        let sorted = sortedCues(doc.cues)
        var clamps: [String: Double] = [:]
        for i in 0..<max(0, sorted.count - 1) {
            let cur = sorted[i], next = sorted[i + 1]
            if next.start - cur.end < gapSec {
                clamps[cur.id] = max(cur.start + 0.001, next.start - gapSec)
            }
        }
        guard !clamps.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.map { cue in
            guard let end = clamps[cue.id] else { return cue }
            var c = cue; c.end = end; return c
        })
        return clamps.count
    }

    /// Clamp each cue's end to the next cue's start (sorted order). Returns #fixed.
    @discardableResult
    public func fixOverlaps() -> Int { applyGapClamps(0) }

    /// Shrink cue ends so every cue is followed by at least `gapSec` of silence.
    @discardableResult
    public func applyMinGap(_ gapSec: Double) -> Int { applyGapClamps(gapSec) }

    /// Stretch/shrink each cue's end to sit within [minSec, maxSec] (never past
    /// the next cue). Returns #changed.
    @discardableResult
    public func applyDurationLimits(minSec: Double, maxSec: Double) -> Int {
        let sorted = sortedCues(doc.cues)
        var patches: [String: Double] = [:]
        for i in 0..<sorted.count {
            let cue = sorted[i]
            let next = i + 1 < sorted.count ? sorted[i + 1] : nil
            var end = cue.end
            let dur = end - cue.start
            if dur > maxSec {
                end = cue.start + maxSec
            } else if dur < minSec {
                let cap = next.map { max(cue.start + 0.001, $0.start - 0.001) } ?? .infinity
                end = min(cue.start + minSec, cap)
            }
            if end != cue.end { patches[cue.id] = end }
        }
        guard !patches.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.map { cue in
            guard let end = patches[cue.id] else { return cue }
            var c = cue; c.end = end; return c
        })
        return patches.count
    }

    /// Broadcast timecode display settings — see DropFrameTimecode.swift.
    /// Document metadata, not cue content, but still an undo-able edit like
    /// everything else here rather than a silent side channel.
    public func setTimecodeStartOffsetSec(_ v: Double) {
        guard doc.timecodeStartOffsetSec != v else { return }
        pushHistory()
        doc.timecodeStartOffsetSec = v
    }
    public func setTimecodeDropFrame(_ v: Bool) {
        guard doc.timecodeDropFrame != v else { return }
        pushHistory()
        doc.timecodeDropFrame = v
    }

    /// Adds resolved system fonts to `doc.fonts` (task N's collector hands
    /// these in already UU-encoded — see FontCollector.swift, app target).
    @discardableResult
    public func addEmbeddedFonts(_ fonts: [AssEmbedded]) -> Int {
        guard !fonts.isEmpty else { return 0 }
        pushHistory()
        doc.fonts = (doc.fonts ?? []) + fonts
        return fonts.count
    }

    /// Rescales styles + inline position/size overrides to a new PlayRes —
    /// see ResolutionResample.swift. One undo entry for the whole document.
    public func resampleResolution(toWidth: Double, toHeight: Double) {
        let resampled = GlyphlineCore.resampleDocument(doc, toWidth: toWidth, toHeight: toHeight)
        // resampleDocument itself no-ops when the target matches the current
        // resolution — guard here too, so picking "Apply" on an unchanged
        // size doesn't push an empty undo step (matches every other action
        // in this file: push only once a real change is known).
        guard resampled != doc else { return }
        pushHistory()
        doc = resampled
    }

    /// Give text a beat before it appears and after it leaves, without eating
    /// into a neighboring cue. Returns #cues changed.
    @discardableResult
    public func applyLeadInOut(leadInSec: Double, leadOutSec: Double) -> Int {
        let (out, changed) = GlyphlineCore.applyLeadInOut(doc.cues, leadInSec: leadInSec, leadOutSec: leadOutSec)
        guard changed > 0 else { return 0 }
        pushHistory()
        withCues(out)
        return changed
    }

    /// Closes gaps short enough to read as flicker rather than a deliberate
    /// pause. Returns #cues extended.
    @discardableResult
    public func bridgeSmallGaps(maxGapSec: Double) -> Int {
        let (out, changed) = GlyphlineCore.bridgeSmallGaps(doc.cues, maxGapSec: maxGapSec)
        guard changed > 0 else { return 0 }
        pushHistory()
        withCues(out)
        return changed
    }

    /// Quantizes every cue's start/end to the nearest detected shot change
    /// within tolerance. Returns #cues changed.
    @discardableResult
    public func snapToSceneCuts(_ sceneCuts: [Double], toleranceSec: Double) -> Int {
        let (out, changed) = GlyphlineCore.snapCuesToSceneCuts(doc.cues, sceneCuts: sceneCuts, toleranceSec: toleranceSec)
        guard changed > 0 else { return 0 }
        pushHistory()
        withCues(out)
        return changed
    }

    /// Delete cues whose text (and translation) is blank. Returns #removed.
    @discardableResult
    public func removeEmptyCues() -> Int {
        let empty = doc.cues.filter { $0.text.trimmed().isEmpty && ($0.translation ?? "").trimmed().isEmpty }
        guard !empty.isEmpty else { return 0 }
        pushHistory()
        let idSet = Set(empty.map(\.id))
        withCues(doc.cues.filter { !idSet.contains($0.id) })
        selectedIds.subtract(idSet)
        if let active = activeCueId, idSet.contains(active) { activeCueId = nil }
        return empty.count
    }

    /// Transform cue text casing (all cues, or only the current selection).
    @discardableResult
    public func changeCase(mode: CaseMode, scope: EditScope) -> Int {
        let targets = scope == .selected ? doc.cues.filter { selectedIds.contains($0.id) } : doc.cues
        guard !targets.isEmpty else { return 0 }
        let transform = casingTransform(mode)
        let idSet = Set(targets.map(\.id))
        let changed = targets.filter { transform($0.text) != $0.text }.count
        guard changed > 0 else { return 0 }
        pushHistory()
        withCues(doc.cues.map { cue in
            guard idSet.contains(cue.id) else { return cue }
            var c = cue; c.text = transform(cue.text); return c
        })
        return changed
    }

    /// Rebreak over-long cues into balanced lines. The counterpart to the
    /// quality check's "line too long" / "too many lines" flags, which until
    /// now reported problems the app gave you no way to fix.
    @discardableResult
    public func rebreakLines(maxLineLength: Int, maxLines: Int, style: LineBreakStyle = .auto, ids: [String]? = nil) -> Int {
        let scope = ids.map { set in doc.cues.filter { Set(set).contains($0.id) } } ?? doc.cues
        return applyTextPatches(rebreakCues(scope, maxLineLength: maxLineLength, maxLines: maxLines, style: style))
    }

    /// Collapse every cue back onto one line.
    @discardableResult
    public func unbreakAllLines(ids: [String]? = nil) -> Int {
        let scope = ids.map { set in doc.cues.filter { Set(set).contains($0.id) } } ?? doc.cues
        return applyTextPatches(unbreakCues(scope))
    }

    /// Applies id→text edits as ONE undo entry. Shared by the text-rewriting
    /// batch actions so they can't drift apart in history behaviour.
    @discardableResult
    private func applyTextPatches(_ patches: [String: String]) -> Int {
        guard !patches.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.map { cue in
            guard let text = patches[cue.id] else { return cue }
            var c = cue; c.text = text; return c
        })
        return patches.count
    }

    // ── karaoke / word-level timing ────────────────────────────────────────

    /// Creates evenly spaced tokens for a cue — the starting point for timing.
    public func generateTokens(for id: String) {
        guard let cue = doc.cues.first(where: { $0.id == id }) else { return }
        let tokens = makeEvenTokens(for: cue)
        guard !tokens.isEmpty else { return }
        updateCue(id) { $0.tokens = tokens }
    }

    public func clearTokens(for id: String) {
        guard doc.cues.first(where: { $0.id == id })?.tokens != nil else { return }
        updateCue(id) { $0.tokens = nil }
    }

    /// Drags the boundary between two tokens. Interactive by design: the whole
    /// drag lands as one undo entry via begin/endInteractive, like the waveform.
    public func moveTokenBoundary(for id: String, index: Int, to time: Double) {
        guard let cue = doc.cues.first(where: { $0.id == id }), let tokens = cue.tokens else { return }
        let next = GlyphlineCore.moveTokenBoundary(tokens, index: index, to: time)
        guard next != tokens else { return }
        updateCue(id) { $0.tokens = next }
    }

    /// Append another document's cues, shifted by `offset`. One undo entry.
    @discardableResult
    public func appendDocument(_ other: SubtitleDocument, offset: Double) -> Int {
        guard !other.cues.isEmpty else { return 0 }
        pushHistory()
        doc = GlyphlineCore.appendDocument(doc, other, offset: offset)
        return other.cues.count
    }

    /// Drops every cue at or after `time` from THIS document and returns them
    /// as a separate one for the caller to save. Splitting is destructive to
    /// the open document, so it goes through history like any other edit.
    public func splitOffTail(at time: Double, rebase: Bool) -> SubtitleDocument {
        let parts = GlyphlineCore.splitDocument(doc, at: time, rebaseSecond: rebase)
        guard !parts.second.cues.isEmpty else { return parts.second }
        pushHistory()
        doc = parts.first
        selectedIds = []
        activeCueId = sortedCues(doc.cues).last?.id
        return parts.second
    }

    /// Apply mechanical typography fixes (see TextTidy). One undo entry for the
    /// whole selection of rules, so a cleanup pass is a single step to reverse.
    @discardableResult
    public func tidyText(rules: [TidyRule], ids: [String]? = nil) -> Int {
        let scope = ids.map { set in doc.cues.filter { Set(set).contains($0.id) } } ?? doc.cues
        return applyTextPatches(tidyCues(scope, rules: rules))
    }

    /// Apply a saved house-style rule set (see CustomRules.swift). Same
    /// one-undo-entry shape as tidyText.
    @discardableResult
    public func applyCustomRules(_ rules: [CustomRule], ids: [String]? = nil) -> Int {
        let scope = ids.map { set in doc.cues.filter { Set(set).contains($0.id) } } ?? doc.cues
        return applyTextPatches(GlyphlineCore.applyCustomRules(toCues: scope, rules: rules))
    }

    /// Strip bracket/parenthesis annotations, e.g. "(door slams)", "[music]".
    @discardableResult
    public func removeHearingImpaired() -> Int {
        var patches: [String: String] = [:]
        for cue in doc.cues {
            let next = stripHearingImpaired(cue.text)
            if next != cue.text { patches[cue.id] = next }
        }
        guard !patches.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.map { cue in
            guard let text = patches[cue.id] else { return cue }
            var c = cue; c.text = text; return c
        })
        return patches.count
    }

    /// Two-point linear sync: remaps every cue/token timestamp so `srcA`→`dstA`
    /// and `srcB`→`dstB`, interpolating (and extrapolating) everything else.
    /// Returns false if the two source points coincide (undefined transform).
    @discardableResult
    public func applyPointSync(srcA: Double, dstA: Double, srcB: Double, dstB: Double) -> Bool {
        guard srcB != srcA else { return false }
        let scale = (dstB - dstA) / (srcB - srcA)
        func remap(_ t: Double) -> Double { dstA + (t - srcA) * scale }
        pushHistory()
        withCues(doc.cues.map { cue in
            var c = cue
            c.start = max(0, remap(cue.start))
            c.end = max(0, remap(cue.end))
            c.tokens = cue.tokens?.map { tk in
                var t = tk
                t.start = max(0, remap(tk.start))
                t.end = max(0, remap(tk.end))
                return t
            }
            return c
        })
        return true
    }

    /// Multiply every timestamp by `factor` (framerate conversion etc.).
    /// Returns false for factor ≤ 0.
    @discardableResult
    public func changeSpeed(_ factor: Double) -> Bool {
        guard factor > 0 else { return false }
        pushHistory()
        func scale(_ t: Double) -> Double { t * factor }
        withCues(doc.cues.map { cue in
            var c = cue
            c.start = scale(cue.start)
            c.end = scale(cue.end)
            c.tokens = cue.tokens?.map { tk in
                var t = tk; t.start = scale(tk.start); t.end = scale(tk.end); return t
            }
            return c
        })
        return true
    }

    /// Merge adjacent cues showing the same text with a small gap between them
    /// (≤250 ms — Subtitle Edit's default; a repeat minutes later stays separate).
    @discardableResult
    public func mergeSameText() -> Int {
        let MAX_GAP = 0.25
        let sorted = sortedCues(doc.cues)
        var removed: Set<String> = []
        var extend: [String: Double] = [:]
        var survivor: Cue?
        for cue in sorted {
            if let s = survivor,
               cue.text.trimmed() == s.text.trimmed(),
               cue.start - (extend[s.id] ?? s.end) <= MAX_GAP {
                removed.insert(cue.id)
                extend[s.id] = max(extend[s.id] ?? s.end, cue.end)
            } else {
                survivor = cue
            }
        }
        guard !removed.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.filter { !removed.contains($0.id) }.map { cue in
            guard let end = extend[cue.id] else { return cue }
            var c = cue; c.end = end; return c
        })
        selectedIds.subtract(removed)
        if let active = activeCueId, removed.contains(active) { activeCueId = nil }
        return removed.count
    }

    /// Merge cues sharing identical start+end (±1ms, stacked lines) into one,
    /// joining text with a newline.
    @discardableResult
    public func mergeSameTimecodes() -> Int {
        let EPS = 0.001
        let sorted = sortedCues(doc.cues)
        var removed: Set<String> = []
        var joined: [String: String] = [:]
        var survivor: Cue?
        for cue in sorted {
            if let s = survivor, abs(cue.start - s.start) <= EPS, abs(cue.end - s.end) <= EPS {
                removed.insert(cue.id)
                joined[s.id] = "\(joined[s.id] ?? s.text)\n\(cue.text)"
            } else {
                survivor = cue
            }
        }
        guard !removed.isEmpty else { return 0 }
        pushHistory()
        withCues(doc.cues.filter { !removed.contains($0.id) }.map { cue in
            guard let text = joined[cue.id] else { return cue }
            var c = cue; c.text = text; return c
        })
        selectedIds.subtract(removed)
        if let active = activeCueId, removed.contains(active) { activeCueId = nil }
        return removed.count
    }

    public func addCue() {
        pushHistory()
        let last = sortedCues(doc.cues).last
        let start = last.map { $0.end + 0.001 } ?? 0
        let cue = Cue(id: newCueId(), start: start, end: start + 2, text: "")
        withCues(doc.cues + [cue])
        activeCueId = cue.id
    }

    public func addCueAt(start: Double, end: Double) {
        pushHistory()
        let cue = Cue(id: newCueId(), start: start, end: max(end, start + 0.001), text: "")
        withCues(doc.cues + [cue])
        activeCueId = cue.id
    }

    /// Lays down a blank cue for each detected speech segment that doesn't
    /// already overlap an existing cue — skipping overlaps means running this
    /// again after manually timing part of the file only fills in the gaps,
    /// rather than duplicating work already done. Returns #cues added.
    @discardableResult
    public func addCuesFromSpeechSegments(_ segments: [SpeechSegment]) -> Int {
        let existing = doc.cues
        let fresh = segments.filter { seg in
            !existing.contains { $0.start < seg.end && $0.end > seg.start }
        }
        guard !fresh.isEmpty else { return 0 }
        pushHistory()
        let newCues = fresh.map { Cue(id: newCueId(), start: $0.start, end: $0.end, text: "") }
        withCues(doc.cues + newCues)
        return newCues.count
    }

    public func insertCueAfter(_ id: String) {
        pushHistory()
        let ref = doc.cues.first { $0.id == id }
        let start = ref.map { $0.end + 0.001 } ?? 0
        let cue = Cue(id: newCueId(), start: start, end: start + 2, text: "")
        var next = doc.cues
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next.insert(cue, at: idx + 1)
        } else {
            next.append(cue)
        }
        withCues(next)
        activeCueId = cue.id
    }

    /// Inserts a blank cue after each cue in `ids` — one undo entry for the
    /// whole batch (a loop over insertCueAfter would leave one entry per
    /// insertion instead), for the context menu's "Insert After" acting on a
    /// multi-selection instead of only the row that was clicked.
    public func insertCueAfterEach(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pushHistory()
        var next = doc.cues
        var lastInsertedId: String?
        // Resolved from the ORIGINAL array so every insertion point reflects
        // this batch's starting state, not cues this same batch already added.
        let refs = doc.cues.filter { ids.contains($0.id) }
        for ref in refs {
            let start = ref.end + 0.001
            let cue = Cue(id: newCueId(), start: start, end: start + 2, text: "")
            if let idx = next.firstIndex(where: { $0.id == ref.id }) {
                next.insert(cue, at: idx + 1)
            } else {
                next.append(cue)
            }
            lastInsertedId = cue.id
        }
        withCues(next)
        if let lastInsertedId { activeCueId = lastInsertedId }
    }

    /// Copy text/style/actor/spans; place right after, shifted by its duration
    /// (min 0.5s) so it doesn't sit exactly on top of the original.
    public func duplicateCue(_ id: String) {
        guard let ref = doc.cues.first(where: { $0.id == id }) else { return }
        pushHistory()
        let dur = max(0.5, ref.end - ref.start)
        var copy = ref
        copy.id = newCueId()
        copy.start = ref.end + 0.001
        copy.end = ref.end + 0.001 + dur
        var next = doc.cues
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next.insert(copy, at: idx + 1)
        } else {
            next.append(copy)
        }
        withCues(next)
        activeCueId = copy.id
        selectedIds = [copy.id]
    }

    /// Duplicates every cue in `ids` — one undo entry for the whole batch,
    /// for the context menu's "Duplicate" acting on a multi-selection
    /// instead of only the row that was clicked. Selects all the copies
    /// afterward, same spirit as duplicateCue selecting its one copy.
    public func duplicateCues(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pushHistory()
        var next = doc.cues
        let refs = doc.cues.filter { ids.contains($0.id) }
        var newIds: [String] = []
        for ref in refs {
            let dur = max(0.5, ref.end - ref.start)
            var copy = ref
            copy.id = newCueId()
            copy.start = ref.end + 0.001
            copy.end = ref.end + 0.001 + dur
            newIds.append(copy.id)
            if let idx = next.firstIndex(where: { $0.id == ref.id }) {
                next.insert(copy, at: idx + 1)
            } else {
                next.append(copy)
            }
        }
        withCues(next)
        if let last = newIds.last { activeCueId = last }
        selectedIds = Set(newIds)
    }

    /// Deletes `ids` and selects whichever cue slides into their place, falling
    /// back to the last remaining cue. Clearing the selection outright meant
    /// losing your position in the document on every delete — with nothing
    /// selected, the next delete/split/timing shortcut also silently did
    /// nothing until you clicked back into the list.
    public func deleteCues(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pushHistory()
        let idSet = Set(ids)
        let ordered = sortedCues(doc.cues)
        let firstDeletedIdx = ordered.firstIndex { idSet.contains($0.id) }
        withCues(doc.cues.filter { !idSet.contains($0.id) })

        let survivor: Cue? = {
            guard let i = firstDeletedIdx else { return nil }
            // The nearest surviving cue at or after the deletion point; if the
            // deletion ran to the end of the document, the new last cue.
            return ordered[i...].first { !idSet.contains($0.id) }
                ?? ordered[..<i].last { !idSet.contains($0.id) }
        }()
        activeCueId = survivor?.id
        selectedIds = survivor.map { [$0.id] } ?? []
    }

    /// Split at `atTime`: multi-line text splits at the midpoint line break, else
    /// by half character length.
    /// The pure half of a split: two cues from one, dividing the text at the
    /// midpoint line break (multi-line) or midpoint character (single-line).
    /// nil when `atTime` doesn't actually fall inside `cue`.
    private func splitCueValue(_ cue: Cue, atTime: Double) -> (first: Cue, second: Cue)? {
        guard atTime > cue.start, atTime < cue.end else { return nil }
        let lines = cue.text.components(separatedBy: "\n")
        var firstText = cue.text
        var secondText = ""
        if lines.count > 1 {
            let mid = Int((Double(lines.count) / 2).rounded(.up))
            firstText = lines[0..<mid].joined(separator: "\n")
            secondText = lines[mid...].joined(separator: "\n")
        } else {
            let chars = Array(cue.text)
            let mid = Int((Double(chars.count) / 2).rounded(.up))
            firstText = String(chars[0..<mid]).trimmed()
            secondText = String(chars[mid...]).trimmed()
        }
        var first = cue; first.end = atTime; first.text = firstText; first.tokens = nil
        var second = cue; second.id = newCueId(); second.start = atTime; second.text = secondText; second.tokens = nil
        return (first, second)
    }

    public func splitCue(_ id: String, atTime: Double) {
        guard let cue = doc.cues.first(where: { $0.id == id }),
              let (first, second) = splitCueValue(cue, atTime: atTime) else { return }
        pushHistory()
        var next = doc.cues
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next.replaceSubrange(idx...idx, with: [first, second])
        }
        withCues(next)
        activeCueId = second.id
    }

    /// Splits every cue in `ids` at ITS OWN split point — the playhead if it
    /// falls inside that particular cue, else that cue's own midpoint — as
    /// one undo entry for the whole batch. A cue the split point doesn't
    /// fall inside of (playhead elsewhere and somehow zero-length) is simply
    /// left alone, mirroring splitCue's own guard.
    public func splitCues(_ ids: [String], playhead: Double?) {
        guard !ids.isEmpty else { return }
        var next = doc.cues
        var lastSecondId: String?
        for cue in doc.cues where ids.contains(cue.id) {
            let at = (playhead.map { $0 > cue.start && $0 < cue.end } == true) ? playhead! : (cue.start + cue.end) / 2
            guard let (first, second) = splitCueValue(cue, atTime: at),
                  let idx = next.firstIndex(where: { $0.id == cue.id }) else { continue }
            next.replaceSubrange(idx...idx, with: [first, second])
            lastSecondId = second.id
        }
        guard let lastSecondId else { return }
        pushHistory()
        withCues(next)
        activeCueId = lastSecondId
    }

    public func mergeCues(_ ids: [String]) {
        guard ids.count >= 2 else { return }
        pushHistory()
        let idSet = Set(ids)
        let targets = sortedCues(doc.cues.filter { idSet.contains($0.id) })
        guard let first = targets.first, let last = targets.last else { return }
        var merged = first
        merged.id = newCueId()
        merged.start = first.start
        merged.end = last.end
        merged.text = targets.map(\.text).joined(separator: "\n")
        let allTokens = targets.flatMap { $0.tokens ?? [] }
        merged.tokens = allTokens.isEmpty ? nil : allTokens

        var remaining = doc.cues.filter { !idSet.contains($0.id) }
        let firstIdx = doc.cues.firstIndex { $0.id == first.id } ?? remaining.count
        remaining.insert(merged, at: min(firstIdx, remaining.count))
        withCues(remaining)
        selectedIds = [merged.id]
        activeCueId = merged.id
    }

    public func shiftTime(deltaSec: Double, scope: EditScope) {
        pushHistory()
        func shift(_ cue: Cue) -> Cue {
            guard scope == .all || selectedIds.contains(cue.id) else { return cue }
            var c = cue
            c.start = max(0, cue.start + deltaSec)
            c.end = max(0, cue.end + deltaSec)
            c.tokens = cue.tokens?.map { tk in
                var t = tk
                t.start = max(0, tk.start + deltaSec)
                t.end = max(0, tk.end + deltaSec)
                return t
            }
            return c
        }
        withCues(doc.cues.map(shift))
    }

    // ── proofreading ignore list ─────────────────────────────────────────────

    /// Words the proofreader skips in this project. Undoable like any other
    /// document edit — dismissing a warning is a decision the user may want to
    /// take back.
    public func ignoreWord(_ word: String) {
        let trimmed = word.trimmed()
        guard !trimmed.isEmpty else { return }
        var list = doc.ignoredWords ?? []
        guard !list.contains(trimmed) else { return }
        pushHistory()
        list.append(trimmed)
        doc.ignoredWords = list.sorted()
    }

    // ── glossary (translation consistency) ────────────────────────────────────

    /// Adds or replaces the mapping for `source`. Undoable and marks the
    /// document dirty, because the glossary ships inside the .glyph file.
    /// `language` defaults to nil (applies regardless of active translation
    /// language — today's exact behavior); set it once a project targets
    /// more than one language, since a target term is only correct for ONE
    /// of them.
    public func upsertGlossaryEntry(source: String, target: String, note: String? = nil, language: String? = nil) {
        let src = source.trimmed()
        let tgt = target.trimmed()
        guard !src.isEmpty, !tgt.isEmpty else { return }
        var list = doc.glossary ?? []
        let entry = GlossaryEntry(
            source: src, target: tgt, note: note?.trimmed().isEmpty == false ? note?.trimmed() : nil, language: language)
        if let i = list.firstIndex(where: { $0.source == src && $0.language == language }) {
            guard list[i] != entry else { return }
            pushHistory()
            list[i] = entry
        } else {
            pushHistory()
            list.append(entry)
        }
        doc.glossary = list.sorted { $0.source < $1.source }
    }

    public func removeGlossaryEntry(source: String, language: String? = nil) {
        guard var list = doc.glossary, list.contains(where: { $0.source == source && $0.language == language }) else { return }
        pushHistory()
        list.removeAll { $0.source == source && $0.language == language }
        doc.glossary = list.isEmpty ? nil : list
    }

    // ── translation languages ────────────────────────────────────────────────

    /// Adds a translation language beyond the first. If this document has no
    /// additional languages yet (`doc.translationLanguages` is nil), the
    /// existing, until-now-unlabeled `translation` field becomes language
    /// index 0 — `primaryLanguageCode` labels it (only used for this
    /// bootstrap case; ignored on every later call).
    public func addTranslationLanguage(_ code: String, primaryLanguageCode: String? = nil) {
        let trimmed = code.trimmed()
        guard !trimmed.isEmpty else { return }
        var languages = doc.translationLanguages ?? []
        if languages.isEmpty {
            let primary = primaryLanguageCode?.trimmed()
            languages = [(primary?.isEmpty == false ? primary! : "?")]
        }
        guard !languages.contains(trimmed) else { return }
        pushHistory()
        languages.append(trimmed)
        doc.translationLanguages = languages
    }

    /// Removes the language at `index` and every cue's stored text for it.
    /// Refuses index 0 — that's `cue.translation` itself, which exists
    /// whether or not any additional languages do, so there's nothing
    /// meaningful to "remove" it into.
    public func removeTranslationLanguage(at index: Int) {
        guard var languages = doc.translationLanguages, languages.indices.contains(index), index > 0 else { return }
        pushHistory()
        let code = languages.remove(at: index)
        doc.translationLanguages = languages
        doc.cues = doc.cues.map { cue in
            guard cue.translations?[code] != nil else { return cue }
            var c = cue
            c.translations?[code] = nil
            return c
        }
        if activeTranslationLanguageIndex >= languages.count { activeTranslationLanguageIndex = 0 }
    }

    public func unignoreWord(_ word: String) {
        guard var list = doc.ignoredWords, list.contains(word) else { return }
        pushHistory()
        list.removeAll { $0 == word }
        doc.ignoredWords = list.isEmpty ? nil : list
    }

    // ── styles (ASS) ─────────────────────────────────────────────────────────

    public func addStyle() {
        pushHistory()
        let styles = doc.styles ?? []
        let name = uniqueStyleName(styles, base: "New Style")
        doc.styles = styles + [AssStyle(name: name)]
    }

    /// Renaming a style (set `.name` in `edit`) re-points cues that referenced
    /// the old name.
    public func updateStyle(_ name: String, _ edit: StyleEdit) {
        pushHistory()
        var renamed: String?
        let styles = (doc.styles ?? []).map { style -> AssStyle in
            guard style.name == name else { return style }
            var s = style
            edit(&s)
            if s.name != name { renamed = s.name }
            return s
        }
        doc.styles = styles
        if let renamed {
            doc.cues = doc.cues.map { cue in
                guard cue.style == name else { return cue }
                var c = cue; c.style = renamed; return c
            }
        }
    }

    public func deleteStyle(_ name: String) {
        pushHistory()
        doc.styles = (doc.styles ?? []).filter { $0.name != name }
        // Cues referencing the removed style fall back to nil (Default on export).
        doc.cues = doc.cues.map { cue in
            guard cue.style == name else { return cue }
            var c = cue; c.style = nil; return c
        }
    }

    // ── undo / redo ──────────────────────────────────────────────────────────

    public func undo() {
        guard let prev = history.popLast() else { return }
        future.append(doc)
        if future.count > MAX_HISTORY { future.removeFirst(future.count - MAX_HISTORY) }
        doc = prev
        isDirty = true
    }

    public func redo() {
        guard let next = future.popLast() else { return }
        history.append(doc)
        if history.count > MAX_HISTORY { history.removeFirst(history.count - MAX_HISTORY) }
        doc = next
        isDirty = true
    }
}

// ─── Free helpers (module-private) ─────────────────────────────────────────────

/// Text transform for changeCase. Sentence/title casing is line-aware.
private func casingTransform(_ mode: CaseMode) -> (String) -> String {
    switch mode {
    case .upper: return { $0.uppercased() }
    case .lower: return { $0.lowercased() }
    case .sentence:
        return { s in
            s.components(separatedBy: "\n").map { line -> String in
                let lower = line.lowercased()
                guard let range = lower.range(of: #"\p{L}"#, options: .regularExpression) else { return line }
                let idx = range.lowerBound
                return lower[lower.startIndex..<idx] + lower[idx..<lower.index(after: idx)].uppercased() + lower[lower.index(after: idx)...]
            }.joined(separator: "\n")
        }
    case .title:
        // Compiled once here, not inside the closure — the closure below runs
        // once per cue (Subtitle ▸ 일괄 정리 ▸ 대소문자 변환 applies it across
        // the whole document), and re-parsing the same fixed pattern on every
        // cue was the same wasted-compilation tax found in the format
        // parsers (see RegexCache's doc comment).
        let titleWordRegex = try? NSRegularExpression(pattern: #"\p{L}+"#)
        return { s in
            let lower = s.lowercased()
            guard let re = titleWordRegex else { return lower }
            let ns = lower as NSString
            var result = ""
            var cursor = 0
            for m in re.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let word = ns.substring(with: m.range)
                result += word.prefix(1).uppercased() + word.dropFirst()
                cursor = m.range.location + m.range.length
            }
            result += ns.substring(from: cursor)
            return result
        }
    }
}

// Compiled once at module scope, not inside stripHearingImpaired — that
// function runs once per cue (removeHearingImpaired sweeps the whole
// document), so building these four every call re-paid the compile cost
// thousands of times on a feature-length subtitle file. Same wasted work the
// format parsers had; see RegexCache in FormatCommon.swift.
private let hiBracketRegex = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^)]*\\)|（[^）]*）|【[^】]*】")
private let hiMusicRegex = try! NSRegularExpression(pattern: "♪[^♪]*♪|♪.*$")
private let hiNameRegex = try! NSRegularExpression(pattern: #"^\s*[-–—]?\s*[\p{Lu}][\p{Lu} .'-]{1,20}:\s*"#)
private let hiSpacesRegex = try! NSRegularExpression(pattern: #"\s{2,}"#)

/// Remove hearing-impaired annotations: bracketed/parenthesized runs like
/// "[music]", "(door slams)", "♪ lyrics ♪", and leading "NAME:" speaker labels.
private func stripHearingImpaired(_ text: String) -> String {
    let bracketRe = hiBracketRegex
    let musicRe = hiMusicRegex
    let nameRe = hiNameRegex
    let spacesRe = hiSpacesRegex

    func replace(_ re: NSRegularExpression, _ s: String) -> String {
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    let lines = text.components(separatedBy: "\n").map { line -> String in
        var l = replace(bracketRe, line)
        l = replace(musicRe, l)
        l = replace(nameRe, l)
        l = replace(spacesRe, l).trimmed()
        return l
    }
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
}

private func uniqueStyleName(_ styles: [AssStyle], base: String) -> String {
    let names = Set(styles.map(\.name))
    if !names.contains(base) { return base }
    var i = 2
    while names.contains("\(base) \(i)") { i += 1 }
    return "\(base) \(i)"
}
