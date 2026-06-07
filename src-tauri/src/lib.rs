// Glyphline — Tauri backend (mpv video engine, dynamic libloading)

use std::ffi::{CString, c_char, c_int, c_void};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use tauri::{Emitter, Manager};

// ─── mpv C API — minimal bindings ────────────────────────────────────────────
// We load libmpv at runtime so the app can start even when mpv is not installed.

type MpvHandle = *mut c_void;

// mpv_format enum values we use (wid is set via set_option_string, not set_property)
const MPV_FORMAT_FLAG:   i32 = 3;
const MPV_FORMAT_DOUBLE: i32 = 5;

/// Function pointers loaded from libmpv.dylib
struct MpvFns {
    create:              unsafe extern "C" fn() -> MpvHandle,
    initialize:          unsafe extern "C" fn(MpvHandle) -> c_int,
    destroy:             unsafe extern "C" fn(MpvHandle),
    set_option_string:   unsafe extern "C" fn(MpvHandle, *const c_char, *const c_char) -> c_int,
    set_property:        unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int,
    get_property:        unsafe extern "C" fn(MpvHandle, *const c_char, c_int, *mut c_void) -> c_int,
    command:             unsafe extern "C" fn(MpvHandle, *const *const c_char) -> c_int,
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
#[cfg(target_os = "macos")]
mod platform {
    use objc::runtime::Object;
    use objc::{class, msg_send, sel, sel_impl};
    use std::sync::atomic::{AtomicI64, Ordering};

    // These structs are used as ARGUMENTS only — never as msg_send! return types.
    // Returning NSRect/CGRect via objc 0.2 is unsafe (struct-return ABI mismatch on arm64).
    #[repr(C)] #[derive(Copy, Clone)] struct CGPoint { x: f64, y: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGSize  { width: f64, height: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGRect  { origin: CGPoint, size: CGSize }

    // The Tauri main window's NSWindow (the adoption parent).
    static PARENT_WIN: AtomicI64 = AtomicI64::new(0);
    // mpv's own NSWindow once adopted as a borderless child (0 = not yet adopted).
    static MPV_WIN: AtomicI64 = AtomicI64::new(0);

    /// Record the Tauri main window's NSWindow pointer from its WKWebView.
    /// Must run on the main thread. Background: this mpv build (Homebrew 0.41,
    /// Vulkan-only, no OpenGL) has NO gl-cocoa context, so `--wid` embedding is
    /// impossible — the macvk backend always spawns its own NSWindow. Instead we
    /// adopt that window as a borderless child (see adopt_and_position).
    pub unsafe fn set_parent_window(wk_ns_view: *mut Object) {
        let ns_window: *mut Object = msg_send![wk_ns_view, window];
        if !ns_window.is_null() {
            PARENT_WIN.store(ns_window as i64, Ordering::SeqCst);
        }
    }

    /// Find mpv's standalone NSWindow, adopt it as a borderless child of the
    /// Tauri window, and position it over the video panel.
    /// MUST run on the main thread (Cocoa window ops are main-thread-only).
    /// `screen_x/screen_y_from_bottom/w/h` are NSWindow logical points
    /// (screen coords, Y=0 at bottom-left of the primary screen).
    pub unsafe fn adopt_and_position(screen_x: f64, screen_y_from_bottom: f64, w: f64, h: f64) {
        let parent = PARENT_WIN.load(Ordering::SeqCst) as *mut Object;
        if parent.is_null() { return; }

        let mut mpv_win = MPV_WIN.load(Ordering::SeqCst) as *mut Object;

        // ── Adopt once: locate mpv's window among the app's windows ────────────
        if mpv_win.is_null() {
            let nsapp: *mut Object = msg_send![class!(NSApplication), sharedApplication];
            let windows: *mut Object = msg_send![nsapp, windows];
            if windows.is_null() { return; }
            let count: usize = msg_send![windows, count];
            for i in 0..count {
                let w_obj: *mut Object = msg_send![windows, objectAtIndex: i];
                if w_obj.is_null() || w_obj == parent { continue; }
                // Skip windows that are already children (e.g. our own adoptee).
                let pw: *mut Object = msg_send![w_obj, parentWindow];
                if !pw.is_null() { continue; }
                // mpv's window is on-screen once force-window has created it.
                let visible: bool = msg_send![w_obj, isVisible];
                if !visible { continue; }
                // Candidate = mpv's window (single-window Tauri app → unambiguous).
                mpv_win = w_obj;
                break;
            }
            if mpv_win.is_null() { return; } // not created yet — caller retries later

            // Strip the title bar (NSWindowStyleMaskBorderless = 0) and attach as
            // a child so it tracks the parent and orders above the panel area.
            let _: () = msg_send![mpv_win, setStyleMask: 0usize];
            let _: () = msg_send![parent, addChildWindow: mpv_win ordered: 1i64]; // Above
            MPV_WIN.store(mpv_win as i64, Ordering::SeqCst);
            eprintln!("[mpv] adopted mpv window {:p} as child of {:p}", mpv_win, parent);
        }

        // ── Position over the video panel every call ──────────────────────────
        let frame = CGRect {
            origin: CGPoint { x: screen_x, y: screen_y_from_bottom },
            size:   CGSize  { width: w, height: h },
        };
        let _: () = msg_send![mpv_win, setFrame: frame display: 1u8];
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    pub fn adopt_and_position(_x: f64, _y: f64, _w: f64, _h: f64) {}
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
// IMPORTANT: this Homebrew mpv 0.41 build is Vulkan-only (no OpenGL / no
// gl-cocoa context), so `--wid` embedding is impossible — the macvk backend
// always spawns its own NSWindow. We let it do so, then adopt that window as a
// borderless child of the Tauri window (see platform::adopt_and_position, driven
// by mpv_set_bounds). `border=no` + `auto-window-resize=no` keep mpv from drawing
// a title bar or resizing itself to the video dimensions on file load.
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

    inst.set_str("keep-open", "yes");
    inst.set_str("idle",      "yes");
    inst.set_str("input-default-bindings", "no");
    inst.set_str("input-vo-keyboard",      "no");
    inst.set_str("osc",                    "no");
    // Window adoption support: borderless mpv window, immediately created, and
    // pinned to our size (don't let mpv resize itself to the video dimensions).
    inst.set_str("border",             "no");
    inst.set_str("force-window",       "yes");
    inst.set_str("auto-window-resize", "no");

    let rc = unsafe { (lib.fns.initialize)(handle) };
    if rc < 0 { return Err(format!("mpv_initialize() 실패: rc={rc}")); }

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
        if rc < 0 { Err(format!("loadfile 실패: {rc}")) } else { Ok(()) }
    })
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

        // Adoption + setFrame are Cocoa ops → must run on the main thread.
        let _ = app.run_on_main_thread(move || {
            unsafe { platform::adopt_and_position(child_x, child_y, w, h) };
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
            mpv_set_bounds,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
