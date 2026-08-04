// Custom row background so the grid participates in the app's own palette
// instead of AppKit's default (system blue selection, adaptive gray rows).
//
// The active-cue spine is the one deliberate signature move here: it reuses
// the exact color and width WaveformDrawView already draws the playhead
// cursor with (GlyphColor.signalLight, GlyphMetric.spineWidth), so the
// "where is 'now'" thread literally continues from the waveform ruler into
// the grid, instead of introducing a new accent that happens to also mean
// "current". Selection (multi-select for bulk edits) and "active" (the row
// tied to the playhead) are different facts about a row — they get visually
// distinct treatment so they're never mistaken for each other.

import AppKit
import SwiftUI

final class CueRowView: NSTableRowView {
    var isActiveCue: Bool = false {
        didSet { if isActiveCue != oldValue { needsDisplay = true } }
    }

    /// Set when this row's cue overlaps another cue in time — a color from
    /// GlyphColor.overlapPalette, matching the same cue's region on the
    /// waveform, so a row and its region can be told apart from their
    /// neighbors and correlated with each other by color. nil for the common
    /// case (no overlap): most rows should never carry this.
    var overlapColor: Color? {
        didSet { needsDisplay = true }
    }

    /// True while the playhead is inside this cue — i.e. this subtitle is on
    /// screen right now. Deliberately separate from selection: playback marks
    /// and scrolls to this row but never steals what the user has selected,
    /// so you can keep editing one cue while the video plays past others.
    var isPlayingCue: Bool = false {
        didSet { if isPlayingCue != oldValue { needsDisplay = true } }
    }

    override var isSelected: Bool {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(GlyphColor.bg).setFill()
        dirtyRect.fill()
    }

    // Suppresses AppKit's own selection highlight (system blue/graphite,
    // dimmed when the window isn't key) — selected/active states are painted
    // in draw(_:) below instead, in the app's own palette, unconditionally.
    override func drawSelection(in dirtyRect: NSRect) {}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            NSColor(GlyphColor.accent).withAlphaComponent(0.16).setFill()
            bounds.fill()
        }
        if isActiveCue {
            NSColor(GlyphColor.accent).withAlphaComponent(0.08).setFill()
            bounds.fill()
        }
        // One left stripe, whose COLOR says which fact is true, so the playing
        // row and the row you're editing never fight over the same edge.
        // signalLight is the waveform playhead's own color, which is what makes
        // "now" one continuous thread from the waveform into the grid; the
        // active cue falls back to the flatter accent when it isn't also the
        // one on screen.
        if isPlayingCue || isActiveCue {
            NSColor(isPlayingCue ? GlyphColor.signalLight : GlyphColor.accent).setFill()
            NSRect(x: 0, y: 0, width: GlyphMetric.spineWidth, height: bounds.height).fill()
        }
        // Mirrors the active-cue spine but on the right edge, in the
        // overlap palette instead of signalLight — "left spine = now,
        // right spine = clashes with another cue" reads as two distinct
        // facts rather than competing for the same stripe.
        if let overlapColor {
            NSColor(overlapColor).setFill()
            NSRect(x: bounds.width - GlyphMetric.spineWidth, y: 0, width: GlyphMetric.spineWidth, height: bounds.height).fill()
        }
    }
}
