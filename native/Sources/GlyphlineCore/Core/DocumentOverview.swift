// Whole-document statistics for the overview pane.
//
// The grid shows a window of ~30 cues; nothing in the app showed the SHAPE of
// a two-hour file. Gaps are the thing that matters here — a ten-minute stretch
// with no subtitles is either a scene with no dialogue or a chunk somebody
// forgot, and you cannot tell those apart by scrolling.

import Foundation

/// A fixed-width density profile of the document: how many cues, and how much
/// of each slice is covered by a cue.
public struct OverviewBucket: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let cueCount: Int
    /// 0…1 — share of this slice covered by a cue.
    public let coverage: Double
    /// 0…1 — share of the covered time whose cue has a translation.
    public let translatedShare: Double
}

/// A stretch with no cues at all, long enough to be worth pointing at.
public struct OverviewGap: Sendable, Equatable, Identifiable {
    public let start: Double
    public let end: Double
    public var id: Double { start }
    public var duration: Double { end - start }
}

public struct DocumentOverview: Sendable, Equatable {
    public var buckets: [OverviewBucket] = []
    public var gaps: [OverviewGap] = []
    public var span: Double = 0
    public var translatedCues = 0
    public var totalCues = 0
    /// 0…1, or nil when nothing is translated at all (the column is unused, so
    /// showing "0%" would nag about a feature this project isn't using).
    public var translationProgress: Double? {
        guard totalCues > 0, translatedCues > 0 else { return nil }
        return Double(translatedCues) / Double(totalCues)
    }
}

/// Builds the profile. `duration` is the media length when known, so the strip
/// represents the VIDEO rather than just the subtitled part — a file that stops
/// 20 minutes early should look like it stops early.
public func buildOverview(
    _ doc: SubtitleDocument,
    duration: Double? = nil,
    bucketCount: Int = 240,
    minGap: Double = 30
) -> DocumentOverview {
    var out = DocumentOverview()
    let cues = sortedCues(doc.cues)
    out.totalCues = cues.count
    out.translatedCues = cues.filter { !($0.translation ?? "").trimmed().isEmpty }.count
    guard let last = cues.last else { return out }

    let span = max(duration ?? 0, last.end)
    guard span > 0, bucketCount > 0 else { return out }
    out.span = span

    let width = span / Double(bucketCount)
    var counts = [Int](repeating: 0, count: bucketCount)
    var covered = [Double](repeating: 0, count: bucketCount)
    var translated = [Double](repeating: 0, count: bucketCount)

    for cue in cues {
        let hasTranslation = !(cue.translation ?? "").trimmed().isEmpty
        let firstBucket = max(0, min(bucketCount - 1, Int(cue.start / width)))
        let lastBucket = max(0, min(bucketCount - 1, Int(cue.end / width)))
        for b in firstBucket...lastBucket {
            let bStart = Double(b) * width
            let overlap = max(0, min(cue.end, bStart + width) - max(cue.start, bStart))
            guard overlap > 0 || firstBucket == lastBucket else { continue }
            counts[b] += 1
            covered[b] += overlap
            if hasTranslation { translated[b] += overlap }
        }
    }

    out.buckets = (0..<bucketCount).map { b in
        OverviewBucket(
            start: Double(b) * width,
            end: Double(b + 1) * width,
            cueCount: counts[b],
            coverage: min(1, covered[b] / width),
            translatedShare: covered[b] > 0 ? translated[b] / covered[b] : 0
        )
    }

    // Gaps come from the cues themselves, not the buckets — bucket resolution
    // would round a real gap's edges and report a length that's merely close.
    var cursor = 0.0
    for cue in cues {
        if cue.start - cursor >= minGap {
            out.gaps.append(OverviewGap(start: cursor, end: cue.start))
        }
        cursor = max(cursor, cue.end)
    }
    if span - cursor >= minGap {
        out.gaps.append(OverviewGap(start: cursor, end: span))
    }
    return out
}

// ── actors ───────────────────────────────────────────────────────────────────

public struct ActorSummary: Sendable, Equatable, Identifiable {
    public let name: String
    public let lineCount: Int
    public let firstCueId: String
    public let firstStart: Double
    public var id: String { name }
}

/// Speakers with their line counts, most lines first.
///
/// Names are NOT normalised or merged: "철수" and "철 수" stay separate rows on
/// purpose, because seeing them side by side is how you notice the typo. Fold
/// them together and the inconsistency disappears from the one view that would
/// have shown it.
public func actorSummaries(_ doc: SubtitleDocument) -> [ActorSummary] {
    var byName: [String: (count: Int, id: String, start: Double)] = [:]
    for cue in sortedCues(doc.cues) {
        let name = (cue.actor ?? "").trimmed()
        guard !name.isEmpty else { continue }
        if var existing = byName[name] {
            existing.count += 1
            byName[name] = existing
        } else {
            byName[name] = (1, cue.id, cue.start)
        }
    }
    return byName
        .map { ActorSummary(name: $0.key, lineCount: $0.value.count,
                            firstCueId: $0.value.id, firstStart: $0.value.start) }
        .sorted { $0.lineCount != $1.lineCount ? $0.lineCount > $1.lineCount : $0.name < $1.name }
}
