// The command surface MediaModel needs from a playback engine. Kept as a
// protocol so MediaModel (state + orchestration) doesn't depend on AppKit or
// libmpv directly — MPVSurfaceView is the concrete implementation, wired in by
// MPVVideoView's Coordinator once the NSView exists.

import Foundation

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
}
