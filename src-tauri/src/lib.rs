// Glyphline — Tauri backend (mpv video engine, dynamic libloading)

use std::ffi::{CString, c_char, c_int, c_void};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use tauri::{Emitter, Manager};

// ─── mpv C API — minimal bindings ────────────────────────────────────────────
// We load libmpv at runtime so the app can start even when mpv is not installed.

type MpvHandle = *mut c_void;
type MpvRenderCtx = *mut c_void;

// mpv_format enum values we use (wid is set via set_option_string, not set_property)
const MPV_FORMAT_FLAG:   i32 = 3;
const MPV_FORMAT_DOUBLE: i32 = 5;

// ─── libmpv render API (OpenGL) — embed video by rendering ourselves ──────────
// mpv_render_param_type values we use
const MPV_RENDER_PARAM_API_TYPE:            c_int = 1;
const MPV_RENDER_PARAM_OPENGL_INIT_PARAMS:  c_int = 2;
const MPV_RENDER_PARAM_OPENGL_FBO:          c_int = 3;
const MPV_RENDER_PARAM_FLIP_Y:              c_int = 4;

/// `struct mpv_render_param { enum type; void *data; }`
#[repr(C)]
struct MpvRenderParam { kind: c_int, data: *mut c_void }

/// `struct mpv_opengl_init_params { void *(*get_proc_address)(void*, const char*); void *ctx; }`
#[repr(C)]
struct MpvOpenglInitParams {
    get_proc_address: unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_void,
    get_proc_address_ctx: *mut c_void,
}

/// `struct mpv_opengl_fbo { int fbo; int w; int h; int internal_format; }`
#[repr(C)]
struct MpvOpenglFbo { fbo: c_int, w: c_int, h: c_int, internal_format: c_int }

/// Function pointers loaded from libmpv.dylib
struct MpvFns {
    create:              unsafe extern "C" fn() -> MpvHandle,
    initialize:          unsafe extern "C" fn(MpvHandle) -> c_int,
    destroy:             unsafe extern "C" fn(MpvHandle),
    set_option_string:   unsafe extern "C" fn(MpvHandle, *const c_char, *const c_char) -> c_int,
    set_property:        unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int,
    get_property:        unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int,
    command:             unsafe extern "C" fn(MpvHandle, *const *const c_char) -> c_int,
    // render API
    render_create:       unsafe extern "C" fn(*mut MpvRenderCtx, MpvHandle, *mut MpvRenderParam) -> c_int,
    #[allow(dead_code)]
    render_free:         unsafe extern "C" fn(MpvRenderCtx),
    render_render:       unsafe extern "C" fn(MpvRenderCtx, *mut MpvRenderParam) -> c_int,
    render_set_update_cb: unsafe extern "C" fn(MpvRenderCtx, unsafe extern "C" fn(*mut c_void), *mut c_void),
}
// MpvFns only stores function pointers (integers), safe to send across threads.
unsafe impl Send for MpvFns {}
unsafe impl Sync for MpvFns {}

/// Loaded libmpv library + cached function pointers
struct MpvLib {
    _lib: libloading::Library, // keep library loaded
    fns:  MpvFns,
}
unsafe impl Send for MpvLib {}
unsafe impl Sync for MpvLib {}

/// mpv instance handle + library reference
struct MpvInstance {
    lib:    &'static MpvLib,
    handle: MpvHandle,
}
unsafe impl Send for MpvInstance {}
unsafe impl Sync for MpvInstance {}

impl Drop for MpvInstance {
    fn drop(&mut self) {
        unsafe { (self.lib.fns.destroy)(self.handle) };
    }
}

// ─── Globals ──────────────────────────────────────────────────────────────────
static MPV_LIB: OnceLock<MpvLib>      = OnceLock::new();
static MPV_CTX: OnceLock<Mutex<MpvInstance>> = OnceLock::new();
// Whether our editing subtitle track is currently loaded into mpv. Reset on each
// loadfile (which clears tracks) so the next mpv_set_subs does sub-add, not reload.
static SUBS_LOADED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn mpv_ctx() -> Option<&'static Mutex<MpvInstance>> { MPV_CTX.get() }

// ─── Library loader ───────────────────────────────────────────────────────────
/// macOS paths to try when loading libmpv.
fn libmpv_candidates() -> Vec<std::path::PathBuf> {
    let mut paths = Vec::new();
    // Homebrew ARM (Apple Silicon)
    paths.push("/opt/homebrew/lib/libmpv.dylib".into());
    // Homebrew Intel
    paths.push("/usr/local/lib/libmpv.dylib".into());
    // Fallback: let dyld search
    paths.push("libmpv.dylib".into());
    paths
}

fn try_load_mpv_lib() -> Result<MpvLib, String> {
    let candidates = libmpv_candidates();
    let mut last_err = String::new();

    for path in &candidates {
        let lib = unsafe { libloading::Library::new(path) };
        match lib {
            Err(e) => { last_err = e.to_string(); continue; }
            Ok(lib) => {
                macro_rules! sym {
                    ($name:literal, $ty:ty) => {
                        unsafe {
                            *lib.get::<$ty>($name)
                                .map_err(|e| format!("symbol {}: {e}", stringify!($name)))?
                        }
                    };
                }
                let fns = MpvFns {
                    create:            sym!(b"mpv_create\0",            unsafe extern "C" fn() -> MpvHandle),
                    initialize:        sym!(b"mpv_initialize\0",        unsafe extern "C" fn(MpvHandle) -> c_int),
                    destroy:           sym!(b"mpv_destroy\0",           unsafe extern "C" fn(MpvHandle)),
                    set_option_string: sym!(b"mpv_set_option_string\0", unsafe extern "C" fn(MpvHandle, *const c_char, *const c_char) -> c_int),
                    set_property:      sym!(b"mpv_set_property\0",      unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int),
                    get_property:      sym!(b"mpv_get_property\0",      unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int),
                    command:           sym!(b"mpv_command\0",           unsafe extern "C" fn(MpvHandle, *const *const c_char) -> c_int),
                    render_create:     sym!(b"mpv_render_context_create\0", unsafe extern "C" fn(*mut MpvRenderCtx, MpvHandle, *mut MpvRenderParam) -> c_int),
                    render_free:       sym!(b"mpv_render_context_free\0",   unsafe extern "C" fn(MpvRenderCtx)),
                    render_render:     sym!(b"mpv_render_context_render\0", unsafe extern "C" fn(MpvRenderCtx, *mut MpvRenderParam) -> c_int),
                    render_set_update_cb: sym!(b"mpv_render_context_set_update_callback\0", unsafe extern "C" fn(MpvRenderCtx, unsafe extern "C" fn(*mut c_void), *mut c_void)),
                };
                return Ok(MpvLib { _lib: lib, fns });
            }
        }
    }
    Err(format!("libmpv를 찾을 수 없습니다. 경로 시도: {:?}\n마지막 오류: {last_err}", candidates))
}

// ─── Safe mpv helpers ─────────────────────────────────────────────────────────
fn cstr(s: &str) -> CString { CString::new(s).unwrap_or_default() }

impl MpvInstance {
    fn set_str(&self, name: &str, val: &str) {
        let n = cstr(name); let v = cstr(val);
        let rc = unsafe { (self.lib.fns.set_option_string)(self.handle, n.as_ptr(), v.as_ptr()) };
        if rc < 0 { eprintln!("[mpv] set_option_string({name}={val}) failed rc={rc}"); }
    }

    fn set_double(&self, name: &str, val: f64) {
        let n = cstr(name);
        let mut v = val;
        unsafe { (self.lib.fns.set_property)(self.handle, n.as_ptr(), MPV_FORMAT_DOUBLE, &mut v as *mut _ as *mut c_void) };
    }

    fn set_flag(&self, name: &str, val: bool) {
        let n = cstr(name);
        let mut v: c_int = if val { 1 } else { 0 };
        unsafe { (self.lib.fns.set_property)(self.handle, n.as_ptr(), MPV_FORMAT_FLAG, &mut v as *mut _ as *mut c_void) };
    }

    fn get_double(&self, name: &str) -> Option<f64> {
        let n = cstr(name);
        let mut v: f64 = 0.0;
        let rc = unsafe { (self.lib.fns.get_property)(self.handle, n.as_ptr(), MPV_FORMAT_DOUBLE, &mut v as *mut _ as *mut c_void) };
        if rc == 0 { Some(v) } else { None }
    }

    fn get_flag(&self, name: &str) -> Option<bool> {
        let n = cstr(name);
        let mut v: c_int = 0;
        let rc = unsafe { (self.lib.fns.get_property)(self.handle, n.as_ptr(), MPV_FORMAT_FLAG, &mut v as *mut _ as *mut c_void) };
        if rc == 0 { Some(v != 0) } else { None }
    }

    fn command(&self, args: &[&str]) -> c_int {
        let cstrs: Vec<CString> = args.iter().map(|s| cstr(s)).collect();
        let mut ptrs: Vec<*const c_char> = cstrs.iter().map(|s| s.as_ptr()).collect();
        ptrs.push(std::ptr::null());
        unsafe { (self.lib.fns.command)(self.handle, ptrs.as_ptr()) }
    }
}

// ─── macOS: native NSView ─────────────────────────────────────────────────────
// ─── macOS: own an OpenGL surface and render mpv into it (render API) ──────────
// This mpv build (Homebrew 0.41) is Vulkan-only for the *standalone* vo, so `--wid`
// embedding is impossible. Instead we use `vo=libmpv` + the render API: we own a
// borderless child NSWindow whose NSView has an NSOpenGLContext, and we drive
// mpv_render_context_render ourselves. Owning the surface lets us repaint on
// demand (pause/resize/move) — fixing the black/stale-frame and move-jank bugs of
// the old "adopt mpv's own window" hack.
#[cfg(target_os = "macos")]
mod platform {
    use objc::runtime::Object;
    use objc::{class, msg_send, sel, sel_impl};
    use std::ffi::{c_char, c_int, c_void};
    use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, Ordering};

    // CGRect & co. — used as ARGUMENTS only (never msg_send! return types; struct
    // returns corrupt the stack with objc 0.2 on arm64).
    #[repr(C)] #[derive(Copy, Clone)] struct CGPoint { x: f64, y: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGSize  { width: f64, height: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGRect  { origin: CGPoint, size: CGSize }

    // NSOpenGLPixelFormatAttribute values
    const NSOPENGL_PFA_DOUBLE_BUFFER: u32 = 5;
    const NSOPENGL_PFA_COLOR_SIZE:    u32 = 8;
    const NSOPENGL_PFA_ALPHA_SIZE:    u32 = 11;
    const NSOPENGL_PFA_PROFILE:       u32 = 99;
    const NSOPENGL_PROFILE_3_2_CORE:  u32 = 0x3200;

    static PARENT_WIN: AtomicI64 = AtomicI64::new(0); // Tauri NSWindow
    static CHILD_WIN:  AtomicI64 = AtomicI64::new(0); // our borderless child window
    static GL_VIEW:    AtomicI64 = AtomicI64::new(0); // the NSView backing the GL surface
    static GL_CTX:     AtomicI64 = AtomicI64::new(0); // NSOpenGLContext
    static WANT_VISIBLE: AtomicBool = AtomicBool::new(true);
    static CUR_W_PX: AtomicI32 = AtomicI32::new(0); // FBO size in physical px
    static CUR_H_PX: AtomicI32 = AtomicI32::new(0);

    extern "C" {
        fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }

    /// get_proc_address for mpv's OpenGL renderer: resolve GL symbols from the
    /// system OpenGL framework. Passed to mpv_render_context_create.
    pub unsafe extern "C" fn gl_get_proc(_ctx: *mut c_void, name: *const c_char) -> *mut c_void {
        static GL_FW: AtomicI64 = AtomicI64::new(0);
        let mut h = GL_FW.load(Ordering::SeqCst) as *mut c_void;
        if h.is_null() {
            let p = b"/System/Library/Frameworks/OpenGL.framework/OpenGL\0";
            h = dlopen(p.as_ptr() as *const c_char, 2 /* RTLD_NOW */);
            GL_FW.store(h as i64, Ordering::SeqCst);
        }
        if h.is_null() { return std::ptr::null_mut(); }
        dlsym(h, name)
    }

    pub fn fbo_size() -> (i32, i32) { (CUR_W_PX.load(Ordering::SeqCst), CUR_H_PX.load(Ordering::SeqCst)) }

    pub unsafe fn make_current() {
        let ctx = GL_CTX.load(Ordering::SeqCst) as *mut Object;
        if !ctx.is_null() { let _: () = msg_send![ctx, makeCurrentContext]; }
    }
    pub unsafe fn flush_buffer() {
        let ctx = GL_CTX.load(Ordering::SeqCst) as *mut Object;
        if !ctx.is_null() { let _: () = msg_send![ctx, flushBuffer]; }
    }

    unsafe fn apply_visibility() {
        let child = CHILD_WIN.load(Ordering::SeqCst) as *mut Object;
        if child.is_null() { return; }
        let nil = std::ptr::null_mut::<Object>();
        if WANT_VISIBLE.load(Ordering::SeqCst) {
            let _: () = msg_send![child, orderFront: nil];
        } else {
            let _: () = msg_send![child, orderOut: nil];
        }
    }

    /// Show/hide the video surface (hide for audio-only / no media). Main thread.
    pub unsafe fn set_visible(visible: bool) {
        WANT_VISIBLE.store(visible, Ordering::SeqCst);
        apply_visibility();
    }

    /// Record the Tauri main window's NSWindow from its WKWebView. Main thread.
    pub unsafe fn set_parent_window(wk_ns_view: *mut Object) {
        let ns_window: *mut Object = msg_send![wk_ns_view, window];
        if !ns_window.is_null() { PARENT_WIN.store(ns_window as i64, Ordering::SeqCst); }
    }

    /// Create the borderless child window + NSView + NSOpenGLContext, attached as
    /// a child of the Tauri window. Idempotent. Main thread. Returns true on success.
    pub unsafe fn create_gl() -> bool {
        if GL_CTX.load(Ordering::SeqCst) != 0 { return true; }
        let parent = PARENT_WIN.load(Ordering::SeqCst) as *mut Object;
        if parent.is_null() { return false; }

        let rect = CGRect { origin: CGPoint { x: 0.0, y: 0.0 }, size: CGSize { width: 320.0, height: 180.0 } };
        let child: *mut Object = msg_send![class!(NSWindow), alloc];
        let child: *mut Object = msg_send![child,
            initWithContentRect: rect
            styleMask: 0usize      // borderless
            backing: 2usize        // buffered
            defer: 0u8];
        if child.is_null() { return false; }
        let _: () = msg_send![child, setOpaque: 1u8];
        let black: *mut Object = msg_send![class!(NSColor), blackColor];
        let _: () = msg_send![child, setBackgroundColor: black];

        // NSView backing the GL surface (best-resolution = render at pixel density).
        let view: *mut Object = msg_send![class!(NSView), alloc];
        let view: *mut Object = msg_send![view, initWithFrame: rect];
        let _: () = msg_send![view, setWantsBestResolutionOpenGLSurface: 1u8];
        let _: () = msg_send![child, setContentView: view];

        // Pixel format + context.
        let attrs: [u32; 9] = [
            NSOPENGL_PFA_DOUBLE_BUFFER,
            NSOPENGL_PFA_PROFILE, NSOPENGL_PROFILE_3_2_CORE,
            NSOPENGL_PFA_COLOR_SIZE, 24,
            NSOPENGL_PFA_ALPHA_SIZE, 8,
            0, 0,
        ];
        let pf: *mut Object = msg_send![class!(NSOpenGLPixelFormat), alloc];
        let pf: *mut Object = msg_send![pf, initWithAttributes: attrs.as_ptr()];
        if pf.is_null() { eprintln!("[mpv] NSOpenGLPixelFormat init failed"); return false; }
        let nil = std::ptr::null_mut::<Object>();
        let ctx: *mut Object = msg_send![class!(NSOpenGLContext), alloc];
        let ctx: *mut Object = msg_send![ctx, initWithFormat: pf shareContext: nil];
        if ctx.is_null() { eprintln!("[mpv] NSOpenGLContext init failed"); return false; }

        let _: () = msg_send![parent, addChildWindow: child ordered: 1i64]; // above
        let _: () = msg_send![ctx, setView: view];

        CHILD_WIN.store(child as i64, Ordering::SeqCst);
        GL_VIEW.store(view as i64, Ordering::SeqCst);
        GL_CTX.store(ctx as i64, Ordering::SeqCst);
        apply_visibility();
        eprintln!("[mpv] GL surface created (child {:p})", child);
        true
    }

    /// Reposition/resize the child window over the video panel and record the FBO
    /// pixel size. Main thread. `*_px` are physical pixels (css × dpr). After this
    /// the caller should render to repaint at the new size.
    pub unsafe fn set_frame(screen_x: f64, screen_y_from_bottom: f64, w: f64, h: f64, w_px: i32, h_px: i32) {
        CUR_W_PX.store(w_px.max(1), Ordering::SeqCst);
        CUR_H_PX.store(h_px.max(1), Ordering::SeqCst);
        let child = CHILD_WIN.load(Ordering::SeqCst) as *mut Object;
        if child.is_null() { return; }
        let frame = CGRect { origin: CGPoint { x: screen_x, y: screen_y_from_bottom }, size: CGSize { width: w, height: h } };
        let _: () = msg_send![child, setFrame: frame display: 1u8];
        let ctx = GL_CTX.load(Ordering::SeqCst) as *mut Object;
        if !ctx.is_null() { let _: () = msg_send![ctx, update]; } // GL surface follows view resize
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    pub fn set_visible(_visible: bool) {}
}

// ─── Render glue (macOS, OpenGL render API) ───────────────────────────────────
// We own the GL surface (platform::*) and call mpv_render_context_render whenever
// mpv has a new frame (update callback) or the surface changes (resize). All GL
// work runs on the main thread (NSOpenGLContext is not thread-safe).
#[cfg(target_os = "macos")]
static RENDER_CTX: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(0);
#[cfg(target_os = "macos")]
static APP_HANDLE: OnceLock<tauri::AppHandle> = OnceLock::new();

/// Render the current mpv frame into our GL surface. Main thread only.
#[cfg(target_os = "macos")]
fn render_now() {
    use std::sync::atomic::Ordering;
    let rc = RENDER_CTX.load(Ordering::SeqCst);
    if rc == 0 { return; }
    let Some(lib) = MPV_LIB.get() else { return };
    unsafe {
        platform::make_current();
        let (w, h) = platform::fbo_size();
        let mut fbo  = MpvOpenglFbo { fbo: 0, w, h, internal_format: 0 };
        let mut flip: c_int = 1;
        let mut params = [
            MpvRenderParam { kind: MPV_RENDER_PARAM_OPENGL_FBO, data: &mut fbo  as *mut _ as *mut c_void },
            MpvRenderParam { kind: MPV_RENDER_PARAM_FLIP_Y,     data: &mut flip as *mut _ as *mut c_void },
            MpvRenderParam { kind: 0, data: std::ptr::null_mut() },
        ];
        (lib.fns.render_render)(rc as MpvRenderCtx, params.as_mut_ptr());
        platform::flush_buffer();
    }
}

/// mpv → "new frame ready" (arbitrary thread). Hop to the main thread to render.
#[cfg(target_os = "macos")]
unsafe extern "C" fn on_render_update(_ctx: *mut c_void) {
    if let Some(app) = APP_HANDLE.get() {
        let _ = app.run_on_main_thread(render_now);
    }
}

// ─── Setup ────────────────────────────────────────────────────────────────────
// Only loads libmpv. Full mpv initialisation (including NSView setup) is deferred
// to the `mpv_init` command, which is called from VideoPlayer on mount — at that
// point the NSWindow is guaranteed to exist and the WKWebView is visible.
fn setup(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let _ = app; // unused on non-macOS too
    match try_load_mpv_lib() {
        Err(e) => eprintln!("[mpv] libmpv 로드 실패: {e}"),
        Ok(lib) => { MPV_LIB.set(lib).ok(); }
    }
    Ok(())
}

// ─── mpv_init — called once from VideoPlayer on mount ────────────────────────
// Deferred from setup() so the WKWebView is attached to its NSWindow first.
//
// We use `vo=libmpv` + the OpenGL render API: mpv has NO standalone vo we can
// embed (Vulkan-only build, no gl-cocoa), so instead WE own an OpenGL surface
// (platform::create_gl) and drive mpv_render_context_render. Owning the surface
// is what lets us repaint on demand (pause/resize/move).
#[tauri::command]
fn mpv_init(app: tauri::AppHandle) -> Result<(), String> {
    // Idempotent — ignore if already initialised (dock re-mount, etc.)
    if MPV_CTX.get().is_some() { return Ok(()); }

    let lib = MPV_LIB.get()
        .ok_or("libmpv를 찾을 수 없습니다. 설정에서 mpv를 설치하세요.")?;

    // ── Record the parent (Tauri) NSWindow on the main thread ─────────────────
    #[cfg(target_os = "macos")]
    {
        let (tx, rx) = std::sync::mpsc::channel::<()>();
        let app2 = app.clone();
        app.run_on_main_thread(move || {
            use raw_window_handle::{HasWindowHandle, RawWindowHandle};
            if let Some(window) = app2.get_webview_window("main") {
                if let Ok(h_raw) = window.window_handle() {
                    if let RawWindowHandle::AppKit(h) = h_raw.as_raw() {
                        let wk_view = h.ns_view.as_ptr() as *mut objc::runtime::Object;
                        unsafe { platform::set_parent_window(wk_view) };
                    }
                }
            }
            let _ = tx.send(());
        }).map_err(|e| format!("main thread dispatch 실패: {e:?}"))?;
        let _ = rx.recv();
    }

    // ── Create + initialise mpv ───────────────────────────────────────────────
    let handle = unsafe { (lib.fns.create)() };
    if handle.is_null() { return Err("mpv_create() returned null".to_string()); }

    let inst = MpvInstance { lib, handle };

    inst.set_str("vo",        "libmpv"); // output via the render API (we own the surface)
    inst.set_str("keep-open", "yes");
    inst.set_str("idle",      "yes");
    inst.set_str("input-default-bindings", "no");
    inst.set_str("input-vo-keyboard",      "no");
    inst.set_str("osc",                    "no");
    // Subtitles: mpv renders our editing doc (pushed via mpv_set_subs). Don't let
    // mpv auto-load the file's embedded/sidecar subs — only our track should show.
    inst.set_str("sub-auto",       "no");
    inst.set_str("sub-visibility", "yes");

    let rc = unsafe { (lib.fns.initialize)(handle) };
    if rc < 0 { return Err(format!("mpv_initialize() 실패: rc={rc}")); }

    // ── Build the GL surface + render context on the main thread ──────────────
    // (NSOpenGLContext.create + mpv_render_context_create must run with the GL
    // context current; we keep all GL work on the main thread.)
    #[cfg(target_os = "macos")]
    {
        APP_HANDLE.set(app.clone()).ok();
        let (tx, rx) = std::sync::mpsc::channel::<i32>();
        let handle_i = handle as i64;
        app.run_on_main_thread(move || {
            use std::sync::atomic::Ordering;
            unsafe {
                if !platform::create_gl() { let _ = tx.send(-100); return; }
                platform::make_current();
                let api = cstr("opengl");
                let mut gpa = MpvOpenglInitParams {
                    get_proc_address: platform::gl_get_proc,
                    get_proc_address_ctx: std::ptr::null_mut(),
                };
                let mut params = [
                    MpvRenderParam { kind: MPV_RENDER_PARAM_API_TYPE,           data: api.as_ptr() as *mut c_void },
                    MpvRenderParam { kind: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: &mut gpa as *mut _ as *mut c_void },
                    MpvRenderParam { kind: 0, data: std::ptr::null_mut() },
                ];
                let lib = MPV_LIB.get().unwrap();
                let mut rctx: MpvRenderCtx = std::ptr::null_mut();
                let rc = (lib.fns.render_create)(&mut rctx, handle_i as MpvHandle, params.as_mut_ptr());
                if rc < 0 || rctx.is_null() { let _ = tx.send(rc); return; }
                RENDER_CTX.store(rctx as i64, Ordering::SeqCst);
                (lib.fns.render_set_update_cb)(rctx, on_render_update, std::ptr::null_mut());
                let _ = tx.send(0);
            }
        }).map_err(|e| format!("main thread dispatch 실패: {e:?}"))?;
        match rx.recv() {
            Ok(0) => eprintln!("[mpv] render context ready"),
            Ok(code) => eprintln!("[mpv] render context 생성 실패: rc={code}"),
            Err(_) => eprintln!("[mpv] render context: main thread 응답 없음"),
        }
    }

    MPV_CTX.set(Mutex::new(inst))
        .map_err(|_| "MPV_CTX가 이미 초기화됨".to_string())?;

    // Poll thread: forward playback state to the frontend every 80 ms
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(80));
        let Some(m) = mpv_ctx() else { continue };
        let Ok(g)   = m.try_lock()  else { continue };
        if let Some(t) = g.get_double("time-pos") { let _ = app.emit("mpv-time-pos", t); }
        if let Some(d) = g.get_double("duration")  { if d > 0.0 { let _ = app.emit("mpv-duration", d); } }
        if let Some(p) = g.get_flag("pause")        { let _ = app.emit("mpv-paused", p); }
    });

    Ok(())
}

// ─── media:// URI scheme (Waveform file serving) ──────────────────────────────
fn mime_type(path: &str) -> &'static str {
    let ext = Path::new(path).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    match ext.as_str() {
        "mp4"|"m4v"=>"video/mp4","mov"=>"video/quicktime","mkv"=>"video/x-matroska",
        "avi"=>"video/x-msvideo","webm"=>"video/webm","mp3"=>"audio/mpeg",
        "aac"=>"audio/aac","m4a"=>"audio/mp4","wav"=>"audio/wav","flac"=>"audio/flac",
        "ogg"|"opus"=>"audio/ogg","aiff"|"aif"=>"audio/aiff",_=>"application/octet-stream",
    }
}
fn extract_media_path(uri: &str) -> Option<String> {
    let q = uri.split('?').nth(1)?;
    for pair in q.split('&') {
        if let Some(v) = pair.strip_prefix("path=") {
            return urlencoding::decode(v).ok().map(|c| c.into_owned());
        }
    }
    None
}
fn serve_media(req: tauri::http::Request<Vec<u8>>, resp: tauri::UriSchemeResponder) {
    let path = match extract_media_path(&req.uri().to_string()) {
        Some(p) => p,
        None => { let _ = resp.respond(tauri::http::Response::builder().status(400).body(vec![]).unwrap()); return; }
    };
    let mut file = match std::fs::File::open(&path) {
        Ok(f) => f,
        Err(_) => { let _ = resp.respond(tauri::http::Response::builder().status(404).body(vec![]).unwrap()); return; }
    };
    let total = file.metadata().map(|m| m.len()).unwrap_or(0);
    if total == 0 {
        let _ = resp.respond(tauri::http::Response::builder().status(200)
            .header("Content-Type", mime_type(&path)).header("Accept-Ranges","bytes").body(vec![]).unwrap());
        return;
    }
    let range = req.headers().get("range").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let (start, req_end, is_range) = if let Some(r) = range.strip_prefix("bytes=") {
        let mut p = r.splitn(2, '-');
        let s = p.next().and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
        let e = p.next().and_then(|v| v.parse::<u64>().ok()).unwrap_or(total-1);
        (s, e, true)
    } else { (0u64, total-1, false) };
    let end = req_end.min(start + 16*1024*1024 - 1).min(total-1);
    if start > end { let _ = resp.respond(tauri::http::Response::builder().status(416).body(vec![]).unwrap()); return; }
    let mut buf = vec![0u8; (end-start+1) as usize];
    if file.seek(SeekFrom::Start(start)).is_err() || file.read_exact(&mut buf).is_err() {
        let _ = resp.respond(tauri::http::Response::builder().status(500).body(vec![]).unwrap()); return;
    }
    let status = if is_range || start > 0 { 206 } else { 200 };
    let mut b = tauri::http::Response::builder().status(status)
        .header("Content-Type", mime_type(&path))
        .header("Content-Length", buf.len().to_string())
        .header("Accept-Ranges","bytes").header("Access-Control-Allow-Origin","*");
    if status == 206 { b = b.header("Content-Range", format!("bytes {start}-{end}/{total}")); }
    let _ = resp.respond(b.body(buf).unwrap());
}

// ─── File I/O ────────────────────────────────────────────────────────────────
#[tauri::command]
async fn read_text_file(path: String) -> Result<String, String> { std::fs::read_to_string(&path).map_err(|e| e.to_string()) }
#[tauri::command]
async fn write_text_file(path: String, content: String) -> Result<(), String> { std::fs::write(&path, content).map_err(|e| e.to_string()) }
#[tauri::command]
async fn read_binary_file(path: String) -> Result<Vec<u8>, String> { std::fs::read(&path).map_err(|e| e.to_string()) }

// ─── mpv availability ────────────────────────────────────────────────────────
#[tauri::command]
fn check_mpv() -> bool { MPV_CTX.get().is_some() }

/// Install mpv via Homebrew and emit progress events.
/// The app must be restarted after installation to load the new libmpv.
#[tauri::command]
async fn install_mpv(app: tauri::AppHandle) -> Result<(), String> {
    let emit = |msg: &str| { let _ = app.emit("mpv-install-progress", msg.to_string()); };

    // Find brew
    let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        .iter().find(|p| Path::new(p).exists())
        .map(|s| s.to_string())
        .ok_or("Homebrew가 설치되어 있지 않습니다.\nhttps://brew.sh 에서 먼저 설치하세요.")?;

    emit("Homebrew로 mpv 설치 중…");

    let output = tokio::task::spawn_blocking(move || {
        std::process::Command::new(&brew)
            .args(["install", "mpv"])
            .output()
            .map_err(|e| format!("brew 실행 실패: {e}"))
    }).await.map_err(|e| format!("내부 오류: {e}"))??;

    if output.status.success() {
        emit("설치 완료! 앱을 재시작하면 mpv가 활성화됩니다.");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("설치 실패:\n{}", &stderr[stderr.len().saturating_sub(500)..]))
    }
}

// ─── Waveform audio extraction ────────────────────────────────────────────────
/// Decode the media's audio track to a small, mono, low-rate WAV in the temp dir
/// and return its path. WaveSurfer can't decode a multi-hundred-MB video via
/// WebAudio (it would download + decodeAudioData the whole file), so we let mpv
/// downsample it first (≈1.5 s for a 22-min file → ~20 MB WAV). Cached per input.
#[tauri::command]
async fn extract_waveform_audio(path: String) -> Result<String, String> {
    use std::hash::{Hash, Hasher};

    let mpv_bin = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"]
        .iter().find(|p| Path::new(p).exists())
        .map(|s| s.to_string())
        .ok_or("mpv 실행 파일을 찾을 수 없습니다.")?;

    // Stable temp filename per (path, mtime) so re-opening reuses the cache.
    let mtime = std::fs::metadata(&path).ok()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs()).unwrap_or(0);
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    path.hash(&mut hasher);
    mtime.hash(&mut hasher);
    let out = std::env::temp_dir().join(format!("glyphline_wave_{:x}.wav", hasher.finish()));
    let out_str = out.to_string_lossy().to_string();
    if out.exists() { return Ok(out_str); }

    let out2 = out_str.clone();
    let status = tokio::task::spawn_blocking(move || {
        std::process::Command::new(&mpv_bin)
            .args([
                &path, "--no-config", "--vid=no",
                &format!("--o={out2}"), "--of=wav", "--oac=pcm_s16le",
                "--af=format=channels=1,aresample=8000",
                "--msg-level=all=no",
            ])
            .status()
    }).await.map_err(|e| format!("내부 오류: {e}"))?
      .map_err(|e| format!("mpv 실행 실패: {e}"))?;

    if status.success() && out.exists() { Ok(out_str) }
    else { Err("오디오 추출 실패".to_string()) }
}

// ─── mpv playback commands ────────────────────────────────────────────────────
macro_rules! with_mpv {
    ($body:expr) => {
        match mpv_ctx() {
            None => Err("mpv를 사용할 수 없습니다. 설정에서 mpv를 설치하세요.".to_string()),
            Some(m) => { let g = m.lock().unwrap(); $body(&g) }
        }
    };
}

#[tauri::command]
fn mpv_open(path: String) -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| {
        let rc = g.command(&["loadfile", &path, "replace"]);
        if rc < 0 { Err(format!("loadfile 실패: {rc}")) }
        else {
            // loadfile clears all tracks → our editing sub track is gone too.
            SUBS_LOADED.store(false, std::sync::atomic::Ordering::SeqCst);
            Ok(())
        }
    })
}

/// Render the editing subtitles: the frontend passes ASS text (serializeAss(doc));
/// we write it to a fixed temp file and add/reload it as mpv's sub track. First
/// call adds + selects; later calls reload the same path (cheap, used on every
/// debounced cue edit). Empty content removes the track.
#[tauri::command]
fn mpv_set_subs(content: String) -> Result<(), String> {
    use std::sync::atomic::Ordering;
    let sub_path = std::env::temp_dir().join("glyphline_subs.ass");
    std::fs::write(&sub_path, &content).map_err(|e| format!("자막 임시파일 쓰기 실패: {e}"))?;
    let path = sub_path.to_string_lossy().to_string();
    with_mpv!(|g: &MpvInstance| {
        if SUBS_LOADED.swap(true, Ordering::SeqCst) {
            g.command(&["sub-reload"]);
        } else {
            g.command(&["sub-add", &path, "select"]);
        }
        Ok(())
    })
}

/// Show or hide the adopted mpv window (hide for audio-only / no media / errors
/// so the React placeholders underneath become visible). macOS Cocoa op → main thread.
#[tauri::command]
fn mpv_set_window_visible(app: tauri::AppHandle, visible: bool) {
    #[cfg(target_os = "macos")]
    {
        let _ = app.run_on_main_thread(move || unsafe { platform::set_visible(visible) });
    }
    #[cfg(not(target_os = "macos"))]
    { let _ = (app, visible); }
}
#[tauri::command]
fn mpv_play_pause() -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { let p = g.get_flag("pause").unwrap_or(false); g.set_flag("pause", !p); Ok(()) })
}
#[tauri::command]
fn mpv_set_pause(pause: bool) -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { g.set_flag("pause", pause); Ok(()) })
}
#[tauri::command]
fn mpv_seek(pos: f64) -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { let s = pos.to_string(); g.command(&["seek", &s, "absolute"]); Ok(()) })
}
#[tauri::command]
fn mpv_skip(delta: f64) -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { let s = delta.to_string(); g.command(&["seek", &s, "relative"]); Ok(()) })
}
#[tauri::command]
fn mpv_set_speed(speed: f64) -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { g.set_double("speed", speed); Ok(()) })
}
#[tauri::command]
fn mpv_stop() -> Result<(), String> {
    with_mpv!(|g: &MpvInstance| { g.command(&["stop"]); Ok(()) })
}
#[tauri::command]
fn mpv_set_bounds(
    app: tauri::AppHandle,
    x: f64, y: f64, w: f64, h: f64,
    dpr: f64,
    _viewport_h: f64,
) {
    // Convert CSS viewport coords → NSWindow screen points.
    //
    // CSS x/y/w/h are in logical pixels relative to viewport top-left (= window top-left).
    // NSWindow frame is in screen points (logical pixels, Y=0 at bottom-left of primary screen).
    //
    // Tauri Window.position() → PhysicalPosition (physical px from screen top-left).
    // Divide by dpr → logical pts.  Flip Y using primary screen height.
    #[cfg(target_os = "macos")]
    {
        let win = match app.get_webview_window("main") { Some(w) => w, None => return };
        let pos = match win.outer_position() { Ok(p) => p, Err(_) => return };
        let screen_h_phys = app.primary_monitor()
            .ok().flatten()
            .map(|m| m.size().height as f64)
            .unwrap_or(dpr * 900.0); // fallback: 900pt screen

        // Convert parent window origin from physical px to logical pts
        let parent_x  = pos.x as f64 / dpr;
        let parent_top = pos.y as f64 / dpr; // distance from screen top in pts
        let screen_h   = screen_h_phys / dpr;

        // CSS (x, y) is relative to window top-left; NSWindow Y is from screen bottom.
        let child_x = parent_x + x;
        let child_y = screen_h - parent_top - y - h; // Y of bottom edge from screen bottom
        let w_px = (w * dpr).round() as i32;
        let h_px = (h * dpr).round() as i32;

        // setFrame + repaint are Cocoa/GL ops → main thread. (We do NOT reposition
        // on window MOVE: addChildWindow makes the OS track the parent for us.)
        let _ = app.run_on_main_thread(move || {
            unsafe { platform::set_frame(child_x, child_y, w, h, w_px, h_px) };
            render_now();
        });
    }
    #[cfg(not(target_os = "macos"))]
    { let _ = (app, x, y, w, h, dpr, _viewport_h); }
}

// ─── Entry point ─────────────────────────────────────────────────────────────
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| { setup(app)?; Ok(()) })
        .register_asynchronous_uri_scheme_protocol("media", |_app, req, resp| {
            std::thread::spawn(move || serve_media(req, resp));
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            read_text_file, write_text_file, read_binary_file,
            check_mpv, install_mpv,
            extract_waveform_audio,
            mpv_init,
            mpv_open, mpv_play_pause, mpv_set_pause,
            mpv_seek, mpv_skip, mpv_set_speed, mpv_stop,
            mpv_set_bounds, mpv_set_subs, mpv_set_window_visible,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
