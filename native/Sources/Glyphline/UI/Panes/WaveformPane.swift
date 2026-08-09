// Waveform pane: zoom controls + the NSScrollView-hosted waveform. Zoom state
// lives here (SwiftUI) and flows down to WaveformScrollView as a plain value —
// ported from Waveform.tsx's zoom slider/⌘-scroll/±buttons.

import SwiftUI
import GlyphlineCore

struct WaveformPane: View {
    let document: DocumentModel
    let media: MediaModel
    let settings: AppSettings
    var onOpenMedia: () -> Void
    // 0–100, log scale (see WaveformScrollView). Lives in AppSettings so it
    // survives relaunch rather than resetting to the default each session.
    private var zoomLevel: Double { settings.waveformZoom }

    var body: some View {
        if media.mediaPath == nil {
            // Same empty-media wording and action as the video pane — both
            // panes are blocked on the same missing thing, so they should read
            // as the same state, not two different messages for one cause.
            PanePlaceholder(
                icon: "waveform", title: t("noMediaShort"), subtitle: t("noMediaDesc"),
                actions: [PlaceholderAction(label: t("openMedia"), prominent: true, action: onOpenMedia)]
            )
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    sceneCutControl
                    Divider().frame(height: 12)
                    spectrogramToggle
                    Spacer()
                    Button("−") { zoomBy(0.8) }.buttonStyle(.plain)
                        .help(t("zoomOut")).accessibilityLabel(t("zoomOut"))
                    Slider(value: Binding(get: { settings.waveformZoom }, set: { settings.waveformZoom = $0 }), in: 0...100).frame(width: 100).tint(GlyphColor.accentHover)
                    Button("＋") { zoomBy(1.25) }.buttonStyle(.plain)
                        .help(t("zoomIn")).accessibilityLabel(t("zoomIn"))
                }
                .font(GlyphFont.data(11))
                .foregroundStyle(GlyphColor.quiet)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Status sits over the waveform rather than replacing it: on a
                // media change the previous waveform stays visible while the new
                // one extracts, which reads as "working" instead of "broken".
                ZStack {
                    WaveformScrollView(
                        document: document,
                        media: media,
                        zoomLevel: zoomLevel,
                        frameRate: settings.frameMode
                            ? settings.effectiveFrameRate(detected: media.detectedFrameRate)
                            : nil,
                        showSpectrogram: settings.showSpectrogram,
                        onZoomWheel: { delta in
                            settings.waveformZoom = min(100, max(0, zoomLevel + delta))
                        }
                    )
                    waveformStatusOverlay
                }
            }
        }
    }

    @ViewBuilder
    private var waveformStatusOverlay: some View {
        switch media.waveformStatus {
        case .extracting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(t("waveformExtracting"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(GlyphColor.surface.opacity(0.92), in: Capsule())
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(GlyphColor.amber)
                Text(message).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(GlyphColor.surface.opacity(0.92), in: Capsule())
        case .idle, .ready:
            EmptyView()
        }
    }

    /// Runs the whole-file decode to find cuts (or shows how it went) — not
    /// automatic, since detection cost scales with runtime and this pane
    /// otherwise has zero waiting for anything but the audio downsample.
    @ViewBuilder
    private var sceneCutControl: some View {
        switch media.sceneCutStatus {
        case .idle:
            Button(t("detectSceneCuts")) { media.detectSceneCuts() }
                .buttonStyle(.plain)
                .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                .disabled(!SceneCutExtractor.ffmpegAvailable)
                .help(SceneCutExtractor.ffmpegAvailable ? "" : t("ffmpegMissing"))
        case .detecting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small).scaleEffect(0.6)
                Text(t("detectingSceneCuts")).font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
            }
        case .ready:
            Button(t("sceneCutCount", "\(media.sceneCuts.count)")) { media.detectSceneCuts() }
                .buttonStyle(.plain)
                .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.signal)
                .help(t("redetectSceneCuts"))
        case .failed(let message):
            Button(message) { media.detectSceneCuts() }
                .buttonStyle(.plain)
                .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.amber)
        }
    }

    private var spectrogramToggle: some View {
        Button {
            settings.showSpectrogram.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform.and.magnifyingglass")
                Text(t("spectrogram"))
            }
        }
        .buttonStyle(.plain)
        .font(GlyphFont.data(11))
        .foregroundStyle(settings.showSpectrogram ? GlyphColor.signal : GlyphColor.quiet)
        .help(t("spectrogramHint"))
    }

    private func zoomBy(_ factor: Double) {
        let px = WaveformScrollView.zoomLevelToPixels(zoomLevel) * factor
        // Invert zoomLevelToPixels (px = 10 · 50^(level/100)) to solve for level.
        settings.waveformZoom = min(100, max(0, 100 * log(px / 10) / log(50)))
    }
}
