// Subtitle↔video pairing for the delivery pipeline's folder-scan input mode
// (see DeliveryManifest.swift for the rest of that pipeline's core types).
// Pure and platform-agnostic like the rest of GlyphlineCore — the actual
// media-extension set lives in the app target (MediaModel.swift's
// MEDIA_EXTS), so it's passed in rather than imported.

import Foundation

public struct SubtitleVideoPair: Equatable, Sendable {
    public var subtitlePath: String
    /// nil when no same-directory, same-basename media file was found.
    public var videoPath: String?

    public init(subtitlePath: String, videoPath: String? = nil) {
        self.subtitlePath = subtitlePath
        self.videoPath = videoPath
    }
}

/// Pairs every subtitle file with a same-directory, same-basename file from
/// `candidatePaths` whose extension is in `mediaExts`.
///
/// If more than one candidate extension matches the same basename (both
/// `.mp4` and `.mkv` present, say), the alphabetically-first extension wins —
/// deterministic and easy to reason about, rather than a "smartest guess"
/// heuristic that would be hard to predict or explain.
public func pairSubtitlesWithVideos(
    subtitlePaths: [String],
    candidatePaths: [String],
    mediaExts: Set<String>
) -> [SubtitleVideoPair] {
    // Group candidates by (directory, basename) once — O(n) — rather than
    // rescanning candidatePaths per subtitle file.
    var byKey: [String: [String]] = [:]
    for path in candidatePaths {
        let ns = path as NSString
        let ext = ns.pathExtension.lowercased()
        guard mediaExts.contains(ext) else { continue }
        let dir = ns.deletingLastPathComponent
        let base = (ns.lastPathComponent as NSString).deletingPathExtension
        byKey["\(dir)/\(base)", default: []].append(path)
    }

    return subtitlePaths.map { subtitlePath in
        let ns = subtitlePath as NSString
        let dir = ns.deletingLastPathComponent
        let base = (ns.lastPathComponent as NSString).deletingPathExtension
        let matches = byKey["\(dir)/\(base)"]?.sorted() ?? []
        return SubtitleVideoPair(subtitlePath: subtitlePath, videoPath: matches.first)
    }
}
