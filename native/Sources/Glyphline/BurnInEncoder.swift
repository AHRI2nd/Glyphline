// Burns the current document's subtitles into a copy of the loaded video via
// ffmpeg's `ass` filter — a review file a client or QC pass can watch without
// needing this app or a player that supports the source subtitle format.

import Foundation
import GlyphlineCore

enum BurnInEncoder {
    enum EncodeError: Error, CustomStringConvertible {
        case ffmpegNotFound
        case processFailed(Int32, String)
        var description: String {
            switch self {
            case .ffmpegNotFound: return "ffmpeg가 설치되어 있지 않습니다 (brew install ffmpeg)."
            case .processFailed(let code, let tail): return "ffmpeg 종료 코드 \(code): \(tail)"
            }
        }
    }

    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    static var ffmpegAvailable: Bool {
        ffmpegCandidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Runs the encode off the calling thread, reporting fractional progress
    /// (0...1, best-effort — nil if ffmpeg's stderr didn't include a
    /// parseable `time=` this tick) via `onProgress` on the main actor.
    /// Writes the current document to a temp ASS file itself, so the burned
    /// text always matches what's on screen right now, edits included.
    static func encode(
        videoPath: String,
        document: SubtitleDocument,
        outputPath: String,
        durationHint: Double,
        onProgress: @escaping @MainActor (Double?) -> Void
    ) async throws {
        guard let ffmpegBin = ffmpegCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw EncodeError.ffmpegNotFound
        }
        let assPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("glyphline_burnin_\(UUID().uuidString).ass").path
        let assText = serializeAss(withDefaultStyleIfNeeded(document))
        try assText.write(toFile: assPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: assPath) }

        // ffmpeg's filter graph parses ':' as an option separator, so a path
        // containing one (any macOS path under a colon-bearing volume name,
        // though rare) must be escaped: `\:`. Backslashes doubled first so an
        // already-escaped input isn't corrupted.
        let escapedAss = assPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ":", with: "\\:")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegBin)
            process.arguments = [
                "-y", "-i", videoPath,
                "-vf", "ass=\(escapedAss)",
                "-c:v", "libx264", "-crf", "20", "-preset", "medium",
                "-c:a", "copy",
                outputPath,
            ]
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = FileHandle.nullDevice

            let tail = TailBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                tail.append(text)
                if let seconds = parseFFmpegTime(text), durationHint > 0 {
                    let fraction = min(1, max(0, seconds / durationHint))
                    Task { @MainActor in onProgress(fraction) }
                }
            }
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EncodeError.processFailed(proc.terminationStatus, tail.joined()))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Last ~20 lines of ffmpeg's stderr, for the error message if it fails.
/// Foundation calls `readabilityHandler` and `terminationHandler` on its own
/// background queues (not necessarily the same one), so this needs its own
/// lock rather than a plain captured array.
private final class TailBuffer: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()
    func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        for line in text.split(separator: "\n") {
            lines.append(String(line))
            if lines.count > 20 { lines.removeFirst() }
        }
    }
    func joined() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

/// Pulls `HH:MM:SS.cc` out of ffmpeg's `time=00:01:23.45` progress line.
private func parseFFmpegTime(_ text: String) -> Double? {
    guard let range = text.range(of: #"time=(\d+):(\d+):(\d+\.\d+)"#, options: .regularExpression) else { return nil }
    let match = text[range]
    let parts = match.dropFirst(5).split(separator: ":")
    guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
    return h * 3600 + m * 60 + s
}

/// Same synthesis mpv's subtitle push already does — a styleless document
/// needs a minimal Default style or the ASS ffmpeg receives is invalid.
private func withDefaultStyleIfNeeded(_ doc: SubtitleDocument) -> SubtitleDocument {
    guard doc.styles?.isEmpty ?? true else { return doc }
    var d = doc
    d.styles = [AssStyle(name: "Default")]
    return d
}
