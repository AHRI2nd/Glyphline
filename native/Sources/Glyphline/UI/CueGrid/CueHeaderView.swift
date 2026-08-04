// Restyles the grid's own NSTableHeaderView so it reads as one continuous
// surface with PaneChrome's header bar above it, instead of a separate
// stock-AppKit control glued on top of the app's custom chrome — the same
// surface color, the same quiet/tracked label treatment used everywhere else
// a section label appears in this app.

import AppKit

final class CueHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(GlyphColor.surface).setFill()
        bounds.fill()
        super.draw(dirtyRect)
        NSColor(GlyphColor.border).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

final class CueHeaderCell: NSTableHeaderCell {
    override var cellSize: NSSize {
        var size = super.cellSize
        size.height = 28
        return size
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !stringValue.isEmpty else { return }
        let attributed = NSAttributedString(string: stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(GlyphColor.quiet),
            .kern: 0.4,
        ])
        let size = attributed.size()
        let y = cellFrame.midY - size.height / 2
        let x: CGFloat
        switch alignment {
        case .right: x = cellFrame.maxX - size.width - 8
        case .center: x = cellFrame.midX - size.width / 2
        default: x = cellFrame.minX + 8
        }
        attributed.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
    }
}
