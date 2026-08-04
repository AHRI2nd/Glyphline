// Renders the waveform via Core Graphics (peaks per pixel column, like
// wavesurfer.js's approach) plus cue region overlays and the playhead line,
// and hosts direct cue timing editing — the waveform is the surface where
// timing work actually happens, so regions are draggable here:
//
//   • drag a region EDGE          → adjust that boundary
//   • drag a region BODY          → slide the whole cue, duration preserved
//   • drag EMPTY space            → create a cue spanning the drag
//   • click                       → seek (and select, when on a region)
//
// Every gesture is one undo entry (DocumentModel.beginInteractive), while the
// document still mutates on each frame so the cue grid and the video overlay
// track the drag live.
//
// wave=indigo-500, playhead=indigo-300 (wavesurfer's wave/progress two-tone),
// matching the original Tauri build's palette.

import AppKit
import SwiftUI
import GlyphlineCore

final class WaveformDrawView: NSView {
    var audio: WaveformAudio? { didSet { needsDisplay = true } }
    var pxPerSec: CGFloat = 71 { didSet { needsDisplay = true } }
    var cues: [Cue] = [] {
        didSet {
            overlapSlots = overlapColorSlots(for: cues, paletteSize: GlyphColor.overlapPalette.count)
            needsDisplay = true
        }
    }
    var activeCueId: String? { didSet { needsDisplay = true } }
    var currentTime: Double = 0 { didSet { needsDisplay = true } }
    /// cue id → overlapPalette index, for cues that overlap another cue —
    /// recomputed whenever `cues` changes (see overlapColorSlots).
    private var overlapSlots: [String: Int] = [:]

    var onSeek: ((Double) -> Void)?
    /// Cmd/Ctrl+scroll → zoom (delta: +4 per notch in, −4 out). Plain scroll
    /// falls through to `super` for normal horizontal panning inside the
    /// enclosing NSScrollView.
    var onZoomWheel: ((Double) -> Void)?

    /// Brackets one drag gesture so it lands as a single undo entry.
    var onBeginEdit: (() -> Void)?
    var onEndEdit: (() -> Void)?
    /// Sets a cue's timing outright (already clamped to be non-inverting).
    var onAdjustCue: ((_ id: String, _ start: Double, _ end: Double) -> Void)?
    /// Creates a cue and returns its id, so the drag can keep resizing it.
    var onCreateCue: ((_ start: Double, _ end: Double) -> String?)?
    var onSelectCue: ((_ id: String) -> Void)?

    override var isFlipped: Bool { true }

    /// Cue boundaries are 1px lines; this is the forgiving grab band around
    /// them. Matches the resize-cursor zone so what you can grab is what the
    /// cursor says you can grab.
    private let edgeGrabPx: CGFloat = 5
    /// Shortest cue a drag may produce — prevents zero/negative durations.
    private let minDuration: Double = 0.05
    /// A press must travel this far before it counts as a drag rather than a
    /// click, so clicking empty space seeks instead of creating a stray cue.
    private let dragThresholdPx: CGFloat = 3

    private enum Grab { case start, end, body }

    private enum DragMode {
        case none
        case resize(id: String, fixedEdge: Double, movingIsStart: Bool)
        case move(id: String, grabOffset: Double, duration: Double)
        /// Empty-space press; upgrades to `.resize` once it passes the threshold.
        case pendingCreate(anchor: Double)
    }

    private var dragMode: DragMode = .none
    private var pressOriginX: CGFloat = 0
    private var hoverGrab: (id: String, grab: Grab)?
    private var trackingAreaRef: NSTrackingArea?

    // ── hit testing ──────────────────────────────────────────────────────────────

    private func time(atX x: CGFloat) -> Double {
        guard pxPerSec > 0 else { return 0 }
        return max(0, Double(x / pxPerSec))
    }

    /// Edges are checked across ALL cues before any body, because an edge can
    /// sit inside a neighbouring cue's body wherever regions abut or overlap —
    /// and the edge is the more specific target the user is aiming at.
    private func hitTest(x: CGFloat) -> (cue: Cue, grab: Grab)? {
        for cue in cues {
            let sx = CGFloat(cue.start) * pxPerSec
            let ex = CGFloat(cue.end) * pxPerSec
            if abs(x - sx) <= edgeGrabPx { return (cue, .start) }
            if abs(x - ex) <= edgeGrabPx { return (cue, .end) }
        }
        let t = time(atX: x)
        if let cue = cues.first(where: { t >= $0.start && t <= $0.end }) { return (cue, .body) }
        return nil
    }

    // ── cursor + hover feedback ──────────────────────────────────────────────────

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard case .none = dragMode else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let hit = hitTest(x: x)
        let next = hit.map { (id: $0.cue.id, grab: $0.grab) }
        if next?.id != hoverGrab?.id || next?.grab != hoverGrab?.grab {
            hoverGrab = next
            needsDisplay = true
        }
        switch hit?.grab {
        case .start, .end: NSCursor.resizeLeftRight.set()
        case .body: NSCursor.openHand.set()
        case nil: NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard case .none = dragMode else { return }
        if hoverGrab != nil { hoverGrab = nil; needsDisplay = true }
        NSCursor.arrow.set()
    }

    // ── drag gestures ────────────────────────────────────────────────────────────

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressOriginX = p.x
        let t = time(atX: p.x)

        guard let (cue, grab) = hitTest(x: p.x) else {
            // Empty space: seek immediately; a drag from here creates a cue.
            dragMode = .pendingCreate(anchor: t)
            onSeek?(t)
            return
        }

        onSelectCue?(cue.id)
        onBeginEdit?()
        switch grab {
        case .start:
            dragMode = .resize(id: cue.id, fixedEdge: cue.end, movingIsStart: true)
        case .end:
            dragMode = .resize(id: cue.id, fixedEdge: cue.start, movingIsStart: false)
        case .body:
            NSCursor.closedHand.set()
            dragMode = .move(id: cue.id, grabOffset: t - cue.start, duration: cue.end - cue.start)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let t = time(atX: p.x)

        switch dragMode {
        case .none:
            break

        case .pendingCreate(let anchor):
            guard abs(p.x - pressOriginX) >= dragThresholdPx else { return }
            // Passed the threshold — materialize the cue, then keep dragging
            // its free edge so the new region tracks the cursor.
            onBeginEdit?()
            let lo = min(anchor, t), hi = max(anchor, t)
            guard let id = onCreateCue?(lo, max(hi, lo + minDuration)) else {
                dragMode = .none
                onEndEdit?()
                return
            }
            dragMode = .resize(id: id, fixedEdge: anchor, movingIsStart: t < anchor)

        case .resize(let id, let fixedEdge, _):
            // Dragging past the anchor flips which edge is moving, so the
            // region keeps following the cursor instead of sticking.
            let movingIsStart = t < fixedEdge
            let lo = min(t, fixedEdge), hi = max(t, fixedEdge)
            let start = lo, end = max(hi, lo + minDuration)
            dragMode = .resize(id: id, fixedEdge: fixedEdge, movingIsStart: movingIsStart)
            onAdjustCue?(id, start, end)

        case .move(let id, let grabOffset, let duration):
            let start = max(0, t - grabOffset)
            onAdjustCue?(id, start, start + duration)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .none, .pendingCreate:
            break // a plain click already seeked; nothing to commit
        case .resize, .move:
            onEndEdit?()
        }
        dragMode = .none
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        onZoomWheel?(event.deltaY > 0 ? 4 : -4)
    }

    // ── drawing ──────────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.fill(dirtyRect)

        drawCueRegions(ctx)
        drawPeaks(ctx, dirtyRect: dirtyRect)
        drawPlayhead(ctx)
    }

    private func drawPeaks(_ ctx: CGContext, dirtyRect: NSRect) {
        guard let audio, !audio.samples.isEmpty, pxPerSec > 0 else { return }
        let midY = bounds.height / 2
        let samplesPerPixel = max(1, audio.sampleRate / Double(pxPerSec))

        ctx.setStrokeColor(NSColor(GlyphColor.accentHover).withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1)

        let startX = max(0, Int(dirtyRect.minX))
        let endX = min(Int(bounds.width) + 1, Int(dirtyRect.maxX) + 1)
        guard startX < endX else { return }

        for x in startX..<endX {
            let sampleStart = Int(Double(x) * samplesPerPixel)
            let sampleEnd = min(audio.samples.count, Int(Double(x + 1) * samplesPerPixel))
            guard sampleStart < sampleEnd, sampleStart < audio.samples.count else { continue }
            var lo: Float = 0, hi: Float = 0
            for s in audio.samples[sampleStart..<sampleEnd] {
                if s < lo { lo = s }
                if s > hi { hi = s }
            }
            let y1 = midY - CGFloat(hi) * midY
            let y2 = midY - CGFloat(lo) * midY
            ctx.move(to: CGPoint(x: CGFloat(x) + 0.5, y: y1))
            ctx.addLine(to: CGPoint(x: CGFloat(x) + 0.5, y: max(y2, y1 + 1)))
        }
        ctx.strokePath()
    }

    private func drawCueRegions(_ ctx: CGContext) {
        let draggingId = draggingCueId
        for (index, cue) in cues.enumerated() {
            let x0 = CGFloat(cue.start) * pxPerSec
            let x1 = CGFloat(cue.end) * pxPerSec
            let rect = CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: bounds.height)
            let active = cue.id == activeCueId
            let hovered = hoverGrab?.id == cue.id
            let dragging = draggingId == cue.id
            // Overlapping cues get a color from the rotating palette instead
            // of the plain accent fill, so two regions covering the same
            // stretch of time no longer look like one indistinguishable blob.
            let overlapTint: Color? = overlapSlots[cue.id].map { GlyphColor.overlapPalette[$0] }
            let baseColor = overlapTint ?? GlyphColor.signal

            let fill: CGFloat = dragging ? 0.28 : (active ? 0.20 : (hovered ? 0.16 : (overlapTint != nil ? 0.14 : 0.07)))
            ctx.setFillColor(NSColor(baseColor).withAlphaComponent(fill).cgColor)
            ctx.fill(rect)

            if active || dragging {
                ctx.setStrokeColor(NSColor(baseColor).withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }

            // Edge handles: always a hairline so boundaries stay readable at a
            // glance, thickened on the edge actually under the cursor.
            for (x, isThisEdge) in [
                (x0, hoverGrab?.id == cue.id && hoverGrab?.grab == .start),
                (x1, hoverGrab?.id == cue.id && hoverGrab?.grab == .end),
            ] {
                let strong = isThisEdge || dragging
                ctx.setStrokeColor(NSColor(GlyphColor.signalLight)
                    .withAlphaComponent(strong ? 0.95 : 0.45).cgColor)
                ctx.setLineWidth(strong ? 3 : 1)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: bounds.height))
                ctx.strokePath()
            }

            drawCueNumber(ctx, index + 1, in: rect, tint: overlapTint)
        }
    }

    /// The cue's 1-based position — the same number shown in the grid's `#`
    /// column — so a region on the waveform and its row in the grid are
    /// identifiable as the same cue without having to match colors alone.
    private func drawCueNumber(_ ctx: CGContext, _ number: Int, in rect: CGRect, tint: Color?) {
        let attributed = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor(GlyphColor.ink),
        ])
        let textSize = attributed.size()
        let hPad: CGFloat = 4, vPad: CGFloat = 2
        let chipSize = CGSize(width: textSize.width + hPad * 2, height: textSize.height + vPad)
        // Too narrow to fit a legible chip at this zoom level — skip rather
        // than draw an illegible smear.
        guard rect.width >= chipSize.width + 4 else { return }
        let chipRect = CGRect(x: rect.minX + 2, y: 2, width: chipSize.width, height: chipSize.height)
        ctx.setFillColor(NSColor(tint ?? GlyphColor.signal).withAlphaComponent(0.9).cgColor)
        ctx.addPath(CGPath(roundedRect: chipRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        attributed.draw(at: CGPoint(x: chipRect.minX + hPad, y: chipRect.minY + vPad / 2))
    }

    private var draggingCueId: String? {
        switch dragMode {
        case .resize(let id, _, _), .move(let id, _, _): return id
        case .none, .pendingCreate: return nil
        }
    }

    private func drawPlayhead(_ ctx: CGContext) {
        let x = CGFloat(currentTime) * pxPerSec
        ctx.setStrokeColor(NSColor(GlyphColor.signalLight).cgColor)
        ctx.setLineWidth(GlyphMetric.spineWidth)
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: bounds.height))
        ctx.strokePath()
    }
}
