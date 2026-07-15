// libmpv C ABI — minimal bindings, dlopen'd at runtime (mirrors the Tauri Rust
// backend's approach: the app must start even when mpv isn't installed). Split
// from the M0 spike (GlyphlineSpike/MPVKit.swift, kept as a throwaway reference)
// with the additional commands/properties real playback needs: pause, seek,
// skip, frame-step, volume, mute, speed, subtitle track, and time-pos/duration/
// pause polling (there is no push-based event API wired here — we poll on a
// timer, matching lib.rs's 80ms poll thread).

import Foundation

let MPV_FORMAT_FLAG: Int32 = 3
let MPV_FORMAT_DOUBLE: Int32 = 5

let MPV_RENDER_PARAM_INVALID: Int32 = 0
let MPV_RENDER_PARAM_API_TYPE: Int32 = 1
let MPV_RENDER_PARAM_OPENGL_INIT_PARAMS: Int32 = 2
let MPV_RENDER_PARAM_OPENGL_FBO: Int32 = 3
let MPV_RENDER_PARAM_FLIP_Y: Int32 = 4
let MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME: Int32 = 12
let MPV_RENDER_PARAM_SKIP_RENDERING: Int32 = 13

struct mpv_render_param { var type: Int32; var data: UnsafeMutableRawPointer? }
struct mpv_opengl_fbo { var fbo: Int32; var w: Int32; var h: Int32; var internal_format: Int32 }
struct mpv_opengl_init_params {
    var get_proc_address: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?
    var get_proc_address_ctx: UnsafeMutableRawPointer?
}

typealias MpvCreate = @convention(c) () -> OpaquePointer?
typealias MpvInitialize = @convention(c) (OpaquePointer?) -> Int32
typealias MpvDestroy = @convention(c) (OpaquePointer?) -> Void
typealias MpvSetOptionString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
typealias MpvSetProperty = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
typealias MpvGetProperty = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
typealias MpvCommand = @convention(c) (OpaquePointer?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
typealias MpvRenderContextCreate = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
typealias MpvRenderContextFree = @convention(c) (OpaquePointer?) -> Void
typealias MpvRenderContextRender = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
typealias MpvRenderContextUpdate = @convention(c) (OpaquePointer?) -> UInt64
typealias MpvRenderContextSetUpdateCallback = @convention(c) (OpaquePointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void

final class MPVLibrary {
    let create: MpvCreate
    let initialize: MpvInitialize
    let destroy: MpvDestroy
    let setOptionString: MpvSetOptionString
    let setProperty: MpvSetProperty
    let getProperty: MpvGetProperty
    let command: MpvCommand
    let renderContextCreate: MpvRenderContextCreate
    let renderContextFree: MpvRenderContextFree
    let renderContextRender: MpvRenderContextRender
    let renderContextUpdate: MpvRenderContextUpdate
    let renderContextSetUpdateCallback: MpvRenderContextSetUpdateCallback

    static let candidates = [
        "/opt/homebrew/lib/libmpv.dylib",
        "/usr/local/lib/libmpv.dylib",
        "libmpv.dylib",
    ]

    /// True once a successful `MPVLibrary()` has been constructed — cheap
    /// re-check for UI ("mpv 미설치" banners) without re-dlopen'ing.
    /// @MainActor: all mpv/GL work is main-thread-only by our own design
    /// (NSOpenGLContext isn't thread-safe), so this is a reasonable isolation.
    @MainActor static var isAvailable: Bool { shared != nil }
    @MainActor static let shared: MPVLibrary? = MPVLibrary()

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
            let d = sym("mpv_destroy", MpvDestroy.self),
            let sos = sym("mpv_set_option_string", MpvSetOptionString.self),
            let sp = sym("mpv_set_property", MpvSetProperty.self),
            let gp = sym("mpv_get_property", MpvGetProperty.self),
            let cmd = sym("mpv_command", MpvCommand.self),
            let rcc = sym("mpv_render_context_create", MpvRenderContextCreate.self),
            let rcf = sym("mpv_render_context_free", MpvRenderContextFree.self),
            let rcr = sym("mpv_render_context_render", MpvRenderContextRender.self),
            let rcu = sym("mpv_render_context_update", MpvRenderContextUpdate.self),
            let rcs = sym("mpv_render_context_set_update_callback", MpvRenderContextSetUpdateCallback.self)
        else { return nil }
        create = c; initialize = i; destroy = d
        setOptionString = sos; setProperty = sp; getProperty = gp; command = cmd
        renderContextCreate = rcc; renderContextFree = rcf; renderContextRender = rcr
        renderContextUpdate = rcu; renderContextSetUpdateCallback = rcs
    }

    // ── Typed property/command helpers ──────────────────────────────────────────

    func setString(_ mpv: OpaquePointer?, _ name: String, _ value: String) {
        _ = setOptionString(mpv, name, value)
    }
    func setDouble(_ mpv: OpaquePointer?, _ name: String, _ value: Double) {
        var v = value
        _ = setProperty(mpv, name, MPV_FORMAT_DOUBLE, &v)
    }
    func setFlag(_ mpv: OpaquePointer?, _ name: String, _ value: Bool) {
        var v: Int32 = value ? 1 : 0
        _ = setProperty(mpv, name, MPV_FORMAT_FLAG, &v)
    }
    func getDouble(_ mpv: OpaquePointer?, _ name: String) -> Double? {
        var v: Double = 0
        let rc = getProperty(mpv, name, MPV_FORMAT_DOUBLE, &v)
        return rc == 0 ? v : nil
    }
    func getFlag(_ mpv: OpaquePointer?, _ name: String) -> Bool? {
        var v: Int32 = 0
        let rc = getProperty(mpv, name, MPV_FORMAT_FLAG, &v)
        return rc == 0 ? (v != 0) : nil
    }
    /// Run an mpv command as a NULL-terminated argv (dup'd C strings, freed after).
    func runCommand(_ mpv: OpaquePointer?, _ args: [String]) {
        var argv: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        argv.append(nil)
        _ = command(mpv, argv)
        for p in argv where p != nil { free(UnsafeMutableRawPointer(mutating: p)) }
    }
}
