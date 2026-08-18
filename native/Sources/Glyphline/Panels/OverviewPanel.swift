// Whole-document overview: a density strip for the whole file, the gaps in it,
// and who speaks.
//
// The grid shows about thirty cues at a time, so the SHAPE of a two-hour file
// was invisible — a ten-minute stretch with no subtitles looks exactly like
// normal scrolling until you happen to pass through it. The strip makes that
// one glance, and clicking anywhere seeks there.

import SwiftUI
import GlyphlineCore

struct OverviewPanel: View {
    let document: DocumentModel
    let media: MediaModel

    private var overview: DocumentOverview {
        let idx = document.activeTranslationLanguageIndex
        let languages = document.doc.translationLanguages ?? []
        return buildOverview(document.doc, duration: media.duration > 0 ? media.duration : nil) {
            $0.translationText(at: idx, languages: languages)
        }
    }

    /// Only shown once a project has named languages — a single-translation
    /// document's progress figure needs no qualifier (index 0 has no name).
    private var activeLanguageLabel: String? {
        let idx = document.activeTranslationLanguageIndex
        guard idx > 0, let languages = document.doc.translationLanguages, languages.indices.contains(idx) else {
            return nil
        }
        return languages[idx].uppercased()
    }

    var body: some View {
        PanelShell(title: t("overview"), width: 520) {
            let data = overview
            VStack(alignment: .leading, spacing: 12) {
                if data.totalCues == 0 {
                    Text(t("noCues")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    summary(data)
                    DensityStrip(data: data, playhead: media.mediaPath != nil ? media.currentTime : nil) { time in
                        media.seek(time)
                    }
                    gapsSection(data)
                    Divider()
                    actorsSection
                }
            }
        } footer: {
            Spacer()
            PanelCloseButton()
        }
    }

    @ViewBuilder
    private func summary(_ data: DocumentOverview) -> some View {
        HStack(spacing: 14) {
            stat(t("statCueCount"), "\(data.totalCues)")
            stat(t("statSpan"), formatDisplayTime(data.span))
            if let progress = data.translationProgress {
                let label = activeLanguageLabel.map { "\(t("translation")) (\($0))" } ?? t("translation")
                stat(label, "\(Int(progress * 100))%")
            }
            Spacer()
        }
        .font(GlyphFont.data(11))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(GlyphColor.quiet)
            Text(value).foregroundStyle(GlyphColor.ink)
        }
    }

    @ViewBuilder
    private func gapsSection(_ data: DocumentOverview) -> some View {
        if data.gaps.isEmpty {
            Text(t("overviewNoGaps")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("overviewGaps", "\(data.gaps.count)"))
                    .font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                ForEach(data.gaps.prefix(20)) { gap in
                    Button {
                        if media.mediaPath != nil { media.seek(gap.start) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(formatDisplayTime(gap.start))
                                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.amber)
                            Text("→").font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                            Text(formatDisplayTime(gap.end))
                                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                            Text(String(format: "%.0f\(t("secondsSuffix"))", gap.duration))
                                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var actorsSection: some View {
        let actors = actorSummaries(document.doc)
        VStack(alignment: .leading, spacing: 3) {
            Text(t("actorList")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            if actors.isEmpty {
                Text(t("actorListEmpty")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            } else {
                // Near-identical names sit next to each other here on purpose —
                // that adjacency is what makes a typo'd speaker name obvious.
                Text(t("actorListHint")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                ForEach(actors) { actor in
                    Button {
                        document.setActiveCue(actor.firstCueId)
                        if media.mediaPath != nil { media.seek(actor.firstStart) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(actor.name).font(GlyphFont.body(12)).lineLimit(1)
                            Spacer()
                            Text(t("actorLineCount", "\(actor.lineCount)"))
                                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One bar per slice: height is cue density, colour marks translated coverage.
private struct DensityStrip: View {
    let data: DocumentOverview
    let playhead: Double?
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let maxCount = max(1, data.buckets.map(\.cueCount).max() ?? 1)
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(GlyphColor.bg)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(data.buckets.enumerated()), id: \.offset) { _, bucket in
                        Rectangle()
                            .fill(color(for: bucket))
                            // A slice with any cue at all keeps a visible floor,
                            // so "sparse" never renders as "empty".
                            .frame(height: bucket.cueCount == 0
                                   ? 0
                                   : max(3, 56 * CGFloat(bucket.cueCount) / CGFloat(maxCount)))
                            .frame(maxWidth: .infinity)
                    }
                }

                if let playhead, data.span > 0 {
                    Rectangle()
                        .fill(GlyphColor.signalLight)
                        .frame(width: GlyphMetric.spineWidth, height: 56)
                        .offset(x: CGFloat(playhead / data.span) * geo.size.width)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard data.span > 0, geo.size.width > 0 else { return }
                onSeek(Double(location.x / geo.size.width) * data.span)
            }
        }
        .frame(height: 56)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(GlyphColor.border, lineWidth: 0.5))
    }

    /// Amber where covered text is untranslated — only once the document uses
    /// translations at all, so a monolingual file isn't painted as "unfinished".
    private func color(for bucket: OverviewBucket) -> Color {
        guard data.translationProgress != nil else { return GlyphColor.accent }
        return bucket.translatedShare > 0.99 ? GlyphColor.accent
             : bucket.translatedShare > 0 ? GlyphColor.accentHover
             : GlyphColor.amber
    }
}
