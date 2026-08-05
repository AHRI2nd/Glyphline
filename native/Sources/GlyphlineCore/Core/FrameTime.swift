// Frame-accurate timing: HH:MM:SS:FF timecodes and frame-boundary snapping.
//
// Internal time stays float seconds everywhere (see Time.swift) — frames are a
// presentation and quantization layer on top, not a second source of truth.
// That keeps every existing adapter, edit action and quality check untouched.
//
// WHY snapping matters: a cue that starts or ends partway through a frame can't
// be shown partway through it. The player rounds it to a frame edge on its own,
// so the timing you verified in the editor isn't quite the timing that ships —
// and at a shot change a boundary that lands one frame late flashes the old
// subtitle over the new shot. Snapping makes the editor agree with the player.
//
// LIMIT — non-drop-frame only. At 29.97/59.94 broadcast houses often use
// DROP-FRAME timecode (written with ';'), which skips label numbers to stay
// aligned with wall-clock time. This converts by pure arithmetic
// (frame = round(seconds × fps)), so at those rates a long timecode drifts from
// a drop-frame reference by ~3.6s/hour. Frame BOUNDARIES are still exact, which
// is what snapping needs; only the printed label differs. Subtitle work is
// overwhelmingly NDF, so this is the deliberate 90% choice, not an oversight.

import Foundation

/// Frame rates offered in the UI. 23.976/29.97 are the NTSC pulldown rates
/// (24000/1001, 30000/1001) — stored at full precision, since rounding them to
/// 23.98 accumulates visible error across a feature-length file.
public let COMMON_FRAME_RATES: [Double] = [
    23.976023976023978, // 24000/1001
    24, 25,
    29.97002997002997,  // 30000/1001
    30, 50,
    59.94005994005994,  // 60000/1001
    60,
]

/// Human label for a frame rate ("23.976", "25", …).
public func frameRateLabel(_ fps: Double) -> String {
    let rounded = (fps * 1000).rounded() / 1000
    return rounded == rounded.rounded()
        ? String(Int(rounded))
        : String(format: "%.3f", rounded)
}

/// Frame index a time falls on. Rounds rather than truncates so a value already
/// sitting on a boundary survives a seconds→frame→seconds round trip intact
/// (floating-point means "exactly 1.0/24×n" often isn't exact).
public func frameIndex(_ seconds: Double, fps: Double) -> Int {
    guard fps > 0 else { return 0 }
    return max(0, Int((seconds * fps).rounded()))
}

/// Quantize a time to the nearest frame boundary.
public func snapToFrame(_ seconds: Double, fps: Double) -> Double {
    guard fps > 0 else { return seconds }
    return Double(frameIndex(seconds, fps: fps)) / fps
}

/// Snaps both bounds of a cue while keeping it non-empty.
///
/// Snapping each edge on its own collapses any cue shorter than one frame to
/// zero length — both edges round to the same boundary. That's reachable in
/// normal use: an imported file can contain sub-frame cues, and sliding one
/// along the waveform preserves its duration rather than re-applying the
/// drag's minimum. A zero-length cue can't be displayed by any player and
/// reads as corrupt output, so the end is pushed out by one frame instead.
/// An already-empty or inverted input is left alone — this fixes quantization,
/// it doesn't invent duration the user never had.
public func snapCueBounds(start: Double, end: Double, fps: Double) -> (start: Double, end: Double) {
    guard fps > 0 else { return (start, end) }
    let s = snapToFrame(start, fps: fps)
    var e = snapToFrame(end, fps: fps)
    if end > start, e <= s { e = s + 1.0 / fps }
    return (s, e)
}

/// `HH:MM:SS:FF`, the conventional frame-accurate timecode.
public func formatFrameTimecode(_ seconds: Double, fps: Double) -> String {
    guard fps > 0 else { return formatDisplayTime(seconds) }
    let perSecond = Int(fps.rounded())
    let total = frameIndex(seconds, fps: fps)
    let ff = total % perSecond
    let totalSeconds = total / perSecond
    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
    return "\(pad2(h)):\(pad2(m)):\(pad2(s)):\(pad2(ff))"
}

/// Parse `HH:MM:SS:FF` (or `MM:SS:FF`) into seconds.
///
/// A frame field at or above `fps` is carried rather than rejected: typing
/// `00:00:01:30` at 24fps means frame 54, i.e. 2s 6f. That's unambiguous
/// arithmetic, and being strict here would reject a value the user can
/// reasonably expect the editor to normalize.
public func parseFrameTimecode(_ input: String, fps: Double) -> Double? {
    guard fps > 0 else { return nil }
    let t = input.trimmingCharacters(in: .whitespaces)
    let parts = t.split(separator: ":", omittingEmptySubsequences: false)
    guard (3...4).contains(parts.count) else { return nil }
    let nums = parts.map { Int($0) }
    guard !nums.contains(where: { $0 == nil || $0! < 0 }) else { return nil }
    let v = nums.map { $0! }
    let (h, m, s, f) = parts.count == 4
        ? (v[0], v[1], v[2], v[3])
        : (0, v[0], v[1], v[2])
    let perSecond = Int(fps.rounded())
    let totalFrames = ((h * 3600 + m * 60 + s) * perSecond) + f
    return Double(totalFrames) / fps
}
