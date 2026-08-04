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

final class CueRowView: NSTableRowView {
    var isActiveCue: Bool = false {
        didSet { if isActiveCue != oldValue { needsDisplay = true } }
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
            NSColor(GlyphColor.signalLight).setFill()
            NSRect(x: 0, y: 0, width: GlyphMetric.spineWidth, height: bounds.height).fill()
        }
    }
}
