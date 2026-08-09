// Export part of the document — the selected cues, or a time range.
//
// The plain File ▸ Export path stays a one-click whole-file export; this is the
// separate entry for the cases that used to require making a throwaway copy of
// the file and deleting everything you didn't want.

import SwiftUI
import GlyphlineCore

struct ExportRangePanel: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Scope: String, CaseIterable { case selected, timeRange }

    @State private var scope: Scope = .selected
    @State private var format: SubFormat = .srt
    @State private var startText = "0"
    @State private var endText = "0"
    @State private var rebase = false

    private var selectedCount: Int { state.document.selectedIds.count }

    /// Resolved scope, or nil when the inputs can't produce an export.
    private var resolved: ExportScope? {
        switch scope {
        case .selected:
            return selectedCount > 0 ? .selected(state.document.selectedIds) : nil
        case .timeRange:
            guard let s = parseTimestampInput(startText), let e = parseTimestampInput(endText), s != e else { return nil }
            return .timeRange(start: s, end: e)
        }
    }

    private var matchCount: Int {
        guard let resolved else { return 0 }
        return subsetDocument(state.document.doc, scope: resolved).cues.count
    }

    var body: some View {
        PanelShell(title: t("exportRange"), width: 400) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $scope) {
                    Text(t("scopeSelected")).tag(Scope.selected)
                    Text(t("scopeTimeRange")).tag(Scope.timeRange)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch scope {
                case .selected:
                    Text(selectedCount > 0 ? t("scopeSelectedCount", "\(selectedCount)") : t("scopeSelectedNone"))
                        .font(GlyphFont.body(11))
                        .foregroundStyle(selectedCount > 0 ? GlyphColor.quiet : GlyphColor.amber)
                case .timeRange:
                    HStack(spacing: 8) {
                        timeField(t("from"), text: $startText)
                        timeField(t("to"), text: $endText)
                        Button(t("useCurrentTime")) {
                            endText = formatDisplayTime(state.media.currentTime)
                        }
                        .controlSize(.small)
                        .disabled(state.media.mediaPath == nil)
                    }
                    Text(t("scopeTimeRangeHint"))
                        .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                }

                Divider()

                HStack {
                    Text(t("exportAs")).font(GlyphFont.body(12))
                    Spacer()
                    Picker("", selection: $format) {
                        ForEach(SubFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue.uppercased()).tag(fmt)
                        }
                    }
                    .labelsHidden().frame(width: 120)
                }
                Toggle(t("rebaseToZero"), isOn: $rebase)
                    .toggleStyle(.checkbox).font(GlyphFont.body(12))
                Text(t("rebaseToZeroHint"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

                Text(t("exportRangeMatch", "\(matchCount)"))
                    .font(GlyphFont.data(11))
                    .foregroundStyle(matchCount > 0 ? GlyphColor.signal : GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("export")) {
                guard let resolved else { return }
                dismiss()
                state.performExport(format: format, source: .text, encodingLabel: nil,
                                    scope: resolved, rebaseToZero: rebase)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(GlyphColor.accent)
            .disabled(matchCount == 0)
        }
    }

    private func timeField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            TextField("", text: text)
                .font(GlyphFont.data(12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        }
    }
}
