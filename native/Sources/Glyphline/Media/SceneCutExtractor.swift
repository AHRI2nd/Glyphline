// Shot-change detection via ffmpeg's scene-score filter.
//
// This decodes the entire file (there's no shortcut — every frame has to be
// compared against the last to score a cut), so it's triggered on demand from
// the waveform pane rather than automatically on every media load like the
// waveform extraction is. Results are cached by (path, mtime, threshold) so
// re-running it on the same file/settings is instant.
//
// A SEPARATE dependency from mpv: this app's video/audio path is entirely
// libmpv, which doesn't expose a scriptable way to get scene-score metadata
// back to Swift without playing the file in real time. ffmpeg's CLI does this
// as an offline batch job, which is what detection actually is. Optional, same
// as mpv — the pane just says "install ffmpeg" and disables the button.

import Foundation
import CryptoKit
import GlyphlineCore

enum SceneCutExtractor {
    enum ExtractError: Error { case ffmpegNotFound, detectionFailed }

    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    static var ffmpegAvailable: Bool {
        ffmpegCandidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Default scene-score threshold (ffmpeg's `select='gt(scene,N)'`). Lower
    /// catches softer cuts (dissolves) at the cost of more false positives from
    /// fast pans/flashes; 0.4 is ffmpeg's own commonly-cited starting point.
    static let defaultThreshold = 0.4

    private static func cacheKey(path: String, mtime: TimeInterval, threshold: Double) -> String {
        let digest = SHA256.hash(data: Data("\(path)|\(mtime)|\(threshold)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Detect (or return the cached) cut list for `path`. Runs ffmpeg off the
    /// calling thread; safe to call from the main actor with `await`.
    static func detect(path: String, threshold: Double = defaultThreshold) async throws -> [Double] {
        guard let ffmpegBin = ffmpegCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ExtractError.ffmpegNotFound
        }

        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            .flatMap { $0 }?.timeIntervalSince1970 ?? 0
        let key = cacheKey(path: path, mtime: mtime, threshold: threshold)
        let cacheFile = FileManager.default.temporaryDirectory.appendingPathComponent("glyphline_cuts_\(key).json")

        if let cached = try? Data(contentsOf: cacheFile),
           let cuts = try? JSONDecoder().decode([Double].self, from: cached) {
            return cuts
        }

        // A full-length feature can take minutes to scan. Swift's task
        // cancellation is cooperative — cancelling the outer Task (e.g. the
        // user switches videos mid-scan) does NOT by itself stop a
        // synchronous `waitUntilExit()` already in flight, so without this
        // handle the ffmpeg process would keep burning CPU to completion in
        // the background even after the app has moved on and discarded
        // whatever it would have returned.
        try Task.checkCancellation() // already-cancelled-before-starting case

        let processBox = ProcessBox()
        let cuts = try await withTaskCancellationHandler {
            // Task.detached deliberately does NOT inherit cancellation from
            // the caller (that's what "detached" means), so the ONLY thing
            // that actually reaches a process already running inside it is
            // onCancel below terminating it directly — not a Task.isCancelled
            // check in here, which would never see the outer cancellation.
            try await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegBin)
                process.arguments = [
                    "-i", path,
                    "-filter:v", "select='gt(scene,\(threshold))',showinfo",
                    "-an", "-f", "null", "-",
                ]
                // ffmpeg writes showinfo to stderr, not stdout.
                let pipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = pipe
                processBox.process = process
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw ExtractError.detectionFailed }
                let text = String(data: output, encoding: .utf8) ?? ""
                return parseFFmpegSceneChangeOutput(text)
            }.value
        } onCancel: {
            processBox.terminate()
        }

        if let data = try? JSONEncoder().encode(cuts) {
            try? data.write(to: cacheFile)
        }
        return cuts
    }
}
