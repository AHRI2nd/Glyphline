// NSScrollView hosting WaveformDrawView, with the playhead kept centered by
// direct scroll-offset manipulation (ported from Waveform.tsx's centerOnCursor,
// which did the same thing via `scrollLeft` — AppKit's NSClipView.scroll(to:) is
// the exact native equivalent). Centering only applies while media is actually
// advancing (i.e. playing); when paused the user can freely scroll/drag,
// matching the original's behavior of only re-centering on `currentTime` change.

import AppKit
import SwiftUI
import GlyphlineCore

struct WaveformScrollView: NSViewRepresentable {
    let document: DocumentModel
    let media: MediaModel
    let zoomLevel: Double // 0–100, log scale (see WaveformPane)
    var onZoomWheel: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let drawView = WaveformDrawView(frame: .zero)
        drawView.onSeek = { [weak media] t in media?.seek(t) }
        drawView.onZoomWheel = onZoomWheel

        let scroll = NSScrollView()
        scroll.documentView = drawView
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        context.coordinator.drawView = drawView
        context.coordinator.scrollView = scroll
        if let path = media.mediaPath { context.coordinator.loadAudio(path: path) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let drawView = coordinator.drawView else { return }
        drawView.onZoomWheel = onZoomWheel

        if media.mediaPath != coordinator.lastPath {
            coordinator.lastPath = media.mediaPath
            if let path = media.mediaPath { coordinator.loadAudio(path: path) }
            else { drawView.audio = nil }
        }

        let pxPerSec = CGFloat(Self.zoomLevelToPixels(zoomLevel))
        drawView.pxPerSec = pxPerSec
        let duration = max(media.duration, coordinator.lastAudio?.duration ?? 0)
        let width = max(nsView.bounds.width, CGFloat(duration) * pxPerSec)
        if drawView.frame.width != width || drawView.frame.height != nsView.bounds.height {
            drawView.frame = CGRect(x: 0, y: 0, width: width, height: max(1, nsView.bounds.height))
        }

        drawView.cues = sortedCues(document.doc.cues)
        drawView.activeCueId = document.activeCueId
        drawView.currentTime = media.currentTime

        // Only recenter while actually playing — paused lets the user scroll freely.
        if media.isPlaying {
            coordinator.centerOnCursor(time: media.currentTime, pxPerSec: pxPerSec, scrollView: nsView)
        }
    }

    /// Log-scale zoom: level 0 → 10 px/s, level 50 → ~71 px/s (default),
    /// level 100 → 500 px/s. Ported from Waveform.tsx's zoomLevelToPixels.
    static func zoomLevelToPixels(_ level: Double) -> Double {
        10 * pow(50, level / 100)
    }

    @MainActor
    final class Coordinator {
        weak var drawView: WaveformDrawView?
        weak var scrollView: NSScrollView?
        var lastPath: String?
        var lastAudio: WaveformAudio?
        private var loadTask: Task<Void, Never>?

        func loadAudio(path: String) {
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let wavURL = try await WaveformExtractor.extract(path: path)
                    guard !Task.isCancelled else { return }
                    let audio = try WaveformAudio.load(wavURL)
                    guard !Task.isCancelled else { return }
                    self.lastAudio = audio
                    self.drawView?.audio = audio
                } catch {
                    NSLog("[waveform] extraction/decode failed: \(error)")
                }
            }
        }

        /// Scroll so the playhead sits at the panel center; clamps at the
        /// start/end so the cursor visibly moves toward the edge there instead.
        func centerOnCursor(time: Double, pxPerSec: CGFloat, scrollView: NSScrollView) {
            let clip = scrollView.contentView
            let cursorX = CGFloat(time) * pxPerSec
            let visibleWidth = clip.bounds.width
            let maxX = max(0, (drawView?.frame.width ?? 0) - visibleWidth)
            let targetX = max(0, min(cursorX - visibleWidth / 2, maxX))
            guard abs(clip.bounds.origin.x - targetX) > 0.5 else { return }
            clip.scroll(to: NSPoint(x: targetX, y: 0))
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
