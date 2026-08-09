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
    /// Non-nil when edits should land on frame boundaries (View ▸ 프레임 타임코드).
    var frameRate: Double?
    var showSpectrogram: Bool = false
    var onZoomWheel: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let drawView = WaveformDrawView(frame: .zero)
        drawView.onSeek = { [weak media] t in media?.seek(t) }
        drawView.onZoomWheel = onZoomWheel

        // Direct timing editing on the waveform. Each drag is bracketed by
        // begin/endInteractive so the whole gesture collapses into one undo
        // entry while still mutating per frame (the grid and the video's
        // subtitle overlay follow the drag live).
        let doc = document
        drawView.onBeginEdit = { doc.beginInteractive() }
        drawView.onEndEdit = { doc.endInteractive() }
        drawView.onSelectCue = { id in doc.setActiveCue(id) }
        // Snapping lives at the drag's exit point rather than inside
        // WaveformDrawView so the view keeps tracking the pointer smoothly —
        // only the value committed to the document is quantized.
        drawView.onAdjustCue = { [weak coordinator = context.coordinator] id, start, end in
            let (s, e) = coordinator?.snappedBounds(start: start, end: end) ?? (start, end)
            doc.updateCue(id) { $0.start = s; $0.end = e }
        }
        drawView.onCreateCue = { [weak coordinator = context.coordinator] start, end in
            let (s, e) = coordinator?.snappedBounds(start: start, end: end) ?? (start, end)
            doc.addCueAt(start: s, end: e)
            return doc.activeCueId // addCueAt makes the new cue active
        }

        let scroll = NSScrollView()
        scroll.documentView = drawView
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        context.coordinator.drawView = drawView
        context.coordinator.scrollView = scroll
        if let path = media.mediaPath { context.coordinator.loadAudio(path: path, media: media) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let drawView = coordinator.drawView else { return }
        drawView.onZoomWheel = onZoomWheel
        coordinator.frameRate = frameRate

        if media.mediaPath != coordinator.lastPath {
            coordinator.lastPath = media.mediaPath
            if let path = media.mediaPath { coordinator.loadAudio(path: path, media: media) }
            else { drawView.audio = nil }
        }

        drawView.showSpectrogram = showSpectrogram
        if showSpectrogram { coordinator.ensureSpectrogram() }
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
        drawView.sceneCuts = media.sceneCuts
        coordinator.sceneCuts = media.sceneCuts

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
        /// Read by the drag callbacks above; kept on the coordinator so they
        /// see the live value instead of the one captured at makeNSView time.
        var frameRate: Double?
        var sceneCuts: [Double] = []
        weak var scrollView: NSScrollView?
        var lastPath: String?
        var lastAudio: WaveformAudio?
        private var loadTask: Task<Void, Never>?

        func loadAudio(path: String, media: MediaModel) {
            loadTask?.cancel()
            media.waveformStatus = .extracting
            loadTask = Task { [weak self, weak media] in
                guard let self else { return }
                do {
                    let wavURL = try await WaveformExtractor.extract(path: path)
                    guard !Task.isCancelled else { return }
                    let audio = try WaveformAudio.load(wavURL)
                    guard !Task.isCancelled else { return }
                    self.lastAudio = audio
                    self.drawView?.audio = audio
                    self.drawView?.spectrogramImage = nil // stale for the new file; ensureSpectrogram rebuilds on demand
                    media?.waveformAudio = audio
                    media?.waveformStatus = .ready
                } catch {
                    guard !Task.isCancelled else { return }
                    NSLog("[waveform] extraction/decode failed: \(error)")
                    // Surfaced in the pane rather than only the log — see
                    // MediaModel.WaveformStatus.
                    media?.waveformStatus = .failed(
                        (error as? WaveformExtractor.ExtractError) == .mpvNotFound
                            ? t("mpvMissing") : t("waveformFailed"))
                }
            }
        }

        /// A cut, if one is close enough, wins outright over frame snapping —
        /// see snapToNearestCut. Tolerance is 3 frames when the rate is known,
        /// else a flat 100ms (roughly a third of a second of dead reckoning on
        /// an un-timed document, generous enough to catch a deliberate drag
        /// toward the line without grabbing an unrelated nearby cut).
        func snappedBounds(start: Double, end: Double) -> (Double, Double) {
            let tolerance = frameRate.map { 3 / $0 } ?? 0.1
            let s = snapToNearestCut(start, cuts: sceneCuts, within: tolerance)
            let e = snapToNearestCut(end, cuts: sceneCuts, within: tolerance)
            return frameRate.map { snapCueBounds(start: s, end: e, fps: $0) } ?? (s, e)
        }

        /// Lazily renders the spectrogram bitmap for the current audio the
        /// first time spectrogram mode is turned on (or a new file loads) —
        /// the FFT pass takes real time for a long file, so it isn't run
        /// unless the user actually asked to see it.
        private var spectrogramTask: Task<Void, Never>?
        func ensureSpectrogram() {
            guard drawView?.spectrogramImage == nil, spectrogramTask == nil, let audio = lastAudio else { return }
            spectrogramTask = Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) { SpectrogramRenderer.render(audio) }.value
                guard let self, !Task.isCancelled else { return }
                self.drawView?.spectrogramImage = image
                self.spectrogramTask = nil
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
