// Standalone media-duration lookup for the delivery pipeline's folder-scan
// items, which have no loaded MediaModel (that's normally where
// `media.duration` comes from — see BurnInPanel.swift's use of it).

import AVFoundation

enum MediaDurationProbe {
    /// Best-effort; 0 on failure. `BurnInEncoder.encode` already treats a
    /// non-positive `durationHint` as "no fractional progress this tick"
    /// (see its `durationHint > 0` guard), so a failed probe never blocks
    /// the encode itself — it only leaves that item's progress bar
    /// indeterminate instead of a filling percentage.
    static func duration(ofFileAt path: String) async -> Double {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}
