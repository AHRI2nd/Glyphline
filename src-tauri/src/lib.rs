// Glyphline — Tauri backend.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use futures_util::StreamExt;
use tauri::{Emitter, Manager};

// ─── Temp-file registry ───────────────────────────────────────────────────────

fn temp_files() -> &'static Mutex<HashSet<String>> {
    static T: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    T.get_or_init(|| Mutex::new(HashSet::new()))
}

// ─── FFmpeg path helpers ──────────────────────────────────────────────────────

fn ffmpeg_bin_name() -> &'static str {
    if cfg!(windows) { "ffmpeg.exe" } else { "ffmpeg" }
}

/// Directory where the app stores its own downloaded ffmpeg binary.
fn ffmpeg_managed_dir(app: &tauri::AppHandle) -> Option<PathBuf> {
    app.path().app_data_dir().ok().map(|d| d.join("ffmpeg"))
}

/// Locate ffmpeg: app-managed install first, then system PATH.
/// Returns the path/command string to use, or None if not found.
fn find_ffmpeg(app: &tauri::AppHandle) -> Option<String> {
    // 1. App-managed install
    if let Some(dir) = ffmpeg_managed_dir(app) {
        let p = dir.join(ffmpeg_bin_name());
        if p.exists() {
            return Some(p.to_string_lossy().into_owned());
        }
    }
    // 2. System PATH
    let ok = std::process::Command::new("ffmpeg")
        .arg("-version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if ok { Some("ffmpeg".to_string()) } else { None }
}

// ─── Native codec detection ───────────────────────────────────────────────────

/// Formats WKWebView / WebView2 can decode without FFmpeg.
const NATIVE_EXTS: &[&str] = &[
    "mp4", "m4v", "mov",
    "mp3", "m4a", "aac", "wav", "flac", "aiff", "aif",
];

fn is_native(path: &str) -> bool {
    let ext = Path::new(path)
        .extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    NATIVE_EXTS.contains(&ext.as_str())
}

// ─── Transcoding (via detected ffmpeg) ───────────────────────────────────────

fn transcode_to_mp4(ffmpeg: &str, src: &str) -> Result<String, String> {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis();
    let tmp = std::env::temp_dir().join(format!("glyphline_{millis}.mp4"));
    let tmp_str = tmp.to_str().ok_or("임시 경로 오류")?.to_string();

    let out = std::process::Command::new(ffmpeg)
        .args(["-i", src, "-c:v", "libx264", "-preset", "ultrafast",
               "-crf", "23", "-c:a", "aac", "-b:a", "192k",
               "-movflags", "+faststart", "-y", &tmp_str])
        .output()
        .map_err(|e| format!("ffmpeg 실행 실패: {e}"))?;

    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(format!("변환 실패: {}", &err[err.len().saturating_sub(500)..]));
    }
    temp_files().lock().unwrap().insert(tmp_str.clone());
    Ok(tmp_str)
}

// ─── FFmpeg install ───────────────────────────────────────────────────────────

#[derive(Clone, serde::Serialize)]
struct FfmpegProgress { stage: String, percent: u8, message: String }

fn ffmpeg_download_url() -> &'static str {
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    return "https://evermeet.cx/ffmpeg/getrelease/arm64/ffmpeg/zip";
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    return "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip";
    #[cfg(windows)]
    return "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
    #[cfg(not(any(target_os = "macos", windows)))]
    return "";
}

fn extract_ffmpeg_zip(zip_bytes: &[u8], dest_dir: &Path) -> Result<(), String> {
    use std::io::Read;
    let cur = std::io::Cursor::new(zip_bytes);
    let mut archive = zip::ZipArchive::new(cur).map_err(|e| format!("ZIP 오류: {e}"))?;
    let target = ffmpeg_bin_name();

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| e.to_string())?;
        let name = entry.name().to_string();
        let base = name.split('/').last().unwrap_or(&name);
        if base != target { continue; }

        std::fs::create_dir_all(dest_dir).map_err(|e| e.to_string())?;
        let dest = dest_dir.join(target);
        let mut buf = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut buf).map_err(|e| e.to_string())?;
        std::fs::write(&dest, &buf).map_err(|e| e.to_string())?;

        // Unix: chmod +x
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut p = dest.metadata().map_err(|e| e.to_string())?.permissions();
            p.set_mode(0o755);
            std::fs::set_permissions(&dest, p).map_err(|e| e.to_string())?;
        }
        // macOS: remove Gatekeeper quarantine so the binary can actually run
        #[cfg(target_os = "macos")]
        let _ = std::process::Command::new("xattr")
            .args(["-d", "com.apple.quarantine", dest.to_str().unwrap_or("")])
            .output();

        return Ok(());
    }
    Err(format!("{target}을 ZIP에서 찾을 수 없습니다."))
}

// ─── Commands ─────────────────────────────────────────────────────────────────

#[tauri::command]
async fn read_text_file(path: String) -> Result<String, String> {
    std::fs::read_to_string(&path).map_err(|e| e.to_string())
}

#[tauri::command]
async fn write_text_file(path: String, content: String) -> Result<(), String> {
    std::fs::write(&path, content).map_err(|e| e.to_string())
}

#[tauri::command]
async fn read_binary_file(path: String) -> Result<Vec<u8>, String> {
    std::fs::read(&path).map_err(|e| e.to_string())
}

/// Returns the ffmpeg path/command if available, or null.
#[tauri::command]
fn check_ffmpeg(app: tauri::AppHandle) -> Option<String> {
    find_ffmpeg(&app)
}

/// Download and install ffmpeg into the app data directory.
/// Emits "ffmpeg-progress" events: { stage, percent, message }.
#[tauri::command]
async fn install_ffmpeg(app: tauri::AppHandle) -> Result<(), String> {
    let url = ffmpeg_download_url();
    if url.is_empty() {
        return Err("이 플랫폼은 자동 설치를 지원하지 않습니다.".to_string());
    }

    let emit = |stage: &str, percent: u8, msg: &str| {
        let _ = app.emit("ffmpeg-progress", FfmpegProgress {
            stage: stage.to_string(), percent, message: msg.to_string(),
        });
    };

    emit("downloading", 0, "서버에 연결 중…");

    let client = reqwest::Client::builder()
        .user_agent("Glyphline/0.1.0")
        .build().map_err(|e| e.to_string())?;

    let resp = client.get(url).send().await
        .map_err(|e| format!("연결 실패: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("다운로드 실패: HTTP {}", resp.status()));
    }

    let total = resp.content_length().unwrap_or(0);
    let mut downloaded = 0u64;
    let mut zip_bytes: Vec<u8> = Vec::with_capacity(total as usize);
    let mut stream = resp.bytes_stream();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("다운로드 중단: {e}"))?;
        downloaded += chunk.len() as u64;
        zip_bytes.extend_from_slice(&chunk);
        let pct = if total > 0 { ((downloaded * 100) / total) as u8 } else { 0 };
        emit("downloading", pct, &format!("다운로드 중… {:.1} MB", downloaded as f64 / 1_048_576.0));
    }

    emit("extracting", 0, "압축 해제 중…");

    let dest_dir = ffmpeg_managed_dir(&app).ok_or("앱 데이터 경로 오류")?;
    tokio::task::spawn_blocking(move || extract_ffmpeg_zip(&zip_bytes, &dest_dir))
        .await.map_err(|e| format!("내부 오류: {e}"))??;

    emit("done", 100, "설치 완료!");
    Ok(())
}

/// Prepare a media file for WKWebView/WebView2 playback.
/// Native formats are returned as-is; others are transcoded via ffmpeg.
/// Returns "FFMPEG_NOT_FOUND" error string when ffmpeg is unavailable.
#[tauri::command]
async fn prepare_media(app: tauri::AppHandle, path: String) -> Result<String, String> {
    if is_native(&path) { return Ok(path); }
    let ffmpeg = find_ffmpeg(&app).ok_or("FFMPEG_NOT_FOUND")?;
    tokio::task::spawn_blocking(move || transcode_to_mp4(&ffmpeg, &path))
        .await.map_err(|e| format!("내부 오류: {e}"))?
}

/// Remove all ffmpeg-generated temp preview files.
#[tauri::command]
fn cleanup_temp_media() {
    let mut files = temp_files().lock().unwrap();
    for path in files.drain() { let _ = std::fs::remove_file(&path); }
}

// ─── Entry point ──────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            read_text_file, write_text_file, read_binary_file,
            check_ffmpeg, install_ffmpeg,
            prepare_media, cleanup_temp_media,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
