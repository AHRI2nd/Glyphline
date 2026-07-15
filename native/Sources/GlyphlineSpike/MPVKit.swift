// M0 spike: minimal libmpv render-API binding + an NSOpenGLView that draws mpv.
//
// The whole point: in a native app the video is a PLAIN NSView in the normal
// view hierarchy. Everything the Tauri build fought — a borderless child NSWindow
// overlaid on a WKWebView, addChildWindow/orderOut re-adoption, CSS→screen
// coordinate conversion, multi-monitor DPI math, modal occlusion, the objc
// struct-return hazard — simply does not exist here. We keep only the mpv-side
// lessons that are intrinsic (vsync off, block-for-target-time off, main-thread
// render).
//
// libmpv is dlopen'd at runtime (mirrors the Tauri approach) so the app can run
// even if mpv isn't installed. OpenGL is deprecated on macOS but still functional
// on macOS 26; a production build would move to Metal via mpv's Metal backend.

import AppKit
import OpenGL.GL

// ── mpv C ABI (minimal subset) ────────────────────────────────────────────────

private let MPV_FORMAT_FLAG: Int32 = 3
private let MPV_FORMAT_DOUBLE: Int32 = 5

private let MPV_RENDER_PARAM_INVALID: Int32 = 0
private let MPV_RENDER_PARAM_API_TYPE: Int32 = 1
private let MPV_RENDER_PARAM_OPENGL_INIT_PARAMS: Int32 = 2
private let MPV_RENDER_PARAM_OPENGL_FBO: Int32 = 3
private let MPV_RENDER_PARAM_FLIP_Y: Int32 = 4
private let MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME: Int32 = 12

struct mpv_render_param { var type: Int32; var data: UnsafeMutableRawPointer? }
struct mpv_opengl_fbo { var fbo: Int32; var w: Int32; var h: Int32; var internal_format: Int32 }
struct mpv_opengl_init_params {
    var get_proc_address: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?
    var get_proc_address_ctx: UnsafeMutableRawPointer?
}

// Render-context fns take `mpv_render_param*` — passed as a void* (raw pointer)
// to stay C-representable for @convention(c).
typealias MpvCreate = @convention(c) () -> OpaquePointer?
typealias MpvInitialize = @convention(c) (OpaquePointer?) -> Int32
typealias MpvSetOptionString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
typealias MpvSetProperty = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
typealias MpvCommand = @convention(c) (OpaquePointer?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
typealias MpvRenderContextCreate = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
typealias MpvRenderContextRender = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
typealias MpvRenderContextUpdate = @convention(c) (OpaquePointer?) -> UInt64
typealias MpvRenderContextSetUpdateCallback = @convention(c) (OpaquePointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void

// ── Dynamic library loader ────────────────────────────────────────────────────

final class MPVLibrary {
    let create: MpvCreate
    let initialize: MpvInitialize
    let setOptionString: MpvSetOptionString
    let setProperty: MpvSetProperty
    let command: MpvCommand
    let renderContextCreate: MpvRenderContextCreate
    let renderContextRender: MpvRenderContextRender
    let renderContextUpdate: MpvRenderContextUpdate
    let renderContextSetUpdateCallback: MpvRenderContextSetUpdateCallback

    static let candidates = [
        "/opt/homebrew/lib/libmpv.dylib",
        "/usr/local/lib/libmpv.dylib",
        "libmpv.dylib",
    ]

    init?() {
        var handle: UnsafeMutableRawPointer?
        for path in Self.candidates {
            handle = dlopen(path, RTLD_NOW)
            if handle != nil { break }
        }
        guard let h = handle else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard
            let c = sym("mpv_create", MpvCreate.self),
            let i = sym("mpv_initialize", MpvInitialize.self),
            let sos = sym("mpv_set_option_string", MpvSetOptionString.self),
            let sp = sym("mpv_set_property", MpvSetProperty.self),
            let cmd = sym("mpv_command", MpvCommand.self),
            let rcc = sym("mpv_render_context_create", MpvRenderContextCreate.self),
            let rcr = sym("mpv_render_context_render", MpvRenderContextRender.self),
            let rcu = sym("mpv_render_context_update", MpvRenderContextUpdate.self),
            let rcs = sym("mpv_render_context_set_update_callback", MpvRenderContextSetUpdateCallback.self)
        else { return nil }
        create = c; initialize = i; setOptionString = sos; setProperty = sp; command = cmd
        renderContextCreate = rcc; renderContextRender = rcr
        renderContextUpdate = rcu; renderContextSetUpdateCallback = rcs
    }
}

// ── OpenGL proc-address resolver (top-level: no captures for @convention(c)) ────

private nonisolated(unsafe) var glFrameworkHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_NOW)

private func glGetProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name = name, let h = glFrameworkHandle else { return nil }
    return dlsym(h, name)
}

// mpv render-update callback (mpv's render thread): flag the view for redraw on
// the main thread. Coalesced by AppKit's needsDisplay.
private func onMPVRenderUpdate(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx = ctx else { return }
    let view = Unmanaged<MPVOpenGLView>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { view.needsRender() }
}

// ── The video view — a plain NSOpenGLView in the normal hierarchy ─────────────

final class MPVOpenGLView: NSOpenGLView {
    private let lib: MPVLibrary
    private var mpv: OpaquePointer?
    private var renderCtx: OpaquePointer?
    private var initialized = false

    init?(mpvFrame frame: NSRect) {
        guard let lib = MPVLibrary() else { return nil }
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
        // The mpv handle needs no GL — create it NOW so commands issued before the
        // first draw (e.g. loadfile at launch) are not silently dropped. Only the
        // render context needs a current GL context, so it waits for prepareOpenGL.
        createMPV()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func createMPV() {
        guard mpv == nil else { return }
        let handle = lib.create()
        self.mpv = handle
        func opt(_ k: String, _ v: String) { _ = lib.setOptionString(handle, k, v) }
        opt("vo", "libmpv")
        opt("video-timing-offset", "0") // pair with BLOCK_FOR_TARGET_TIME=0
        opt("keep-open", "yes")
        opt("idle", "yes")
        opt("hwdec", "no")
        _ = lib.initialize(handle)
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
        // vsync off: flushBuffer must not block the main thread (learned the hard
        // way in the Tauri build). Must be set AFTER the context has a drawable.
        var swap: GLint = 0
        openGLContext?.setValues(&swap, for: .swapInterval)
        createRenderContext()
    }

    private func createRenderContext() {
        guard let handle = mpv, renderCtx == nil else { return }
        // Render context (OpenGL). get_proc_address resolves GL from the framework.
        var apiType = strdup("opengl")!
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
            if rc >= 0, let ctx = ctx {
                self.renderCtx = ctx
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                lib.renderContextSetUpdateCallback(ctx, onMPVRenderUpdate, selfPtr)
                initialized = true
                NSLog("[spike] mpv render context ready")
            } else {
                NSLog("[spike] render context create failed: rc=\(rc)")
            }
        }
    }

    /// Run an mpv command as a NULL-terminated argv (dup'd C strings, then freed).
    private func runCommand(_ args: [String]) {
        guard let mpv = mpv else { return }
        var argv: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        argv.append(nil)
        _ = lib.command(mpv, argv)
        for p in argv where p != nil { free(UnsafeMutableRawPointer(mutating: p)) }
    }

    func open(path: String) { runCommand(["loadfile", path, "replace"]) }
    func togglePause() { runCommand(["cycle", "pause"]) }

    /// Called from the mpv update callback (already hopped to main).
    func needsRender() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard initialized, let renderCtx = renderCtx, let ctx = openGLContext else { return }
        ctx.makeCurrentContext()
        _ = lib.renderContextUpdate(renderCtx) // ack pending updates

        let backing = convertToBacking(bounds).size
        var fbo = mpv_opengl_fbo(fbo: 0, w: Int32(backing.width), h: Int32(backing.height), internal_format: 0)
        var flip: Int32 = 1
        var block: Int32 = 0 // never wait for the frame's target time on the main thread
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
}
