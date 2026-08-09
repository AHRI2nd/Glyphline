// Word/syllable timing for the active cue.
//
// The document model and the ASS/VTT adapters have carried `tokens` losslessly
// since M1, but nothing could create or adjust them — this is that editor.
//
// The interaction is a timeline of adjacent blocks whose widths are the
// syllable durations, with draggable boundaries between them. Boundaries
// rather than free-floating blocks because \k encodes DURATIONS with no way to
// express a gap: letting a user open one would produce a file that silently
// renders differently from what they laid out.

import SwiftUI
import GlyphlineCore

struct KaraokeTimingPanel: View {
    let document: DocumentModel
    let media: MediaModel
    @Environment(\.dismiss) private var dismiss

    private var cue: Cue? {
        guard let id = document.activeCueId else { return nil }
        return document.doc.cues.first { $0.id == id }
    }

    var body: some View {
        PanelShell(title: t("karaokeTiming"), width: 620) {
            VStack(alignment: .leading, spacing: 14) {
                if let cue {
                    header(cue)
                    Divider()
                    if let tokens = cue.tokens, !tokens.isEmpty {
                        TokenTimeline(
                            cue: cue,
                            tokens: tokens,
                            playhead: media.mediaPath != nil ? media.currentTime : nil,
                            onBeginDrag: { document.beginInteractive() },
                            onDrag: { index, time in
                                document.moveTokenBoundary(for: cue.id, index: index, to: time)
                            },
                            onEndDrag: { document.endInteractive() }
                        )
                        tokenList(cue, tokens)
                    } else {
                        Text(t("karaokeNoTokens"))
                            .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                } else {
                    Text(t("noActiveCueShort"))
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                Text(t("karaokeHint"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            PanelCloseButton()
        }
    }

    @ViewBuilder
    private func header(_ cue: Cue) -> some View {
        HStack {
            Text(cue.text.replacingOccurrences(of: "\n", with: " "))
                .font(GlyphFont.body(12)).lineLimit(1)
            Spacer()
            Button(cue.tokens == nil ? t("karaokeGenerate") : t("karaokeRegenerate")) {
                document.generateTokens(for: cue.id)
            }
            .controlSize(.small)
            if cue.tokens != nil {
                Button(t("karaokeClear")) { document.clearTokens(for: cue.id) }
                    .controlSize(.small)
            }
        }
    }

    /// Numeric read-out under the timeline — the timeline is for shaping,
    /// this is for checking the exact value you shaped.
    private func tokenList(_ cue: Cue, _ tokens: [SyncToken]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, token in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(GlyphFont.data(10))
                        .foregroundStyle(GlyphColor.quiet).frame(width: 22, alignment: .trailing)
                    Text(token.text).font(GlyphFont.body(12))
                        .frame(width: 90, alignment: .leading)
                    Text(formatDisplayTime(token.start)).font(GlyphFont.data(10))
                        .foregroundStyle(GlyphColor.quiet)
                    Text("–").font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                    Text(formatDisplayTime(token.end)).font(GlyphFont.data(10))
                        .foregroundStyle(GlyphColor.quiet)
                    Spacer()
                    Text(String(format: "%.0f ms", (token.end - token.start) * 1000))
                        .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.signal)
                }
            }
        }
    }
}

/// Adjacent blocks sized by duration, with draggable boundaries between them.
private struct TokenTimeline: View {
    let cue: Cue
    let tokens: [SyncToken]
    let playhead: Double?
    let onBeginDrag: () -> Void
    let onDrag: (Int, Double) -> Void
    let onEndDrag: () -> Void

    @State private var dragging: Int?

    private var span: Double { max(0.001, cue.end - cue.start) }
    private func x(_ time: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((time - cue.start) / span) * width
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { i, token in
                    let left = x(token.start, geo.size.width)
                    let width = max(1, x(token.end, geo.size.width) - left)
                    Text(token.text)
                        .font(GlyphFont.body(11))
                        .foregroundStyle(GlyphColor.ink)
                        .frame(width: width, height: 44)
                        .background(
                            GlyphColor.accent.opacity(i % 2 == 0 ? 0.22 : 0.14),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .clipped()
                        .offset(x: left)
                }

                // Boundaries sit ON TOP of the blocks so the grab target isn't
                // covered by whichever block was drawn last.
                ForEach(Array(tokens.dropLast().enumerated()), id: \.offset) { i, token in
                    Rectangle()
                        .fill(dragging == i ? GlyphColor.signalLight : GlyphColor.signal)
                        .frame(width: dragging == i ? 3 : 1.5, height: 44)
                        .offset(x: x(token.end, geo.size.width) - 1)
                        .contentShape(Rectangle().size(width: 12, height: 44))
                        .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragging != i { dragging = i; onBeginDrag() }
                                    let time = cue.start + Double(value.location.x / geo.size.width) * span
                                    onDrag(i, time)
                                }
                                .onEnded { _ in dragging = nil; onEndDrag() }
                        )
                }

                if let playhead, playhead >= cue.start, playhead <= cue.end {
                    Rectangle()
                        .fill(GlyphColor.signalLight)
                        .frame(width: GlyphMetric.spineWidth, height: 44)
                        .offset(x: x(playhead, geo.size.width))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 44)
    }
}
