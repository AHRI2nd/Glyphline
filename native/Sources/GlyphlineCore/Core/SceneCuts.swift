// Shot/scene-change timestamps and what to do with them once detected.
//
// A hard cut is the one boundary subtitle rules actually reference ("don't let
// a cue straddle a cut", "if it's within N frames of a cut, snap to it") — not
// something derivable from the document itself, so this is media-derived state
// that the UI layer supplies from outside (see SceneCutExtractor, which shells
// out to ffmpeg's `select='gt(scene,…)'` filter and hands back the parsed list).
// Everything here is the pure, testable half: parsing that tool's output and
// answering "does this cue cross a cut" / "what's the nearest cut to snap to".

import Foundation

/// Parses ffmpeg's `-vf "select='gt(scene,N)',showinfo" -f null -` stderr,
/// pulling every `pts_time:<seconds>` occurrence. showinfo also prints other
/// fields (n:, fmt:, sar:, …) on the same line — the regex only anchors on the
/// one field this needs, so it doesn't care what else is present or in what order.
public func parseFFmpegSceneChangeOutput(_ text: String) -> [Double] {
    var times: [Double] = []
    let pattern = #"pts_time:([0-9]+(?:\.[0-9]+)?)"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
        guard let match, let r = Range(match.range(at: 1), in: text), let v = Double(text[r]) else { return }
        times.append(v)
    }
    return times.sorted()
}

/// The nearest cut to `time` within `tolerance` seconds, or nil if none is close.
public func nearestCut(to time: Double, in cuts: [Double], within tolerance: Double) -> Double? {
    guard !cuts.isEmpty else { return nil }
    var best: Double?
    var bestDist = Double.infinity
    for c in cuts {
        let dist = abs(c - time)
        if dist < bestDist { bestDist = dist; best = c }
    }
    return bestDist <= tolerance ? best : nil
}

/// Quantizes a dragged edit toward the nearest cut when one is close enough,
/// otherwise passes the value through unchanged. Meant to run BEFORE frame
/// snapping in a drag handler: a cut, once found, wins outright — the whole
/// point of shot-change snapping is landing exactly on the frame the picture
/// changes, not the nearest frame boundary in general.
public func snapToNearestCut(_ time: Double, cuts: [Double], within tolerance: Double) -> Double {
    nearestCut(to: time, in: cuts, within: tolerance) ?? time
}

/// Cuts that fall strictly inside `(cue.start, cue.end)` — i.e. this cue is on
/// screen when the shot changes underneath it. A cut sitting exactly on a
/// boundary is the cue correctly ending/starting AT the cut, not a violation.
public func cutsInside(_ cue: Cue, cuts: [Double]) -> [Double] {
    guard cue.end > cue.start else { return [] }
    return cuts.filter { $0 > cue.start && $0 < cue.end }
}
