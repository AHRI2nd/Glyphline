// Subtitle quality checks (ported from ../../src/utils/quality.ts).
// CPS, duration, overlap, line length / line count. Thresholds are configurable.

import Foundation

public struct QualityThresholds: Codable, Equatable, Sendable {
    public var maxCps: Double
    public var minDuration: Double
    public var maxDuration: Double
    public var maxLineLength: Int
    public var maxLines: Int

    public init(maxCps: Double, minDuration: Double, maxDuration: Double, maxLineLength: Int, maxLines: Int) {
        self.maxCps = maxCps
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.maxLineLength = maxLineLength
        self.maxLines = maxLines
    }
}

public let DEFAULT_THRESHOLDS = QualityThresholds(
    maxCps: 20, minDuration: 0.7, maxDuration: 7, maxLineLength: 42, maxLines: 2
)

/// Netflix timed-text style guide (English/most languages).
public let NETFLIX_THRESHOLDS = QualityThresholds(
    maxCps: 17, minDuration: 0.833, maxDuration: 7, maxLineLength: 42, maxLines: 2
)

/// Visible characters (whitespace excluded).
public func visibleCharCount(_ text: String) -> Int {
    text.filter { !$0.isWhitespace }.count
}

public func cueDuration(_ cue: Cue) -> Double {
    max(0, cue.end - cue.start)
}

/// Characters per second; 0 when duration is non-positive.
public func cps(_ cue: Cue) -> Double {
    let d = cueDuration(cue)
    return d <= 0 ? 0 : Double(visibleCharCount(cue.text)) / d
}

/// Longest line length (trimmed).
public func longestLineLength(_ text: String) -> Int {
    text.components(separatedBy: "\n").map { $0.trimmed().count }.max() ?? 0
}

public func lineCount(_ text: String) -> Int {
    text.components(separatedBy: "\n").count
}

public struct CueQuality: Equatable, Sendable {
    public var durationTooShort = false
    public var durationTooLong = false
    public var cpsTooHigh = false
    public var negativeDuration = false
    public var overlapsPrev = false
    public var lineTooLong = false
    public var tooManyLines = false
    /// A detected shot change falls inside this cue's span — see SceneCuts.swift.
    /// Only ever set when the caller actually has a cut list; a document opened
    /// without media (or before detection ran) leaves this false throughout,
    /// same as every other check that simply finds nothing to flag.
    public var crossesCut = false
}

/// Evaluate a cue against the previous (time-sorted) cue. `sceneCuts` is
/// optional media-derived state (empty when no video is loaded or detection
/// hasn't run) — passing it in rather than storing it on the model keeps this
/// function pure and testable without a media dependency.
public func evaluateCue(
    _ cue: Cue,
    prev: Cue?,
    thresholds th: QualityThresholds = DEFAULT_THRESHOLDS,
    sceneCuts: [Double] = []
) -> CueQuality {
    let d = cueDuration(cue)
    var q = CueQuality()
    q.negativeDuration = cue.end < cue.start
    q.durationTooShort = d > 0 && d < th.minDuration
    q.durationTooLong = d > th.maxDuration
    q.cpsTooHigh = cps(cue) > th.maxCps
    q.overlapsPrev = prev != nil && cue.start < prev!.end - 1e-6
    q.lineTooLong = !cue.text.trimmed().isEmpty && longestLineLength(cue.text) > th.maxLineLength
    q.tooManyLines = lineCount(cue.text) > th.maxLines
    q.crossesCut = !sceneCuts.isEmpty && !cutsInside(cue, cuts: sceneCuts).isEmpty
    return q
}

public func hasAnyIssue(_ q: CueQuality) -> Bool {
    q.negativeDuration || q.durationTooShort || q.durationTooLong
        || q.cpsTooHigh || q.overlapsPrev || q.lineTooLong || q.tooManyLines || q.crossesCut
}

/// How many cues have at least one flagged issue — the same per-cue pass
/// QualityIssuesPanel's own issue list already does (see its `issues`
/// computed property), factored out so a tab badge elsewhere in the app can
/// show the same number without duplicating the sorted-pairwise-evaluate
/// loop by hand.
public func countQualityIssues(
    _ cues: [Cue], thresholds: QualityThresholds = DEFAULT_THRESHOLDS, sceneCuts: [Double] = []
) -> Int {
    let sorted = sortedCues(cues)
    return sorted.indices.reduce(0) { count, i in
        let q = evaluateCue(sorted[i], prev: i > 0 ? sorted[i - 1] : nil, thresholds: thresholds, sceneCuts: sceneCuts)
        return count + (hasAnyIssue(q) ? 1 : 0)
    }
}
