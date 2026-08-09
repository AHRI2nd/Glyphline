// Broadcast safe-area guides drawn over the video.
//
// Deliverables for TV get letterboxed, overscanned and re-framed downstream, so
// text placed too close to an edge can end up cropped on someone's set. The
// industry answer is two nested boxes (SMPTE RP 218): everything essential
// inside the TITLE-safe box, everything you'd rather not lose inside the
// ACTION-safe box. Checking that by eye needs the boxes ON the picture.
//
// They're drawn as ASS `\p` vector shapes appended to the copy of the document
// that goes to mpv — NOT as a view layered over the video. The video surface is
// an OpenGL view that flushes straight to the window's backing store, so a
// sibling overlay would tear; libass composites into the frame itself and gets
// the video's own scaling and letterboxing for free.

/// SMPTE RP 218 for HD: 93% action-safe, 90% title-safe, both centred.
public let ACTION_SAFE_FRACTION = 0.93
public let TITLE_SAFE_FRACTION = 0.90

/// The style name the guides render with. Prefixed so it can't collide with a
/// style the user actually authored.
public let SAFE_GUIDE_STYLE = "__glyphline_safe"

/// libass's assumed script resolution when the script declares none.
private let DEFAULT_PLAY_RES = (x: 384.0, y: 288.0)

/// Reads PlayResX/PlayResY out of the preserved `[Script Info]` block. Guides
/// are drawn in script coordinates, so getting this wrong would put the boxes
/// in the wrong place rather than merely mis-sized.
public func scriptResolution(of doc: SubtitleDocument) -> (x: Double, y: Double) {
    guard let info = doc.meta["assScriptInfo"] else { return DEFAULT_PLAY_RES }
    func value(_ key: String) -> Double? {
        for line in info.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == key.lowercased()
            else { continue }
            return Double(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
    let x = value("PlayResX") ?? DEFAULT_PLAY_RES.x
    let y = value("PlayResY") ?? DEFAULT_PLAY_RES.y
    guard x > 0, y > 0 else { return DEFAULT_PLAY_RES }
    return (x, y)
}

/// A single rectangle outline as an ASS drawing command, in script coordinates.
func safeBoxDrawing(fraction: Double, width: Double, height: Double) -> String {
    let insetX = (width * (1 - fraction) / 2).rounded()
    let insetY = (height * (1 - fraction) / 2).rounded()
    let x1 = Int(insetX), y1 = Int(insetY)
    let x2 = Int(width - insetX), y2 = Int(height - insetY)
    return "m \(x1) \(y1) l \(x2) \(y1) \(x2) \(y2) \(x1) \(y2)"
}

/// Returns a copy of `doc` with two full-length guide cues (and their style)
/// appended. Purely additive and never persisted — the caller hands the result
/// straight to the player.
public func withSafeAreaGuides(_ doc: SubtitleDocument, duration: Double) -> SubtitleDocument {
    var out = doc
    let res = scriptResolution(of: doc)
    // Alignment 7 + \pos(0,0) puts the drawing origin at the top-left of the
    // script rectangle, which is the coordinate space the boxes are computed in.
    // Outline-only: the fill is made fully transparent (\1a&HFF&) so the boxes
    // never obscure the picture they exist to let you judge.
    out.styles = (out.styles ?? []) + [AssStyle(
        name: SAFE_GUIDE_STYLE,
        primaryColour: "&HFF000000",
        outlineColour: "&H002EA2F0",   // BBGGRR of the app's signal amber
        outline: 2, shadow: 0, alignment: 7,
        marginL: 0, marginR: 0, marginV: 0
    )]

    // 24h rather than the media duration: the duration isn't known until mpv
    // has read the file, and a guide that quietly stops halfway through would
    // be worse than none.
    let end = max(duration, 86_400)
    func guideCue(_ id: String, fraction: Double, colour: String) -> Cue {
        let shape = safeBoxDrawing(fraction: fraction, width: res.x, height: res.y)
        return Cue(
            id: id, start: 0, end: end,
            text: "{\\an7\\pos(0,0)\\bord2\\shad0\\1a&HFF&\\3c\(colour)\\p1}\(shape)",
            style: SAFE_GUIDE_STYLE, layer: 100
        )
    }
    out.cues.append(guideCue("__safe_action", fraction: ACTION_SAFE_FRACTION, colour: "&H2EA2F0&"))
    out.cues.append(guideCue("__safe_title", fraction: TITLE_SAFE_FRACTION, colour: "&H8E8E8A&"))
    return out
}
