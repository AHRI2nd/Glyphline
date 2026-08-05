// Compare two subtitle files, and join/split documents.
//
// COMPARISON: subtitle revisions are not line-edits of a text file — a cue can
// move in time without its text changing (a retime), or change text while
// staying put (a translation fix), and both matter for different reasons. So
// this pairs cues by TIME OVERLAP rather than by index or by a text diff:
// index-pairing breaks completely the moment one cue is inserted, and a text
// diff can't see a retime at all.
//
// Each cue on each side is matched to at most one on the other, greedily by
// how much they overlap, which keeps the result stable and symmetric.

import Foundation

public enum DiffKind: String, Sendable, Equatable {
    /// Present only in the revised file.
    case added
    /// Present only in the original.
    case removed
    /// Same span, different text.
    case textChanged
    /// Same text, moved in time.
    case retimed
    /// Both text and timing differ.
    case changed
}

public struct DiffEntry: Sendable, Equatable, Identifiable {
    public let kind: DiffKind
    public let left: Cue?   // original
    public let right: Cue?  // revised
    public var id: String { "\(kind.rawValue):\(left?.id ?? "-"):\(right?.id ?? "-")" }
    public init(kind: DiffKind, left: Cue?, right: Cue?) {
        self.kind = kind; self.left = left; self.right = right
    }
    /// Where to jump in whichever document the caller has open.
    public var time: Double { (left ?? right)?.start ?? 0 }
}

public struct DiffSummary: Sendable, Equatable {
    public var added = 0, removed = 0, textChanged = 0, retimed = 0, changed = 0
    public var total: Int { added + removed + textChanged + retimed + changed }
    public init() {}
}

/// Seconds of slack when deciding whether two cues sit at the "same" time.
/// A hair of rounding from a format round trip shouldn't read as a retime.
private let TIME_EPSILON = 0.05

private func overlap(_ a: Cue, _ b: Cue) -> Double {
    max(0, min(a.end, b.end) - max(a.start, b.start))
}

private func sameTiming(_ a: Cue, _ b: Cue) -> Bool {
    abs(a.start - b.start) <= TIME_EPSILON && abs(a.end - b.end) <= TIME_EPSILON
}

/// Pairs cues by best time overlap, then classifies each pair.
///
/// Cues that overlap nothing on the other side are added/removed. Note this
/// deliberately does NOT try to detect a cue that was moved far away AND
/// edited — with no identity to follow, that is indistinguishable from a
/// deletion plus an insertion, and guessing would produce confident nonsense.
public func diffDocuments(_ original: SubtitleDocument, _ revised: SubtitleDocument) -> [DiffEntry] {
    let left = sortedCues(original.cues)
    let right = sortedCues(revised.cues)

    var pairedRight = Set<Int>()
    var entries: [DiffEntry] = []

    for l in left {
        var bestIdx: Int?
        var bestOverlap = 0.0
        for (i, r) in right.enumerated() where !pairedRight.contains(i) {
            let o = overlap(l, r)
            if o > bestOverlap { bestOverlap = o; bestIdx = i }
        }
        guard let idx = bestIdx, bestOverlap > 0 else {
            entries.append(DiffEntry(kind: .removed, left: l, right: nil))
            continue
        }
        pairedRight.insert(idx)
        let r = right[idx]
        let textSame = l.text == r.text
        let timeSame = sameTiming(l, r)
        if textSame && timeSame { continue } // identical — not a finding
        let kind: DiffKind = textSame ? .retimed : (timeSame ? .textChanged : .changed)
        entries.append(DiffEntry(kind: kind, left: l, right: r))
    }

    for (i, r) in right.enumerated() where !pairedRight.contains(i) {
        entries.append(DiffEntry(kind: .added, left: nil, right: r))
    }

    return entries.sorted { $0.time < $1.time }
}

public func summarize(_ entries: [DiffEntry]) -> DiffSummary {
    var s = DiffSummary()
    for e in entries {
        switch e.kind {
        case .added: s.added += 1
        case .removed: s.removed += 1
        case .textChanged: s.textChanged += 1
        case .retimed: s.retimed += 1
        case .changed: s.changed += 1
        }
    }
    return s
}

// ── join / split ─────────────────────────────────────────────────────────────

/// Appends `other`'s cues to `base`, shifted by `offset` seconds.
///
/// Fresh ids are minted for the incoming cues: two files independently can and
/// do reuse ids, and a duplicate id would break every id-keyed operation in the
/// app (selection, undo patches, the glossary jump-to).
public func appendDocument(
    _ base: SubtitleDocument,
    _ other: SubtitleDocument,
    offset: Double
) -> SubtitleDocument {
    var out = base
    out.cues += other.cues.map { cue in
        var c = cue
        c.id = newCueId()
        c.start = max(0, cue.start + offset)
        c.end = max(0, cue.end + offset)
        return c
    }
    out.cues = sortedCues(out.cues)
    return out
}

/// Offset that places `other` immediately after the last cue of `base`.
public func appendOffsetAfter(_ base: SubtitleDocument, gap: Double = 1) -> Double {
    (sortedCues(base.cues).last?.end ?? 0) + gap
}

/// Splits at `time`: cues starting at or after it move to the second document,
/// rebased so it starts near zero. Cues straddling the point stay in the first
/// half — splitting a cue in two would invent text that was never written.
public func splitDocument(
    _ doc: SubtitleDocument,
    at time: Double,
    rebaseSecond: Bool = true
) -> (first: SubtitleDocument, second: SubtitleDocument) {
    var first = doc, second = doc
    let ordered = sortedCues(doc.cues)
    first.cues = ordered.filter { $0.start < time }
    let tail = ordered.filter { $0.start >= time }
    let base = rebaseSecond ? (tail.first?.start ?? 0) : 0
    second.cues = tail.map { cue in
        var c = cue
        c.id = newCueId()
        c.start = max(0, cue.start - base)
        c.end = max(0, cue.end - base)
        return c
    }
    return (first, second)
}
