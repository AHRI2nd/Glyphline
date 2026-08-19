// Media playback state (ported from ../../../src/stores/useMediaStore.ts).
// Orchestrates a MediaEngineControlling (MPVSurfaceView in practice); mpv itself
// is the single source of truth for playback — MPVVideoView's poll timer pushes
// time-pos/duration/pause back into this model, mirroring the Tauri backend's
// 80ms poll thread.

import Observation
import Foundation
import GlyphlineCore

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

    /// The loaded file's audio streams and which one is playing. Populated from
    /// the poll loop, since mpv only knows them once the file is open.
    private(set) var audioTracks: [AudioTrack] = []
    private(set) var currentAudioTrackId: Int64?

    /// Waveform extraction status. Extraction runs for seconds on a feature —
    /// without this the pane just sat empty and there was no way to tell work
    /// in progress from a silent failure (the error only reached the log).
    enum WaveformStatus: Equatable {
        case idle, extracting, ready
        case failed(String)
    }
    var waveformStatus: WaveformStatus = .idle
    /// The decoded downsampled audio backing the waveform, exposed here (not
    /// just inside WaveformScrollView's private coordinator) so other features
    /// — auto-spotting — can read the same samples without a second decode.
    var waveformAudio: WaveformAudio?
    /// Live \pos(x,y) crosshair while InlineTagEditorPanel has a position tag
    /// selected — see PositionPreview.swift. nil the rest of the time.
    var positionPreview: (x: Double, y: Double)?

    /// Shot-change timestamps for the loaded file — empty until the user runs
    /// detection (it decodes the whole file, so it's opt-in, not automatic).
    private(set) var sceneCuts: [Double] = []
    enum SceneCutStatus: Equatable {
        case idle, detecting, ready
        case failed(String)
    }
    var sceneCutStatus: SceneCutStatus = .idle
    private var sceneCutTask: Task<Void, Never>?

    func loadMedia(_ path: String) {
        mediaPath = path
        mediaKind = Self.kind(of: path)
        mediaName = (path as NSString).lastPathComponent
        currentTime = 0; duration = 0; isPlaying = false; loopCueId = nil; error = nil
        detectedFrameRate = nil
        audioTracks = []; currentAudioTrackId = nil
        waveformStatus = .idle
        waveformAudio = nil
        sceneCuts = []; sceneCutStatus = .idle; sceneCutTask?.cancel()
        engine?.open(path: path)
    }

    func closeMedia() {
        engine?.stop()
        mediaPath = nil; mediaKind = nil; mediaName = nil
        currentTime = 0; duration = 0; isPlaying = false; loopCueId = nil; error = nil
        detectedFrameRate = nil
        audioTracks = []; currentAudioTrackId = nil
        waveformStatus = .idle
        waveformAudio = nil
        sceneCuts = []; sceneCutStatus = .idle; sceneCutTask?.cancel()
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
        // Only while the list is still empty: re-reading a dozen string
        // properties 12 times a second for a list that never changes mid-file
        // would be pure waste.
        if mediaPath != nil, audioTracks.isEmpty, let engine {
            audioTracks = engine.audioTracks()
            if !audioTracks.isEmpty { currentAudioTrackId = engine.selectedAudioTrackId() }
        }
    }

    /// isPlaying=true → pause it (pass true); isPlaying=false → resume (pass false).
    func togglePlay() { engine?.setPause(isPlaying) }

    /// A manual seek (grid click, waveform click, scrubber drag, Overview
    /// jump — every one of them routes through here) cancels any active
    /// loop, same as skip()/frameStep() already do below. Without this,
    /// scrubbing away from a looping cue played normally right up until
    /// crossing the loop's END time, then snapped backward with no warning —
    /// the loop's own repeat rewind bypasses this method (calls engine?.seek
    /// directly, see loopRegion's consumer), so it isn't affected by this.
    func seek(_ sec: Double) {
        loopCueId = nil
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

    /// Matches TransportBar's own "shows as muted" condition (`muted ||
    /// volume == 0`) rather than just flipping the `muted` flag — dragging
    /// the volume slider to 0 already reads as muted in the UI, but only
    /// toggling `muted` there did nothing audible: un-muting from a 0-volume
    /// state left the flag false and the volume still 0, so the icon (and
    /// the silence) never changed no matter how many times you clicked it.
    func toggleMute() {
        if muted || volume == 0 {
            if volume == 0 {
                setVolume(100) // already clears `muted` and unmutes the engine
            } else {
                muted = false
                engine?.setMute(false)
            }
        } else {
            muted = true
            engine?.setMute(true)
        }
    }

    /// Loop over the given cue: seek to its start, unpause, remember WHICH cue
    /// is looping (not its times — see `loopRegion`).
    func playRegion(cueId: String, start: Double, end: Double) {
        loopCueId = cueId
        engine?.seek(max(0, start))
        engine?.setPause(false)
    }

    func clearLoop() { loopCueId = nil }

    /// Toggle looping the currently active cue — shared by TransportBar's
    /// loop button and the Playback menu's keyboard shortcut so the two
    /// don't drift apart with separately-maintained copies of the same
    /// guard. A no-op with nothing to loop and no loop already running (same
    /// as the button's own disabled state, see TransportBar's loop button).
    func toggleLoopActiveCue(document: DocumentModel) {
        if loopRegion != nil {
            clearLoop()
            return
        }
        guard let id = document.activeCueId, let cue = document.doc.cues.first(where: { $0.id == id }) else { return }
        playRegion(cueId: cue.id, start: cue.start, end: cue.end)
    }

    func pushSubtitles(_ assText: String) { engine?.setSubtitles(assText) }

    func selectAudioTrack(_ id: Int64) {
        engine?.setAudioTrack(id)
        currentAudioTrackId = id
    }

    /// Kicks off (or re-kicks, cancelling any run in progress) shot-change
    /// detection for the current file. No-op without media loaded.
    func detectSceneCuts() {
        guard let path = mediaPath else { return }
        sceneCutTask?.cancel()
        sceneCutStatus = .detecting
        sceneCutTask = Task { [weak self] in
            do {
                let cuts = try await SceneCutExtractor.detect(path: path)
                guard !Task.isCancelled else { return }
                self?.sceneCuts = cuts
                self?.sceneCutStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.sceneCutStatus = .failed(
                    (error as? SceneCutExtractor.ExtractError) == .ffmpegNotFound
                        ? t("ffmpegMissing") : t("sceneCutFailed"))
            }
        }
    }

    private static func kind(of path: String) -> MediaKind {
        let ext = (path as NSString).pathExtension.lowercased()
        return AUDIO_EXTS.contains(ext) ? .audio : .video
    }
}
