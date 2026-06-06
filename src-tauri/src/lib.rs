// Glyphline — Tauri backend (mpv video engine, dynamic libloading)

use std::ffi::{CString, c_char, c_int, c_void};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use tauri::{Emitter, Manager};

// ─── mpv C API — minimal bindings ────────────────────────────────────────────
// We load libmpv at runtime so the app can start even when mpv is not installed.

type MpvHandle = *mut c_void;

// mpv_format enum values we use
const MPV_FORMAT_FLAG:   i32 = 3;
const MPV_FORMAT_INT64:  i32 = 4;
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
        unsafe { (self.lib.fns.set_option_string)(self.handle, n.as_ptr(), v.as_ptr()) };
    }

    fn set_i64(&self, name: &str, val: i64) {
        let n = cstr(name);
        let mut v = val;
        unsafe { (self.lib.fns.set_property)(self.handle, n.as_ptr(), MPV_FORMAT_INT64, &mut v as *mut _ as *mut c_void) };
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
    use std::sync::OnceLock;

    #[repr(C)] #[derive(Copy, Clone)] struct CGPoint { x: f64, y: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGSize  { width: f64, height: f64 }
    #[repr(C)] #[derive(Copy, Clone)] struct CGRect  { origin: CGPoint, size: CGSize }

    static VIEW_PTR: OnceLock<i64> = OnceLock::new();

    pub unsafe fn create_video_view(wk_ns_view: *mut Object) -> i64 {
        let ns_window: *mut Object  = msg_send![wk_ns_view, window];
        let content_view: *mut Object = msg_send![ns_window, contentView];
        let zero = CGRect { origin: CGPoint { x: 0.0, y: 0.0 }, size: CGSize { width: 1.0, height: 1.0 } };
        let view: *mut Object = msg_send![class!(NSView), alloc];
        let view: *mut Object = msg_send![view, initWithFrame: zero];
        let _: () = msg_send![content_view, insertSubview: view atIndex: 0usize];
        let ptr = view as i64;
        VIEW_PTR.get_or_init(|| ptr);
        ptr
    }

    pub fn set_bounds(x: f64, y: f64, w: f64, h: f64, dpr: f64, viewport_h: f64) {
        let ptr = match VIEW_PTR.get() { Some(p) => *p as *mut Object, None => return };
        let frame = CGRect {
            origin: CGPoint { x: x * dpr, y: (viewport_h - y - h) * dpr },
            size:   CGSize  { width: w * dpr, height: h * dpr },
        };
        unsafe { let _: () = msg_send![ptr, setFrame: frame]; }
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    pub fn set_bounds(_x: f64, _y: f64, _w: f64, _h: f64, _dpr: f64, _vh: f64) {}
}

// ─── Setup ────────────────────────────────────────────────────────────────────
fn setup(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    eprintln!("[setup] 시작");
    // Attempt to load libmpv. Non-fatal — app runs with video disabled if unavailable.
    match try_load_mpv_lib() {
        Err(e) => {
            eprintln!("[mpv] 로드 실패: {e}");
            eprintln!("[setup] mpv 없이 계속");
            return Ok(()); // app continues without video
        }
        Ok(lib) => {
            eprintln!("[mpv] 라이브러리 로드 성공");
            MPV_LIB.set(lib).ok();
        }
    }

    eprintln!("[setup] MPV_LIB.get() 시도");
    let lib = MPV_LIB.get().unwrap();
    eprintln!("[setup] mpv_create() 호출");
    let handle = unsafe { (lib.fns.create)() };
    if handle.is_null() {
        eprintln!("[mpv] mpv_create() returned null");
        return Ok(());
    }
    eprintln!("[setup] mpv handle 생성 완료: {:p}", handle);

    // Acquire NSView for mpv to render into
    eprintln!("[setup] NSView 생성 시도");
    let wid: i64 = {
        #[cfg(target_os = "macos")]
        {
            use raw_window_handle::{HasWindowHandle, RawWindowHandle};
            if let Some(window) = app.get_webview_window("main") {
                eprintln!("[setup] webview_window 획득");
                if let Ok(h_raw) = window.window_handle() {
                    eprintln!("[setup] window_handle 획득");
                    if let RawWindowHandle::AppKit(h) = h_raw.as_raw() {
                        eprintln!("[setup] AppKit handle 획득, NSView 생성");
                        let wk_view = h.ns_view.as_ptr() as *mut objc::runtime::Object;
                        let v = unsafe { platform::create_video_view(wk_view) };
                        eprintln!("[setup] NSView 생성 완료: {v}");
                        v
                    } else { eprintln!("[setup] AppKit handle 아님"); 0 }
                } else { eprintln!("[setup] window_handle 실패"); 0 }
            } else { eprintln!("[setup] webview_window 없음"); 0 }
        }
        #[cfg(not(target_os = "macos"))]
        { 0i64 }
    };

    eprintln!("[setup] wid = {wid}, MpvInstance 생성");
    let inst = MpvInstance { lib, handle };
    // Set wid BEFORE initialize
    if wid != 0 {
        eprintln!("[setup] set_i64 wid");
        inst.set_i64("wid", wid);
    }
    eprintln!("[setup] set_str options");
    inst.set_str("keep-open", "yes");
    inst.set_str("idle", "yes");
    inst.set_str("input-default-bindings", "no");
    inst.set_str("input-vo-keyboard", "no");
    inst.set_str("osc", "no");

    eprintln!("[setup] mpv_initialize() 호출");
    let rc = unsafe { (lib.fns.initialize)(handle) };
    eprintln!("[setup] mpv_initialize() 반환: {rc}");
    if rc < 0 { eprintln!("[mpv] mpv_initialize() failed: {rc}"); return Ok(()); }

    eprintln!("[setup] MPV_CTX 설정");
    MPV_CTX.set(Mutex::new(inst)).ok();

    // Poll thread: forward time/pause state to the frontend every 80ms
    eprintln!("[setup] 폴 스레드 시작");
    let app_handle = app.handle().clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(80));
        let Some(m) = mpv_ctx() else { continue };
        let Ok(g) = m.try_lock() else { continue };
        if let Some(t) = g.get_double("time-pos") { let _ = app_handle.emit("mpv-time-pos", t); }
        if let Some(d) = g.get_double("duration")  { if d > 0.0 { let _ = app_handle.emit("mpv-duration", d); } }
        if let Some(p) = g.get_flag("pause")        { let _ = app_handle.emit("mpv-paused", p); }
    });

    eprintln!("[setup] 완료 Ok(())");
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
fn mpv_set_bounds(x: f64, y: f64, w: f64, h: f64, dpr: f64, viewport_h: f64) {
    platform::set_bounds(x, y, w, h, dpr, viewport_h);
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
            mpv_open, mpv_play_pause, mpv_set_pause,
            mpv_seek, mpv_skip, mpv_set_speed, mpv_stop,
            mpv_set_bounds,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
