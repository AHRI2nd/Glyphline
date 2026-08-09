// SMPTE drop-frame timecode + a document-level start-timecode offset.
//
// Two separate broadcast conventions FrameTime.swift's plain HH:MM:SS:FF
// deliberately doesn't cover (see its LIMIT note):
//
//  1. DROP-FRAME notation (written with ';', e.g. 01:00:00;02) — at 29.97/59.94
//     the true frame rate is slightly under the nominal 30/60, so labeling
//     frames sequentially at the nominal rate drifts off wall-clock time by
//     ~3.6s/hour. Drop-frame periodically skips two (or four) LABEL numbers —
//     never actual frames — to keep the label synced. The skip is jarring by
//     design: scrub a DF timeline and you'll see :01 → :02, never :00 → :01,
//     at most minute boundaries.
//  2. START OFFSET — broadcast masters conventionally don't start at
//     00:00:00:00; 10:00:00:00 is the common house-style start, so a
//     deliverable's burned-in/embedded timecode matches what the client's QC
//     checks against. This app still edits everything at internal 0-based
//     seconds; the offset only shifts what's DISPLAYED and PARSED.
//
// Both are optional per-document settings (SubtitleDocument.meta), off by
// default — the plain NDF-from-zero path FrameTime.swift already provides
// stays the common case for non-broadcast work.

import Foundation

/// Drop-frame only applies to the NTSC pulldown rates; asking for it at 24/25/30
/// exact would be meaningless (there's no drift to correct), so callers should
/// gate the UI on this rather than silently no-op.
public func isDropFrameCandidate(fps: Double) -> Bool {
    abs(fps - 29.97002997002997) < 0.01 || abs(fps - 59.94005994005994) < 0.01
}

/// Frames skipped at the start of each non-tenth minute — 2 at 30fps-nominal,
/// 4 at 60fps-nominal. nil for a rate drop-frame doesn't apply to.
private func dropFramesPerMinute(fps: Double) -> Int? {
    guard isDropFrameCandidate(fps: fps) else { return nil }
    return Int((fps * 0.066666).rounded())
}

/// `HH:MM:SS;FF` drop-frame label for a raw, sequentially-counted frame index
/// (i.e. `frameIndex(seconds, fps:)` — one count per physically captured frame,
/// no compensation applied yet). Falls back to the plain NDF format at a rate
/// drop-frame doesn't apply to, since there's nothing to compensate for.
public func formatDropFrameTimecode(_ seconds: Double, fps: Double) -> String {
    guard let dropFrames = dropFramesPerMinute(fps: fps) else {
        return formatFrameTimecode(seconds, fps: fps)
    }
    let frRound = Int(fps.rounded())
    let framesPer10Minutes = Int((fps * 600).rounded())
    let framesPerMinute = frRound * 60 - dropFrames

    var frame = frameIndex(seconds, fps: fps)
    let d = frame / framesPer10Minutes
    let m = frame % framesPer10Minutes
    if m > dropFrames {
        frame += dropFrames * 9 * d + dropFrames * ((m - dropFrames) / framesPerMinute)
    } else {
        frame += dropFrames * 9 * d
    }

    let ff = frame % frRound
    let totalSeconds = frame / frRound
    let h = (totalSeconds / 3600) % 24
    let m2 = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
    return "\(pad2(h)):\(pad2(m2)):\(pad2(s));\(pad2(ff))"
}

/// Inverse of `formatDropFrameTimecode`. Accepts `;` or `:` before the frame
/// field — a pasted label from another tool's export isn't always faithful
/// about which separator it used, and there's no ambiguity either way since
/// the caller already knows this field is drop-frame.
public func parseDropFrameTimecode(_ input: String, fps: Double) -> Double? {
    guard let dropFrames = dropFramesPerMinute(fps: fps) else {
        return parseFrameTimecode(input, fps: fps)
    }
    let t = input.trimmingCharacters(in: .whitespaces)
    let parts = t.split(whereSeparator: { $0 == ":" || $0 == ";" })
    guard (3...4).contains(parts.count) else { return nil }
    let nums = parts.map { Int($0) }
    guard !nums.contains(where: { $0 == nil || $0! < 0 }) else { return nil }
    let v = nums.map { $0! }
    let (h, m, s, f) = parts.count == 4 ? (v[0], v[1], v[2], v[3]) : (0, v[0], v[1], v[2])

    let frRound = Int(fps.rounded())
    let totalMinutes = 60 * h + m
    var frame = frRound * 3600 * h + frRound * 60 * m + frRound * s + f
    frame -= dropFrames * (totalMinutes - totalMinutes / 10)
    guard frame >= 0 else { return nil }
    return Double(frame) / fps
}

/// Formats for display: drop-frame or plain, with the document's start offset
/// added first. This is the one callers should reach for once a document has
/// broadcast timecode settings — `formatFrameTimecode` stays the from-zero,
/// NDF-only primitive underneath.
public func displayTimecode(_ seconds: Double, fps: Double, offsetSec: Double = 0, dropFrame: Bool = false) -> String {
    let shifted = max(0, seconds + offsetSec)
    return dropFrame ? formatDropFrameTimecode(shifted, fps: fps) : formatFrameTimecode(shifted, fps: fps)
}

/// Inverse of `displayTimecode`: parses, then removes the offset to get back
/// to the document's internal 0-based seconds.
public func parseDisplayTimecode(_ input: String, fps: Double, offsetSec: Double = 0, dropFrame: Bool = false) -> Double? {
    let parsed = dropFrame ? parseDropFrameTimecode(input, fps: fps) : parseFrameTimecode(input, fps: fps)
    guard let seconds = parsed else { return nil }
    let internalSeconds = seconds - offsetSec
    // A label before the house start (e.g. typing 05:00:00:00 under a
    // 10:00:00:00 offset) has no valid internal time to represent — nil
    // here is what makes the grid REJECT the edit and revert the cell,
    // rather than silently storing a negative cue.start that every other
    // assumption in this app (sorting, export, "always float seconds ≥ 0")
    // doesn't expect.
    guard internalSeconds >= 0 else { return nil }
    return internalSeconds
}

// ── document-level settings (SubtitleDocument.meta) ─────────────────────────

private let TC_OFFSET_KEY = "tcStartOffsetSec"
private let TC_DROPFRAME_KEY = "tcDropFrame"

public extension SubtitleDocument {
    /// Start-timecode offset in seconds (e.g. 36000 for a 10:00:00:00 house
    /// start). 0 when unset — the common from-zero case.
    var timecodeStartOffsetSec: Double {
        get { meta[TC_OFFSET_KEY].flatMap(Double.init) ?? 0 }
        set { meta[TC_OFFSET_KEY] = newValue == 0 ? nil : String(newValue) }
    }
    /// Whether timecode display/entry for this document uses drop-frame
    /// notation. Meaningless (and ignored by the formatters above) at a rate
    /// `isDropFrameCandidate` rejects.
    var timecodeDropFrame: Bool {
        get { meta[TC_DROPFRAME_KEY] == "true" }
        set { meta[TC_DROPFRAME_KEY] = newValue ? "true" : nil }
    }
}
