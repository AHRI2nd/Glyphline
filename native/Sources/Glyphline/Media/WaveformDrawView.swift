// Renders the waveform via Core Graphics (peaks per pixel column, like
// wavesurfer.js's approach) plus cue region overlays and the playhead line.
// Click seeks; wave=indigo-500, playhead=indigo-300 (wavesurfer's wave/progress
// two-tone), matching the original Tauri build's palette.

import AppKit
import GlyphlineCore

final class WaveformDrawView: NSView {
    var audio: WaveformAudio? { didSet { needsDisplay = true } }
    var pxPerSec: CGFloat = 71 { didSet { needsDisplay = true } }
    var cues: [Cue] = [] { didSet { needsDisplay = true } }
    var activeCueId: String? { didSet { needsDisplay = true } }
    var currentTime: Double = 0 { didSet { needsDisplay = true } }

    var onSeek: ((Double) -> Void)?
    /// Cmd/Ctrl+scroll → zoom (delta: +4 per notch in, −4 out). Plain scroll
    /// falls through to `super` for normal horizontal panning inside the
    /// enclosing NSScrollView.
    var onZoomWheel: ((Double) -> Void)?

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onSeek?(max(0, Double(p.x / pxPerSec)))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        onZoomWheel?(event.deltaY > 0 ? 4 : -4)
    }

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
        for cue in cues {
            let x0 = CGFloat(cue.start) * pxPerSec
            let x1 = CGFloat(cue.end) * pxPerSec
            let rect = CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: bounds.height)
            let active = cue.id == activeCueId
            ctx.setFillColor(NSColor(GlyphColor.signal).withAlphaComponent(active ? 0.16 : 0.07).cgColor)
            ctx.fill(rect)
            if active {
                ctx.setStrokeColor(NSColor(GlyphColor.signal).withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }
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
