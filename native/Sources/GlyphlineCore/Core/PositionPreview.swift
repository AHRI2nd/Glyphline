// Live preview of a `\pos(x,y)` override while editing it.
//
// A drag-to-position tool on the video itself was considered and set aside
// (see the mpv architecture notes in CLAUDE.md): the video surface is an
// opaque child NSWindow floating over the SwiftUI content specifically so it
// can repaint outside SwiftUI's own draw cycle, which means a SwiftUI overlay
// drawn "on top of" it would either be hidden behind it or fight it for
// z-order — the same reason the broadcast safe-area guides are burned into
// the frame via ASS rather than drawn as a sibling view. This does the same
// thing: a small crosshair, expressed as an ASS `\p` vector drawing at the
// exact coordinate being edited, pushed to mpv alongside the real subtitles
// so the user sees where text will land without closing the editor to check.

import Foundation

public let POSITION_PREVIEW_STYLE = "__glyphline_pos_preview"

/// A temporary marker cue: a small crosshair at (x, y) in script coordinates,
/// spanning the full timeline so it's visible regardless of playhead
/// position while the editor is open. Purely additive, like
/// withSafeAreaGuides — never persisted, built fresh each time the position
/// field changes and handed straight to the player.
public func positionPreviewCue(x: Double, y: Double, radius: Double = 14) -> Cue {
    let shape = "m \(Int(x - radius)) \(Int(y)) l \(Int(x)) \(Int(y - radius)) \(Int(x + radius)) \(Int(y)) "
        + "\(Int(x)) \(Int(y + radius)) \(Int(x - radius)) \(Int(y)) "
        + "m \(Int(x - radius)) \(Int(y)) l \(Int(x + radius)) \(Int(y)) "
        + "m \(Int(x)) \(Int(y - radius)) l \(Int(x)) \(Int(y + radius))"
    return Cue(
        id: "__pos_preview", start: 0, end: 86_400,
        text: "{\\an7\\pos(0,0)\\bord2\\shad0\\1a&H40&\\3c&H2EA2F0&\\p1}\(shape)",
        style: POSITION_PREVIEW_STYLE, layer: 200
    )
}

/// Returns a copy of `doc` with the preview crosshair appended, mirroring
/// withSafeAreaGuides' additive shape.
public func withPositionPreview(_ doc: SubtitleDocument, x: Double, y: Double) -> SubtitleDocument {
    var out = doc
    out.styles = (out.styles ?? []) + [AssStyle(
        name: POSITION_PREVIEW_STYLE,
        primaryColour: "&HFF000000", outlineColour: "&H002EA2F0",
        outline: 2, shadow: 0, alignment: 7, marginL: 0, marginR: 0, marginV: 0
    )]
    out.cues.append(positionPreviewCue(x: x, y: y))
    return out
}
