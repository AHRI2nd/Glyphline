// Silence-based auto-spotting: lay down blank cue timing over every stretch of
// audio that looks like speech, so timing a file from scratch starts from
// "here's where someone's talking" instead of a blank grid.
//
// NOT voice activity detection — no model, no speech/music/noise distinction,
// just short-window RMS energy against a threshold. That's a deliberate 80%
// tool: it catches "is anything making sound here" cheaply and predictably,
// and a human still reviews and types the actual text over each spot. A false
// positive on loud room tone or a music sting is a segment the editor deletes
// in two clicks; a missed line of dialogue under a whisper is the same either
// way with a fancier model, since threshold tuning is still required.

import Foundation

public struct SpeechSegment: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Finds stretches of `samples` (mono, [-1, 1], at `sampleRate`) whose local
/// energy stays above `thresholdDb` for at least `minSpeechSec`, treating a
/// quiet gap shorter than `minSilenceSec` as still part of the same line
/// (a breath or a short pause mid-sentence, not a cut between lines). Each
/// found segment is padded by `paddingSec` on both ends (a beat of lead-in/out,
/// same idea as applyLeadInOut) without crossing into a neighboring segment.
public func detectSpeechSegments(
    samples: [Float],
    sampleRate: Double,
    thresholdDb: Double = -35,
    minSilenceSec: Double = 0.3,
    minSpeechSec: Double = 0.3,
    paddingSec: Double = 0.1
) -> [SpeechSegment] {
    guard sampleRate > 0, !samples.isEmpty else { return [] }

    let windowSec = 0.02 // 20ms analysis window — short enough to catch word onsets
    let windowSize = max(1, Int(windowSec * sampleRate))
    let windowCount = (samples.count + windowSize - 1) / windowSize

    var active = [Bool](repeating: false, count: windowCount)
    for w in 0..<windowCount {
        let lo = w * windowSize
        let hi = min(samples.count, lo + windowSize)
        guard hi > lo else { continue }
        var sumSquares: Double = 0
        for i in lo..<hi { sumSquares += Double(samples[i]) * Double(samples[i]) }
        let rms = (sumSquares / Double(hi - lo)).squareRoot()
        let db = rms > 0 ? 20 * log10(rms) : -.infinity
        active[w] = db >= thresholdDb
    }

    // Raw active runs, in windows.
    var runs: [(start: Int, end: Int)] = []
    var runStart: Int?
    for w in 0..<windowCount {
        if active[w] {
            if runStart == nil { runStart = w }
        } else if let s = runStart {
            runs.append((s, w))
            runStart = nil
        }
    }
    if let s = runStart { runs.append((s, windowCount)) }
    guard !runs.isEmpty else { return [] }

    // Merge runs separated by a gap shorter than minSilenceSec.
    let minSilenceWindows = Int((minSilenceSec / windowSec).rounded())
    var merged: [(start: Int, end: Int)] = [runs[0]]
    for run in runs.dropFirst() {
        if run.start - merged[merged.count - 1].end <= minSilenceWindows {
            merged[merged.count - 1].end = run.end
        } else {
            merged.append(run)
        }
    }

    // Drop runs too short to be a real line, convert to seconds, then pad —
    // clamped against the file bounds and the (already-merged, so
    // non-overlapping) neighbor on each side.
    let inSeconds = merged
        .map { (start: Double($0.start) * windowSec, end: Double($0.end) * windowSec) }
        .filter { $0.end - $0.start >= minSpeechSec }
    let duration = Double(samples.count) / sampleRate

    // Padding on one segment's end and the next segment's start compete for
    // the SAME gap. Splitting each gap in half (rather than clamping each
    // side independently to the far edge) guarantees the two pads can never
    // cross even when the requested padding exceeds the whole gap.
    return inSeconds.enumerated().map { i, seg in
        let prevEnd = i > 0 ? inSeconds[i - 1].end : 0
        let nextStart = i + 1 < inSeconds.count ? inSeconds[i + 1].start : duration
        let backHalf = max(0, (seg.start - prevEnd) / 2)
        let fwdHalf = max(0, (nextStart - seg.end) / 2)
        let start = max(0, seg.start - min(paddingSec, backHalf))
        let end = min(duration, seg.end + min(paddingSec, fwdHalf))
        return SpeechSegment(start: start, end: end)
    }
}
