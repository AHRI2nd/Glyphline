// Waveform pane: zoom controls + the NSScrollView-hosted waveform. Zoom state
// lives here (SwiftUI) and flows down to WaveformScrollView as a plain value —
// ported from Waveform.tsx's zoom slider/⌘-scroll/±buttons.

import SwiftUI
import GlyphlineCore

struct WaveformPane: View {
    let document: DocumentModel
    let media: MediaModel
    @State private var zoomLevel: Double = 50 // 0–100, log scale — see WaveformScrollView

    var body: some View {
        if media.mediaPath == nil {
            PanePlaceholder(message: t("noMediaShort"))
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Spacer()
                    Button("−") { zoomBy(0.8) }.buttonStyle(.plain)
                        .help(t("zoomOut")).accessibilityLabel(t("zoomOut"))
                    Slider(value: $zoomLevel, in: 0...100).frame(width: 100).tint(GlyphColor.accentHover)
                    Button("＋") { zoomBy(1.25) }.buttonStyle(.plain)
                        .help(t("zoomIn")).accessibilityLabel(t("zoomIn"))
                }
                .font(GlyphFont.data(11))
                .foregroundStyle(GlyphColor.quiet)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                WaveformScrollView(
                    document: document, media: media, zoomLevel: zoomLevel,
                    onZoomWheel: { delta in zoomLevel = min(100, max(0, zoomLevel + delta)) }
                )
            }
        }
    }

    private func zoomBy(_ factor: Double) {
        let px = WaveformScrollView.zoomLevelToPixels(zoomLevel) * factor
        // Invert zoomLevelToPixels (px = 10 · 50^(level/100)) to solve for level.
        zoomLevel = min(100, max(0, 100 * log(px / 10) / log(50)))
    }
}
