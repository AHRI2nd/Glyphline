// Exporting part of a document.
//
// Full-file export is the common case, but two partial cases come up often
// enough that doing them by hand (duplicate the file, delete everything else,
// export, throw the copy away) is a real cost: sending a reviewer the twenty
// lines you're unsure about, and cutting a reel or an episode segment out of a
// long timeline.
//
// Cues are selected by OVERLAP, not containment, and are never clipped: a cue
// that straddles the boundary is subtitle text that is on screen during the
// range, and silently shortening it would change the deliverable. Including it
// whole is the choice that can't corrupt anything.

public enum ExportScope: Equatable, Sendable {
    case all
    case selected(Set<String>)
    case timeRange(start: Double, end: Double)
}

/// Narrows `doc` to `scope`, optionally shifting the result so the first cue
/// starts at zero — what you want when the excerpt will be laid against a clip
/// that itself starts at zero, and what you must NOT do when it goes back
/// against the original timeline.
public func subsetDocument(
    _ doc: SubtitleDocument,
    scope: ExportScope,
    rebaseToZero: Bool = false
) -> SubtitleDocument {
    var out = doc
    switch scope {
    case .all:
        break
    case .selected(let ids):
        out.cues = doc.cues.filter { ids.contains($0.id) }
    case .timeRange(let start, let end):
        let lo = min(start, end)
        let hi = max(start, end)
        out.cues = doc.cues.filter { $0.end > lo && $0.start < hi }
    }
    guard rebaseToZero, let first = out.cues.map(\.start).min(), first != 0 else { return out }
    out.cues = out.cues.map { cue in
        var c = cue
        c.start -= first
        c.end -= first
        if let tokens = c.tokens {
            c.tokens = tokens.map { SyncToken(text: $0.text, start: $0.start - first, end: $0.end - first, confidence: $0.confidence) }
        }
        return c
    }
    return out
}
