// The video surface: a plain NSOpenGLView in the normal view hierarchy, driving
// libmpv's render API directly. Extends the M0 spike (validated: video renders
// correctly, no overlay-window/coordinate hacks needed) with real playback
// commands, property polling, and subtitle push.
//
// Hard-won mpv lessons carried over from the Tauri build (still apply natively —
// these are mpv/OpenGL facts, not webview-compositing artifacts):
//   • NSOpenGLCPSwapInterval=0 MUST be set AFTER setView: (ignored before a
//     drawable is attached) — otherwise vsync blocks the main thread.
//   • mpv_render_context_render defaults to blocking up to `video-timing-offset`
//     inside the call — pass BLOCK_FOR_TARGET_TIME=0 and set the mpv option to 0.
//   • When there's no usable surface (hidden/zero-size), still ack the frame via
//     SKIP_RENDERING so mpv's pipeline doesn't stall.

import AppKit
import OpenGL.GL
import GlyphlineCore

private nonisolated(unsafe) var glFrameworkHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_NOW)

private func glGetProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name, let h = glFrameworkHandle else { return nil }
    return dlsym(h, name)
}

private func onMPVRenderUpdate(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let view = Unmanaged<MPVSurfaceView>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { view.needsDisplay = true }
}

final class MPVSurfaceView: NSOpenGLView, MediaEngineControlling {
    // nonisolated(unsafe): these are main-thread-only by construction (mpv/GL
    // state, same constraint as the rest of this file), but `deinit` in Swift
    // cannot itself be @MainActor-isolated, so it can't touch MainActor-isolated
    // stored properties directly. Marking them unsafe here is the documented
    // escape hatch — safety is guaranteed by our own single-thread discipline,
    // not by the compiler.
    nonisolated(unsafe) private let lib: MPVLibrary
    nonisolated(unsafe) private var mpv: OpaquePointer?
    nonisolated(unsafe) private var renderCtx: OpaquePointer?
    private var initialized = false
    private var subsLoaded = false
    nonisolated(unsafe) private var pollTimer: Timer?
    /// `open(path:)` can be called (via SwiftUI's `updateNSView`) before AppKit
    /// has attached this view to a window and fired `prepareOpenGL()` — if
    /// `loadfile` reaches mpv before the render context exists, vo=libmpv finds
    /// no consumer and the file plays audio-only with no video (until the next
    /// load, by which point the context already exists). Buffer the path here
    /// and flush it once `createRenderContext()` succeeds instead of racing it.
    private var pendingOpenPath: String?

    /// Pushed every ~80ms with mpv's time-pos/duration/pause (mirrors lib.rs's
    /// poll thread — libmpv's push-event API isn't wired here for simplicity).
    var onPoll: ((Double?, Double?, Bool?, Double?) -> Void)?

    /// `mpvFrame` (not `frame`) avoids colliding with NSView's non-failable
    /// `init(frame:)` — this initializer must stay failable (mpv may be missing).
    init?(mpvFrame frame: NSRect) {
        guard let lib = MPVLibrary.shared else { return nil }
        self.lib = lib
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            0,
        ]
        guard let pf = NSOpenGLPixelFormat(attributes: attrs) else { return nil }
        super.init(frame: frame, pixelFormat: pf)
        wantsBestResolutionOpenGLSurface = true
        createMPV()
        startPolling()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        pollTimer?.invalidate()
        if let renderCtx {
            // Detach the update callback BEFORE freeing the context. mpv invokes
            // it from its own render thread, and onMPVRenderUpdate resolves the
            // context pointer with Unmanaged.takeUnretainedValue() — a callback
            // that lands while this object is being deallocated would resurrect
            // freed memory. Clearing it first is mpv's documented way to
            // guarantee no further callbacks reference us. This view really does
            // get torn down in normal use (SwiftUI rebuilds it when the video
            // pane is re-docked), so the window is reachable, not theoretical.
            lib.renderContextSetUpdateCallback(renderCtx, nil, nil)
            lib.renderContextFree(renderCtx)
        }
        if let mpv { lib.destroy(mpv) }
    }

    private func createMPV() {
        guard mpv == nil else { return }
        let handle = lib.create()
        self.mpv = handle
        lib.setString(handle, "vo", "libmpv")
        lib.setString(handle, "video-timing-offset", "0") // pair with BLOCK_FOR_TARGET_TIME=0
        lib.setString(handle, "keep-open", "yes")
        lib.setString(handle, "idle", "yes")
        lib.setString(handle, "hwdec", "no")
        // We render our own subtitles from the editing doc — don't let mpv
        // auto-load embedded/sidecar subs.
        lib.setString(handle, "sub-auto", "no")
        lib.setString(handle, "sub-visibility", "yes")
        // mpv's bundled Lua scripts (osc, stats, console, ytdl_hook, …) are all
        // redundant here — Glyphline has its own Transport/OSD — and loading
        // them spins up LuaJIT, which JIT-compiles into RWX pages. Hardened
        // Runtime's code-signing enforcement kills the process the moment that
        // page executes (SIGKILL, CODESIGNING/"Invalid Page") unless the app
        // carries the JIT/unsigned-executable-memory entitlement. Since we
        // don't want any of those scripts anyway, disabling script loading
        // avoids the crash without widening the entitlement surface.
        lib.setString(handle, "load-scripts", "no")
        _ = lib.initialize(handle)
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
        createRenderContext()
        // NSOpenGLCPSwapInterval=0 MUST be set AFTER setView: is implicitly done
        // by NSOpenGLView's own drawable attachment — safe here.
        var swap: GLint = 0
        openGLContext?.setValues(&swap, for: .swapInterval)
    }

    /// Without this, NSOpenGLContext's cached drawable can go stale after the
    /// view grows from its initial `.zero` frame to SwiftUI's real layout size
    /// (or any later resize) — mpv's FBO 0 render then lands in a physically
    /// smaller backing store than `bounds` claims, showing the video pillar/
    /// letterboxed inside its own pane instead of filling it. `update()` is the
    /// documented fix for NSOpenGLView subclasses under Auto Layout.
    override func reshape() {
        super.reshape()
        openGLContext?.update()
        needsDisplay = true
    }

    private func createRenderContext() {
        guard let handle = mpv, renderCtx == nil else { return }
        let apiType = strdup("opengl")!
        defer { free(apiType) }
        var glParams = mpv_opengl_init_params(get_proc_address: glGetProcAddress, get_proc_address_ctx: nil)
        withUnsafeMutablePointer(to: &glParams) { glp in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(glp)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            var ctx: OpaquePointer?
            let rc = params.withUnsafeMutableBufferPointer { buf -> Int32 in
                lib.renderContextCreate(&ctx, handle, UnsafeMutableRawPointer(buf.baseAddress!))
            }
            if rc >= 0, let ctx {
                self.renderCtx = ctx
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                lib.renderContextSetUpdateCallback(ctx, onMPVRenderUpdate, selfPtr)
                initialized = true
                if let path = pendingOpenPath {
                    pendingOpenPath = nil
                    open(path: path)
                }
            } else {
                NSLog("[mpv] render context create failed: rc=\(rc)")
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard initialized, let renderCtx, let ctx = openGLContext else { return }
        ctx.makeCurrentContext()
        _ = lib.renderContextUpdate(renderCtx) // ack pending updates

        let backing = convertToBacking(bounds).size
        let w = Int32(backing.width), h = Int32(backing.height)
        if w <= 0 || h <= 0 || !(window?.isVisible ?? false) {
            var skip: Int32 = 1
            withUnsafeMutablePointer(to: &skip) { sp in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(sp)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = params.withUnsafeMutableBufferPointer { buf in
                    lib.renderContextRender(renderCtx, UnsafeMutableRawPointer(buf.baseAddress!))
                }
            }
            return
        }

        var fbo = mpv_opengl_fbo(fbo: 0, w: w, h: h, internal_format: 0)
        var flip: Int32 = 1
        var block: Int32 = 0 // never block the main thread waiting on target time
        withUnsafeMutablePointer(to: &fbo) { fp in
            withUnsafeMutablePointer(to: &flip) { flp in
                withUnsafeMutablePointer(to: &block) { blp in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    _ = params.withUnsafeMutableBufferPointer { buf in
                        lib.renderContextRender(renderCtx, UnsafeMutableRawPointer(buf.baseAddress!))
                    }
                }
            }
        }
        ctx.flushBuffer()
    }

    // ── Polling (time-pos / duration / pause) ───────────────────────────────────

    private func startPolling() {
        // Timer's closure isn't statically @MainActor, but scheduledTimer always
        // fires on the run loop it was created on — main, here — so this is
        // genuinely safe; assumeIsolated documents that instead of suppressing it.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let mpv = self.mpv else { return }
                self.onPoll?(
                    self.lib.getDouble(mpv, "time-pos"),
                    self.lib.getDouble(mpv, "duration"),
                    self.lib.getFlag(mpv, "pause"),
                    // container-fps is the rate declared by the file itself,
                    // which is what a deliverable's timecode is reckoned in.
                    // estimated-vf-fps would drift with decode timing.
                    self.lib.getDouble(mpv, "container-fps")
                )
            }
        }
    }

    // ── MediaEngineControlling ──────────────────────────────────────────────────

    func open(path: String) {
        guard initialized else {
            pendingOpenPath = path
            return
        }
        subsLoaded = false
        lib.runCommand(mpv, ["loadfile", path, "replace"])
    }

    func setPause(_ pause: Bool) { lib.setFlag(mpv, "pause", pause) }
    func seek(_ seconds: Double) { lib.runCommand(mpv, ["seek", String(seconds), "absolute"]) }
    func skip(_ delta: Double) { lib.runCommand(mpv, ["seek", String(delta), "relative"]) }
    func frameStep(forward: Bool) { lib.runCommand(mpv, [forward ? "frame-step" : "frame-back-step"]) }
    func setVolume(_ volume: Double) { lib.setDouble(mpv, "volume", volume) }
    func setMute(_ muted: Bool) { lib.setFlag(mpv, "mute", muted) }
    func setSpeed(_ speed: Double) { lib.setDouble(mpv, "speed", speed) }
    func stop() { lib.runCommand(mpv, ["stop"]) }

    func audioTracks() -> [AudioTrack] {
        guard let count = lib.getInt(mpv, "track-list/count"), count > 0 else { return [] }
        var tracks: [AudioTrack] = []
        for i in 0..<count {
            guard lib.getString(mpv, "track-list/\(i)/type") == "audio",
                  let id = lib.getInt(mpv, "track-list/\(i)/id") else { continue }
            tracks.append(AudioTrack(
                id: id,
                title: lib.getString(mpv, "track-list/\(i)/title"),
                lang: lib.getString(mpv, "track-list/\(i)/lang"),
                codec: lib.getString(mpv, "track-list/\(i)/codec"),
                isDefault: lib.getFlag(mpv, "track-list/\(i)/default") ?? false
            ))
        }
        return tracks
    }

    /// `aid` reads back as the string "no" when audio is disabled, which
    /// getInt can't represent — hence nil rather than 0 (a real track id).
    func selectedAudioTrackId() -> Int64? { lib.getInt(mpv, "aid") }

    // `set` command, not set_option_string: aid is being changed on a running
    // player, and options are only honoured through the property path here.
    func setAudioTrack(_ id: Int64) { lib.runCommand(mpv, ["set", "aid", String(id)]) }

    /// Write ASS to a fixed temp file and add/reload it as mpv's sub track
    /// (first call adds+selects; later calls reload the same path).
    func setSubtitles(_ assText: String) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("glyphline_subs.ass")
        do {
            try assText.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[mpv] subtitle temp write failed: \(error)")
            return
        }
        if subsLoaded {
            lib.runCommand(mpv, ["sub-reload"])
        } else {
            lib.runCommand(mpv, ["sub-add", path.path, "select"])
            subsLoaded = true
        }
    }
}
