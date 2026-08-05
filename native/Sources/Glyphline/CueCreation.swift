// Where a newly created cue lands.
//
// This is the ONE place that decides, because there are three ways to make a
// cue — ⌘Return, the transport's "Cue here" button, and double-clicking the
// empty area under the grid — and they had drifted into two different answers.
// ⌘Return appended after the last cue regardless of where the video was, so
// adding cues while watching produced a stack of them at the end of the file
// two seconds apart instead of at the moments they belong to.
//
// The playhead is the right default: you add a subtitle because you just heard
// the line. Appending after the last cue is only the fallback for when there's
// no media open and therefore no time to take.

import Foundation
import GlyphlineCore

/// Default on-screen duration for a fresh cue. The start is what matters — the
/// end gets trimmed by the O key, a waveform drag, or the next cue's start
/// almost immediately.
let NEW_CUE_DURATION: Double = 2

@MainActor
func addCueAtPlayhead(document: DocumentModel, media: MediaModel, frameRate: Double?) {
    guard media.mediaPath != nil else {
        // No media: nothing better to anchor to than the end of the document.
        document.addCue()
        return
    }
    let start = media.currentTime
    let end = media.duration > 0
        ? min(start + NEW_CUE_DURATION, media.duration)
        : start + NEW_CUE_DURATION
    let bounds = frameRate.map { snapCueBounds(start: start, end: end, fps: $0) }
        ?? (start: start, end: end)
    document.addCueAt(start: bounds.start, end: bounds.end)
}
