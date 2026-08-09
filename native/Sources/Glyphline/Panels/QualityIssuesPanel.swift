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
    let media: MediaModel
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
            let q = evaluateCue(cue, prev: i > 0 ? sorted[i - 1] : nil,
                               thresholds: settings.quality, sceneCuts: media.sceneCuts)
            return hasAnyIssue(q) ? Issue(cue: cue, index: i + 1, q: q) : nil
        }
    }

    // Decoding+parsing every embedded font's binary data isn't cheap (a
    // multi-MB CJK font is real work), and this panel is a DOCKED pane, not
    // a modal sheet — it can sit open right next to the grid while the user
    // types. A computed property here would redo that work on every single
    // keystroke, since it reads `document.doc` and ANY cue edit changes that.
    // Caching keyed on `doc.fonts` (which only changes when fonts are
    // embedded/removed, not on ordinary cue editing) decouples the two.
    @State private var fontIssues: [FontCoverageIssue] = []

    var body: some View {
        PanelShell(title: t("qualityIssues"), width: 420) {
            VStack(alignment: .leading, spacing: 0) {
                if !fontIssues.isEmpty {
                    fontCoverageSection
                    Divider().padding(.vertical, 6)
                }
                if issues.isEmpty {
                    Text(t("qualityIssuesNone"))
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
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
            Menu(t("qcReportExport")) {
                Button(t("qcReportExportCSV")) { exportReport(html: false) }
                Button(t("qcReportExportHTML")) { exportReport(html: true) }
            }
            .fixedSize()
            Spacer()
            PanelCloseButton()
        }
        .onAppear { fontIssues = checkFontCoverage(document.doc) }
        // Fires on a real font embed/removal AND on a tab switch (loadParsed
        // swaps the whole doc, fonts included) — never on plain cue editing,
        // which is the whole point.
        .onChange(of: document.doc.fonts) { _, _ in fontIssues = checkFontCoverage(document.doc) }
    }

    private func exportReport(html: Bool) {
        let panel = NSSavePanel()
        let base = (document.fileName ?? "subtitle").replacingOccurrences(of: ".\(document.doc.format.rawValue)", with: "")
        panel.nameFieldStringValue = "\(base)_qc.\(html ? "html" : "csv")"
        panel.allowedContentTypes = [html ? .html : .commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = html
            ? generateQCReportHTML(document.doc, thresholds: settings.quality, sceneCuts: media.sceneCuts,
                                   fontIssues: fontIssues, title: document.fileName ?? "QC Report")
            : generateQCReportCSV(document.doc, thresholds: settings.quality, sceneCuts: media.sceneCuts)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Document-level, not per-cue — the embedded font either covers a
    /// character everywhere in the file or it doesn't, so this sits above the
    /// per-cue list rather than trying to force it into one row per cue.
    @ViewBuilder
    private var fontCoverageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("fontCoverage")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            ForEach(Array(fontIssues.enumerated()), id: \.offset) { _, issue in
                if let missing = issue.missingCharacters {
                    Text(t("fontCoverageMissing", issue.fontName, String(missing.prefix(20))))
                        .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.amber)
                } else {
                    Text(t("fontCoverageUnparseable", issue.fontName))
                        .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                }
            }
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
            (t("crossesCut"), q.crossesCut, GlyphColor.warn),
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
