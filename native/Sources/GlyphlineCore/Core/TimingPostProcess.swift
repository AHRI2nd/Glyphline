// Batch timing operations for an already-drafted document — Aegisub calls
// this its Timing Post-Processor. Where BatchCleanup's gap functions FIX
// problems (overlaps, too-short/long), these three shape correctly-timed
// cues to reading and viewing conventions: give the eye a beat before text
// appears and after it leaves (lead-in/out), stop a one-frame gap from
// reading as a flicker (gap bridging), and land boundaries exactly on the
// shot changes a separate scan found (see SceneCuts.swift).
//
// All three operate on the SORTED cue list and never let one cue's timing
// invade the one next to it — a lead-in that reached past the previous cue's
// end, or a lead-out that reached past the next cue's start, would silently
// recreate the overlaps fixOverlaps exists to remove.

import Foundation

/// Pull each cue's start earlier and push its end later, without touching a
/// neighbor. `leadInSec`/`leadOutSec` are the requested amounts; each is
/// clamped per-cue against the available gap to the previous/next cue.
public func applyLeadInOut(
    _ cues: [Cue],
    leadInSec: Double,
    leadOutSec: Double
) -> (cues: [Cue], changed: Int) {
    guard leadInSec > 0 || leadOutSec > 0 else { return (cues, 0) }
    let sorted = sortedCues(cues)
    var patches: [String: (start: Double, end: Double)] = [:]
    for i in 0..<sorted.count {
        let cue = sorted[i]
        let prevEnd = i > 0 ? sorted[i - 1].end : 0
        let nextStart = i + 1 < sorted.count ? sorted[i + 1].start : Double.infinity
        let newStart = leadInSec > 0 ? max(prevEnd, cue.start - leadInSec) : cue.start
        let newEnd = leadOutSec > 0 ? min(nextStart, cue.end + leadOutSec) : cue.end
        if newStart != cue.start || newEnd != cue.end {
            patches[cue.id] = (newStart, newEnd)
        }
    }
    guard !patches.isEmpty else { return (cues, 0) }
    let out = cues.map { cue -> Cue in
        guard let p = patches[cue.id] else { return cue }
        var c = cue; c.start = p.start; c.end = p.end; return c
    }
    return (out, patches.count)
}

/// Extends a cue's end to meet the next cue's start wherever the gap between
/// them is short enough to read as a flicker rather than a deliberate pause,
/// but leaves genuinely spaced-out lines alone.
public func bridgeSmallGaps(_ cues: [Cue], maxGapSec: Double) -> (cues: [Cue], changed: Int) {
    guard maxGapSec > 0 else { return (cues, 0) }
    let sorted = sortedCues(cues)
    var patches: [String: Double] = [:]
    for i in 0..<max(0, sorted.count - 1) {
        let cur = sorted[i], next = sorted[i + 1]
        let gap = next.start - cur.end
        if gap > 0, gap <= maxGapSec {
            patches[cur.id] = next.start
        }
    }
    guard !patches.isEmpty else { return (cues, 0) }
    let out = cues.map { cue -> Cue in
        guard let end = patches[cue.id] else { return cue }
        var c = cue; c.end = end; return c
    }
    return (out, patches.count)
}

/// Batch form of the drag-time snap in WaveformScrollView: quantizes every
/// cue's start/end to the nearest detected shot change within tolerance,
/// independently — a cue can pick up a snapped start without its end moving,
/// and vice versa.
public func snapCuesToSceneCuts(
    _ cues: [Cue],
    sceneCuts: [Double],
    toleranceSec: Double
) -> (cues: [Cue], changed: Int) {
    guard !sceneCuts.isEmpty else { return (cues, 0) }
    var changed = 0
    let out = cues.map { cue -> Cue in
        let candidateStart = snapToNearestCut(cue.start, cuts: sceneCuts, within: toleranceSec)
        // A snap that would collapse or invert the cue is worse than no snap —
        // e.g. two cuts close together near a very short cue could otherwise
        // pull start past the (still unsnapped) end.
        let newStart = candidateStart < cue.end ? candidateStart : cue.start
        let candidateEnd = snapToNearestCut(cue.end, cuts: sceneCuts, within: toleranceSec)
        let newEnd = candidateEnd > newStart ? candidateEnd : cue.end
        guard newStart != cue.start || newEnd != cue.end else { return cue }
        changed += 1
        var c = cue; c.start = newStart; c.end = newEnd; return c
    }
    return (out, changed)
}
