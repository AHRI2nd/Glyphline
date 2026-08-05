// Media playback state (ported from ../../../src/stores/useMediaStore.ts).
// Orchestrates a MediaEngineControlling (MPVSurfaceView in practice); mpv itself
// is the single source of truth for playback — MPVVideoView's poll timer pushes
// time-pos/duration/pause back into this model, mirroring the Tauri backend's
// 80ms poll thread.

import Observation
import Foundation

let PLAYBACK_RATES: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

let VIDEO_EXTS: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ts", "flv", "wmv", "m2ts"]
let AUDIO_EXTS: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff", "aif"]
let MEDIA_EXTS: Set<String> = VIDEO_EXTS.union(AUDIO_EXTS)

enum MediaKind { case video, audio }

// @MainActor: calls into MediaEngineControlling (itself @MainActor — mpv/GL
// state is main-thread-only by our own design), so this model must be too.
@MainActor
@Observable
final class MediaModel {
    weak var engine: (any MediaEngineControlling)?

    private(set) var mediaPath: String?
    private(set) var mediaKind: MediaKind?
    private(set) var mediaName: String?
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying = false
    var playbackRate: Double = 1
    var volume: Double = 100 // mpv scale, 0–130, 100 = original
    var muted = false
    /// The cue being looped, or nil. Stored as an ID rather than a fixed time
    /// range because looping exists to let you hear a cue WHILE you retime it —
    /// snapshotting the bounds meant dragging the cue's edge kept replaying the
    /// old range, and deleting the cue left an orphan loop the user had to
    /// notice and switch off by hand.
    private(set) var loopCueId: String?
    /// Resolves a cue id to its current timing. Injected by AppState, which owns
    /// both models — MediaModel deliberately doesn't depend on DocumentModel.
    var loopBoundsProvider: ((String) -> (start: Double, end: Double)?)?

    /// Live bounds of the looping cue; nil once it stops existing.
    var loopRegion: (start: Double, end: Double)? {
        guard let loopCueId else { return nil }
        return loopBoundsProvider?(loopCueId)
    }
    /// Frame rate mpv read from the loaded file, or nil when nothing is loaded
    /// (or it's audio-only). AppSettings.effectiveFrameRate turns this plus the
    /// user's override into the rate the UI actually times against.
    private(set) var detectedFrameRate: Double?
    var error: String?

    func loadMedia(_ path: String) {
        mediaPath = path
        mediaKind = Self.kind(of: path)
        mediaName = (path as NSString).lastPathComponent
        currentTime = 0; duration = 0; isPlaying = false; loopCueId = nil; error = nil
        detectedFrameRate = nil
        engine?.open(path: path)
    }

    func closeMedia() {
        engine?.stop()
        mediaPath = nil; mediaKind = nil; mediaName = nil
        currentTime = 0; duration = 0; isPlaying = false; loopCueId = nil; error = nil
        detectedFrameRate = nil
    }

    /// Called by the poll timer — mpv is the source of truth for these three.
    /// Also drives loop playback: when the region's end is reached, jump back to
    /// its start (~80ms poll granularity means a slight overshoot — fine for review).
    func applyPolled(time: Double?, duration: Double?, paused: Bool?, fps: Double? = nil) {
        // Only accept a plausible rate — mpv reports 0/NaN before the first
        // frame is decoded, and letting that through would zero out the frame
        // grid mid-session.
        if let fps, fps.isFinite, fps > 1, fps < 1000 { detectedFrameRate = fps }
        if let time {
            currentTime = time
            if let loop = loopRegion, time >= loop.end { engine?.seek(loop.start) }
        }
        if let duration, duration > 0 { self.duration = duration }
        if let paused { isPlaying = !paused }
    }

    /// isPlaying=true → pause it (pass true); isPlaying=false → resume (pass false).
    func togglePlay() { engine?.setPause(isPlaying) }

    func seek(_ sec: Double) {
        let clamped = max(0, min(sec, duration > 0 ? duration : sec))
        engine?.seek(clamped)
    }

    func skip(_ delta: Double) {
        loopCueId = nil // a manual skip cancels any active loop
        engine?.skip(delta)
    }

    func frameStep(forward: Bool) {
        loopCueId = nil
        engine?.frameStep(forward: forward)
    }

    func setPlaybackRate(_ speed: Double) {
        engine?.setSpeed(speed)
        playbackRate = speed
    }

    func setVolume(_ v: Double) {
        let clamped = max(0, min(130, v))
        volume = clamped
        muted = false // adjusting volume implicitly unmutes
        engine?.setVolume(clamped)
        engine?.setMute(false)
    }

    func toggleMute() {
        muted.toggle()
        engine?.setMute(muted)
    }

    /// Loop over the given cue: seek to its start, unpause, remember WHICH cue
    /// is looping (not its times — see `loopRegion`).
    func playRegion(cueId: String, start: Double, end: Double) {
        loopCueId = cueId
        engine?.seek(max(0, start))
        engine?.setPause(false)
    }

    func clearLoop() { loopCueId = nil }

    func pushSubtitles(_ assText: String) { engine?.setSubtitles(assText) }

    private static func kind(of path: String) -> MediaKind {
        let ext = (path as NSString).pathExtension.lowercased()
        return AUDIO_EXTS.contains(ext) ? .audio : .video
    }
}
