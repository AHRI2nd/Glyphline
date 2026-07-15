// Aggregate list of quality-flagged cues (ported from
// ../../../src/components/Plugins/QualityPanel.tsx). Docked in Tauri; shipped
// here as a modal panel like the rest of M5/M6 since native's fixed 3-pane
// layout doesn't yet have a flexlayout-equivalent dock (see plan's Risk
// section — arbitrary docking is a stretch goal, not required for parity).
// Clicking a row makes that cue active; the sheet stays open so several rows
// can be triaged in one visit.

import SwiftUI
import GlyphlineCore

struct QualityIssuesPanel: View {
    let document: DocumentModel
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private struct Issue: Identifiable {
        let cue: Cue
        let index: Int
        let q: CueQuality
        var id: String { cue.id }
    }

    private var issues: [Issue] {
        let sorted = sortedCues(document.doc.cues)
        return sorted.enumerated().compactMap { i, cue in
            let q = evaluateCue(cue, prev: i > 0 ? sorted[i - 1] : nil, thresholds: settings.quality)
            return hasAnyIssue(q) ? Issue(cue: cue, index: i + 1, q: q) : nil
        }
    }

    var body: some View {
        PanelShell(title: t("qualityIssues"), width: 420) {
            if issues.isEmpty {
                Text(t("qualityIssuesNone"))
                    .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(t("qualityIssuesCount", "\(issues.count)"))
                        .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                        .padding(.bottom, 6)
                    ForEach(issues) { issue in
                        IssueRow(issue: issue.cue, index: issue.index, q: issue.q) {
                            document.setActiveCue(issue.cue.id)
                        }
                        Divider()
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }
}

private struct IssueRow: View {
    let issue: Cue
    let index: Int
    let q: CueQuality
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(index)").font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                    Text(issue.text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "—")
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.ink)
                        .lineLimit(1)
                }
                badges
                Text("\(formatDisplayTime(issue.start)) → \(formatDisplayTime(issue.end))")
                    .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badges: some View {
        // Overlap/negative-duration are hard errors (rose); everything else is a
        // soft warning (amber) — matches QualityPanel.tsx's red/amber split.
        let items: [(String, Bool, Color)] = [
            (t("overlap"), q.overlapsPrev, GlyphColor.warn),
            ("\(t("cpsHigh")) (\(String(format: "%.0f", cps(issue))))", q.cpsTooHigh, GlyphColor.amber),
            ("\(t("tooShort")) (\(String(format: "%.2f", cueDuration(issue)))s)", q.durationTooShort, GlyphColor.amber),
            ("\(t("tooLong")) (\(String(format: "%.2f", cueDuration(issue)))s)", q.durationTooLong, GlyphColor.amber),
            (t("lineTooLong"), q.lineTooLong, GlyphColor.amber),
            (t("tooManyLines"), q.tooManyLines, GlyphColor.amber),
            (t("negativeDuration"), q.negativeDuration, GlyphColor.warn),
        ]
        let active = items.filter { $0.1 }
        if !active.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(active.enumerated()), id: \.offset) { _, item in
                    Text(item.0)
                        .font(GlyphFont.data(9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(item.2.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(item.2)
                }
            }
        }
    }
}
