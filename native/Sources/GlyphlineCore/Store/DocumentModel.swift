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
        history = []
        future = []
    }

    public func loadFromRaw(_ raw: String, format: SubFormat) {
        let newDoc = adapterForFormat(format).parse(raw)
        pushHistory()
        doc = newDoc
        activeCueId = newDoc.cues.first?.id
        selectedIds = []
    }

    /// Restore a document from the crash-recovery autosave (stays dirty until saved).
    public func restoreDoc(_ restored: SubtitleDocument, filePath: String?, fileName: String?) {
        doc = restored
        self.filePath = filePath
        self.fileName = fileName
        isDirty = true // recovered content is unsaved by definition
        activeCueId = restored.cues.first?.id
        selectedIds = []
        history = []
        future = []
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
    /// the translation column (falls back to `text`); ASS spans/tokens are
    /// dropped there since they describe the ORIGINAL text.
    public enum ExportSource { case text, translation }
    public func exportContent(format: SubFormat, source: ExportSource = .text) -> String {
        var exportDoc = doc
        if source == .translation {
            exportDoc.cues = doc.cues.map { cue in
                var c = cue
                if let t = cue.translation, !t.trimmed().isEmpty { c.text = t }
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

    public func deleteCues(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pushHistory()
        let idSet = Set(ids)
        withCues(doc.cues.filter { !idSet.contains($0.id) })
        selectedIds = []
        activeCueId = nil
    }

    /// Split at `atTime`: multi-line text splits at the midpoint line break, else
    /// by half character length.
    public func splitCue(_ id: String, atTime: Double) {
        guard let cue = doc.cues.first(where: { $0.id == id }), atTime > cue.start, atTime < cue.end else { return }
        pushHistory()
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

        var next = doc.cues
        if let idx = next.firstIndex(where: { $0.id == id }) {
            next.replaceSubrange(idx...idx, with: [first, second])
        }
        withCues(next)
        activeCueId = second.id
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
        return { s in
            let lower = s.lowercased()
            guard let re = try? NSRegularExpression(pattern: #"\p{L}+"#) else { return lower }
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

/// Remove hearing-impaired annotations: bracketed/parenthesized runs like
/// "[music]", "(door slams)", "♪ lyrics ♪", and leading "NAME:" speaker labels.
private func stripHearingImpaired(_ text: String) -> String {
    let bracketRe = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^)]*\\)|（[^）]*）|【[^】]*】")
    let musicRe = try! NSRegularExpression(pattern: "♪[^♪]*♪|♪.*$")
    let nameRe = try! NSRegularExpression(pattern: #"^\s*[-–—]?\s*[\p{Lu}][\p{Lu} .'-]{1,20}:\s*"#)
    let spacesRe = try! NSRegularExpression(pattern: #"\s{2,}"#)

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
