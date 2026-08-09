// One-stop batch cleanup (ported from ../../../src/components/Modals/BatchCleanupModal.tsx).
// Every row's action is a DocumentModel method already covered by unit tests
// (M1) — this panel is purely UI plumbing.

import SwiftUI
import GlyphlineCore

struct BatchCleanupPanel: View {
    let document: DocumentModel
    /// Line rebreaking reuses the SAME limits the quality check flags against,
    /// so "fix" and "complain" can never disagree about what too long means.
    let settings: AppSettings
    /// Only needed for the scene-cut snap row, which reads media.sceneCuts.
    let media: MediaModel
    @Environment(\.dismiss) private var dismiss

    @State private var results: [String: Int] = [:]
    @State private var gapMs = "80"
    @State private var minDur = String(DEFAULT_THRESHOLDS.minDuration)
    @State private var maxDur = String(DEFAULT_THRESHOLDS.maxDuration)
    @State private var caseMode: CaseMode = .sentence
    @State private var caseScope: EditScope = .all
    @State private var breakStyle: LineBreakStyle = .auto
    // Off by default: each rule rewrites text, so the user opts in to exactly
    // the ones they want rather than discovering a sweeping change afterwards.
    @State private var tidyRules: Set<TidyRule> = []
    @State private var leadInMs = "0"
    @State private var leadOutMs = "0"
    @State private var bridgeGapMs = "300"
    @State private var cutSnapMs = "80"

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

                row(t("autoBreakLines"), key: "autoBreak", hint: t("autoBreakLinesHint")) {
                    document.rebreakLines(
                        maxLineLength: settings.quality.maxLineLength,
                        maxLines: settings.quality.maxLines,
                        style: breakStyle
                    )
                } accessory: {
                    Picker("", selection: $breakStyle) {
                        Text(t("breakStyleAuto")).tag(LineBreakStyle.auto)
                        Text(t("breakStyleSpaced")).tag(LineBreakStyle.spaced)
                        Text(t("breakStyleCJK")).tag(LineBreakStyle.cjk)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                row(t("unbreakLines"), key: "unbreak", hint: t("unbreakLinesHint")) {
                    document.unbreakAllLines()
                }

                row(t("removeHearingImpaired"), key: "hi", hint: t("removeHearingImpairedHint")) {
                    document.removeHearingImpaired()
                }

                row(t("mergeSameText"), key: "sameText", hint: t("mergeSameTextHint")) {
                    document.mergeSameText()
                }

                row(t("mergeSameTimecodes"), key: "sameTime") { document.mergeSameTimecodes() }

                Divider()
                Text(t("timingPostProcess")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)

                row(t("leadInOut"), key: "leadInOut", hint: t("leadInOutHint")) {
                    document.applyLeadInOut(
                        leadInSec: max(0, (Double(leadInMs) ?? 0)) / 1000,
                        leadOutSec: max(0, (Double(leadOutMs) ?? 0)) / 1000
                    )
                } accessory: {
                    HStack(spacing: 4) {
                        NumberField(label: "", value: $leadInMs, suffix: "ms", width: 48)
                        Text("/").foregroundStyle(GlyphColor.quiet)
                        NumberField(label: "", value: $leadOutMs, suffix: "ms", width: 48)
                    }
                }

                row(t("bridgeSmallGaps"), key: "bridge", hint: t("bridgeSmallGapsHint")) {
                    document.bridgeSmallGaps(maxGapSec: max(0, (Double(bridgeGapMs) ?? 0)) / 1000)
                } accessory: {
                    NumberField(label: "", value: $bridgeGapMs, suffix: "ms")
                }

                row(t("snapToSceneCuts"), key: "cutSnap",
                    hint: media.sceneCuts.isEmpty ? t("snapToSceneCutsNeedsDetect") : nil) {
                    document.snapToSceneCuts(media.sceneCuts, toleranceSec: max(0, (Double(cutSnapMs) ?? 0)) / 1000)
                } accessory: {
                    NumberField(label: "", value: $cutSnapMs, suffix: "ms")
                }
                .disabled(media.sceneCuts.isEmpty)

                Divider()
                tidySection
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    /// The typography rules. Grouped under one Apply because they're normally
    /// run together as a single "clean this file up" pass, and each one on its
    /// own undo step would make backing out a cleanup tedious.
    @ViewBuilder
    private var tidySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("tidyText")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                Spacer()
                if let n = results["tidy"] {
                    Text(t("qualityIssuesCount", "\(n)"))
                        .font(GlyphFont.data(11))
                        .foregroundStyle(n > 0 ? GlyphColor.good : GlyphColor.quiet)
                }
                Button(t("apply")) { results["tidy"] = document.tidyText(rules: Array(tidyRules)) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(tidyRules.isEmpty)
            }
            ForEach(TidyRule.allCases, id: \.self) { rule in
                Toggle(t(rule.labelKey), isOn: Binding(
                    get: { tidyRules.contains(rule) },
                    set: { on in if on { tidyRules.insert(rule) } else { tidyRules.remove(rule) } }
                ))
                .toggleStyle(.checkbox).font(GlyphFont.body(12))
            }
        }
    }

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


extension TidyRule {
    /// Localised name. Kept here rather than in GlyphlineCore so the core stays
    /// free of any presentation concern.
    var labelKey: String {
        switch self {
        case .spacing: return "tidySpacing"
        case .spaceAfterPunctuation: return "tidySpaceAfterPunct"
        case .dialogueDashes: return "tidyDashes"
        case .ocrCapitalI: return "tidyOcrI"
        case .ellipsis: return "tidyEllipsis"
        }
    }
}
