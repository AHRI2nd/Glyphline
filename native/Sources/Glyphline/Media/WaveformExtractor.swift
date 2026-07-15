// Downsample the media's audio to a small mono 8kHz WAV via the mpv CLI
// (ported from ../../../src-tauri/src/lib.rs's extract_waveform_audio).
//
// WHY: decoding a multi-hundred-MB video directly for waveform display is
// impractical (the Tauri build hit this trying to feed the original file to
// WebAudio). mpv downsamples once (~1.5s for a 22-min file → ~20MB WAV);
// cached by (path, mtime) so re-opening the same file is instant.

import Foundation

enum WaveformExtractor {
    enum ExtractError: Error { case mpvNotFound, extractionFailed }

    private static let mpvCandidates = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"]

    /// Extract (or return the cached) downsampled WAV path for `path`. Runs mpv
    /// off the calling thread; safe to call from the main actor with `await`.
    static func extract(path: String) async throws -> URL {
        guard let mpvBin = mpvCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ExtractError.mpvNotFound
        }

        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            .flatMap { $0 }?.timeIntervalSince1970 ?? 0
        var hasher = Hasher()
        hasher.combine(path)
        hasher.combine(mtime)
        let key = String(format: "%016x", UInt64(bitPattern: Int64(hasher.finalize())))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("glyphline_wave_\(key).wav")

        if FileManager.default.fileExists(atPath: out.path) { return out }

        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mpvBin)
            process.arguments = [
                path, "--no-config", "--vid=no",
                "--o=\(out.path)", "--of=wav", "--oac=pcm_s16le",
                "--af=format=channels=1,aresample=8000",
                "--msg-level=all=no",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: out.path) {
                throw ExtractError.extractionFailed
            }
        }.value

        return out
    }
}
