// One-stop batch cleanup (ported from ../../../src/components/Modals/BatchCleanupModal.tsx).
// Every row's action is a DocumentModel method already covered by unit tests
// (M1) — this panel is purely UI plumbing.

import SwiftUI
import GlyphlineCore

struct BatchCleanupPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var results: [String: Int] = [:]
    @State private var gapMs = "80"
    @State private var minDur = String(DEFAULT_THRESHOLDS.minDuration)
    @State private var maxDur = String(DEFAULT_THRESHOLDS.maxDuration)
    @State private var caseMode: CaseMode = .sentence
    @State private var caseScope: EditScope = .all

    var body: some View {
        PanelShell(title: t("batchCleanup"), width: 480) {
            VStack(alignment: .leading, spacing: 14) {
                row(t("fixOverlaps"), key: "overlaps") { document.fixOverlaps() }

                row(t("minGap"), key: "gap") {
                    document.applyMinGap(max(0, (Double(gapMs) ?? 0)) / 1000)
                } accessory: {
                    NumberField(label: "", value: $gapMs, suffix: "ms")
                }

                row(t("durationLimits"), key: "durations") {
                    let lo = max(0, Double(minDur) ?? 0)
                    let hi = max(lo, Double(maxDur) ?? lo)
                    return document.applyDurationLimits(minSec: lo, maxSec: hi)
                } accessory: {
                    HStack(spacing: 4) {
                        NumberField(label: "", value: $minDur, suffix: t("secondsSuffix"), width: 48)
                        Text("–").foregroundStyle(GlyphColor.quiet)
                        NumberField(label: "", value: $maxDur, suffix: t("secondsSuffix"), width: 48)
                    }
                }

                row(t("removeEmptyCues"), key: "empty") { document.removeEmptyCues() }

                row(t("changeCase"), key: "casing") {
                    document.changeCase(mode: caseMode, scope: caseScope)
                } accessory: {
                    HStack(spacing: 6) {
                        Picker("", selection: $caseMode) {
                            Text(t("caseSentence")).tag(CaseMode.sentence)
                            Text(t("caseTitle")).tag(CaseMode.title)
                            Text(t("caseUpper")).tag(CaseMode.upper)
                            Text(t("caseLower")).tag(CaseMode.lower)
                        }.frame(width: 90).labelsHidden()
                        Picker("", selection: $caseScope) {
                            Text(t("scopeAll")).tag(EditScope.all)
                            Text(t("scopeSelected")).tag(EditScope.selected)
                        }.frame(width: 70).labelsHidden()
                    }
                }

                row(t("removeHearingImpaired"), key: "hi", hint: t("removeHearingImpairedHint")) {
                    document.removeHearingImpaired()
                }

                row(t("mergeSameText"), key: "sameText", hint: t("mergeSameTextHint")) {
                    document.mergeSameText()
                }

                row(t("mergeSameTimecodes"), key: "sameTime") { document.mergeSameTimecodes() }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func row(
        _ label: String, key: String, hint: String? = nil,
        action: @escaping () -> Int,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(GlyphFont.body(12))
                if let hint {
                    Text(hint).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                }
            }
            Spacer()
            accessory()
            if let n = results[key] {
                Text("✓ \(n)")
                    .font(GlyphFont.data(11))
                    .foregroundStyle(n > 0 ? GlyphColor.good : GlyphColor.quiet)
            }
            Button(t("apply")) { results[key] = action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
