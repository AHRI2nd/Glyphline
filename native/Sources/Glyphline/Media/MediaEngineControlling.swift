// The command surface MediaModel needs from a playback engine. Kept as a
// protocol so MediaModel (state + orchestration) doesn't depend on AppKit or
// libmpv directly — MPVSurfaceView is the concrete implementation, wired in by
// MPVVideoView's Coordinator once the NSView exists.

import Foundation

/// One selectable audio stream of the loaded file. Multi-track releases (a
/// dub plus the original, or a commentary) are routine in subtitling work, and
/// timing against the wrong one is silently wrong rather than obviously broken.
struct AudioTrack: Identifiable, Equatable, Sendable {
    var id: Int64
    var title: String?
    var lang: String?
    var codec: String?
    var isDefault: Bool

    /// What the menu shows: whatever the file actually names it, falling back
    /// to the language, then to a bare number rather than an empty row.
    var label: String {
        let parts = [lang?.uppercased(), title].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "#\(id)" : parts.joined(separator: " · ")
    }
}

@MainActor
protocol MediaEngineControlling: AnyObject {
    func open(path: String)
    func setPause(_ pause: Bool)
    func seek(_ seconds: Double)
    func skip(_ delta: Double)
    func frameStep(forward: Bool)
    func setVolume(_ volume: Double)
    func setMute(_ muted: Bool)
    func setSpeed(_ speed: Double)
    /// Push the current editing document's subtitles (ASS text) to mpv's sub
    /// track. Called on load and on debounced cue edits.
    func setSubtitles(_ assText: String)
    func stop()
    /// The file's audio streams, read on demand — mpv only knows them after the
    /// file is loaded, so this is called from the poll loop, not at open time.
    func audioTracks() -> [AudioTrack]
    func selectedAudioTrackId() -> Int64?
    func setAudioTrack(_ id: Int64)
}
