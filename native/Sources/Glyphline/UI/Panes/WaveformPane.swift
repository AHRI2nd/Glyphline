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

                WaveformScrollView(
                    document: document, media: media, zoomLevel: zoomLevel,
                    onZoomWheel: { delta in settings.waveformZoom = min(100, max(0, zoomLevel + delta)) }
                )
            }
        }
    }

    private func zoomBy(_ factor: Double) {
        let px = WaveformScrollView.zoomLevelToPixels(zoomLevel) * factor
        // Invert zoomLevelToPixels (px = 10 · 50^(level/100)) to solve for level.
        settings.waveformZoom = min(100, max(0, 100 * log(px / 10) / log(50)))
    }
}
