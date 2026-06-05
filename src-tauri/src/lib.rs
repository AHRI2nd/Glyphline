// Glyphline — Tauri backend.
//
// Generic file I/O commands. Unlike Lyrical Sync (which named these read_lrc_file
// etc.), these are format-agnostic: any text subtitle format (.srt/.vtt/.ass/.smi)
// or the native .glyph project file goes through read_text_file/write_text_file.

/// Read any UTF-8 text file (subtitle source or .glyph project).
#[tauri::command]
async fn read_text_file(path: String) -> Result<String, String> {
    std::fs::read_to_string(&path).map_err(|e| e.to_string())
}

/// Write any UTF-8 text file (subtitle source or .glyph project).
#[tauri::command]
async fn write_text_file(path: String, content: String) -> Result<(), String> {
    std::fs::write(&path, content).map_err(|e| e.to_string())
}

/// Read a binary file as raw bytes. Reserved for future media work
/// (video/waveform); unused by the editing core today.
#[tauri::command]
async fn read_binary_file(path: String) -> Result<Vec<u8>, String> {
    std::fs::read(&path).map_err(|e| e.to_string())
}

// ─── Entry point ──────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            read_text_file,
            write_text_file,
            read_binary_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
