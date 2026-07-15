// Document-wide summary (ported from ../../../src/components/Modals/StatisticsModal.tsx).
// Read-only.

import SwiftUI
import GlyphlineCore

struct StatisticsPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    private struct Stats {
        var count = 0, chars = 0, words = 0, lines = 0, overlaps = 0
        var span = 0.0, shown = 0.0, cpsAvg = 0.0, cpsMax = 0.0
        var durMin = Double.infinity, durMax = 0.0
    }

    private var stats: Stats? {
        let sorted = sortedCues(document.doc.cues)
        guard !sorted.isEmpty else { return nil }
        var s = Stats()
        s.count = sorted.count
        s.span = sorted.last!.end - sorted.first!.start
        for (i, cue) in sorted.enumerated() {
            s.chars += visibleCharCount(cue.text)
            s.words += cue.text.split(whereSeparator: { $0.isWhitespace }).count
            s.lines += cue.text.components(separatedBy: "\n").count
            let d = cueDuration(cue)
            s.shown += d
            s.durMin = min(s.durMin, d)
            s.durMax = max(s.durMax, d)
            let c = cps(cue)
            s.cpsAvg += c
            s.cpsMax = max(s.cpsMax, c)
            if i > 0, sorted[i - 1].end > cue.start { s.overlaps += 1 }
        }
        s.cpsAvg /= Double(sorted.count)
        return s
    }

    var body: some View {
        PanelShell(title: t("statistics"), width: 340) {
            if let s = stats {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row(t("statCueCount"), "\(s.count)")
                    row(t("statSpan"), formatDisplayTime(s.span))
                    row(t("statShownTime"), formatDisplayTime(s.shown))
                    row(t("statChars"), "\(s.chars)")
                    row(t("statWords"), "\(s.words)")
                    row(t("statLines"), "\(s.lines)")
                    row(t("statAvgCps"), String(format: "%.1f", s.cpsAvg))
                    row(t("statMaxCps"), String(format: "%.1f", s.cpsMax))
                    row(t("statDurRange"), "\(String(format: "%.2f", s.durMin))s – \(String(format: "%.2f", s.durMax))s")
                    row(t("statOverlaps"), "\(s.overlaps)")
                }
            } else {
                Text(t("noCues")).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
            Text(value).font(GlyphFont.data(12)).foregroundStyle(GlyphColor.ink).gridColumnAlignment(.trailing)
        }
    }
}
