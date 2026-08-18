// House-style find/replace rules — persisted across files and sessions (see
// AppSettings.customRules), applied as one batch with one undo entry. The
// fixed TidyRule set (Subtitle ▸ 일괄 정리…) covers universal typography;
// this is where a translator's or client's OWN rules go.

import SwiftUI
import GlyphlineCore

struct CustomRulesPanel: View {
    let document: DocumentModel
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var lastAppliedCount: Int?

    var body: some View {
        PanelShell(title: t("customRules"), width: 480) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("customRulesHint"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)

                if settings.customRules.isEmpty {
                    Text(t("customRulesEmpty"))
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ForEach(Array(settings.customRules.enumerated()), id: \.element.id) { i, rule in
                        RuleRow(
                            rule: Binding(
                                get: { settings.customRules[i] },
                                set: { settings.customRules[i] = $0 }
                            ),
                            onDelete: { settings.customRules.remove(at: i) }
                        )
                        Divider()
                    }
                }

                Button(t("customRulesAdd")) {
                    settings.customRules.append(CustomRule(name: t("customRulesNewName"), pattern: "", replacement: ""))
                }
                .controlSize(.small)

                if let lastAppliedCount {
                    Text(t("customRulesApplied", "\(lastAppliedCount)"))
                        .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.good)
                }
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("customRulesApply")) {
                lastAppliedCount = document.applyCustomRules(settings.customRules)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(GlyphColor.accent)
            .disabled(!settings.customRules.contains { $0.enabled && !$0.pattern.isEmpty })
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: CustomRule
    let onDelete: () -> Void

    private var patternValid: Bool { rule.pattern.isEmpty || isValidRulePattern(rule.pattern) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                TextField(t("customRulesName"), text: $rule.name)
                    .textFieldStyle(.plain).font(GlyphFont.body(12))
                Spacer()
                Toggle(t("customRulesCaseInsensitive"), isOn: $rule.caseInsensitive)
                    .toggleStyle(.checkbox).font(GlyphFont.body(10))
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain).foregroundStyle(GlyphColor.quiet)
            }
            HStack(spacing: 6) {
                TextField(t("customRulesPattern"), text: $rule.pattern)
                    .font(GlyphFont.data(11)).textFieldStyle(.roundedBorder)
                Text("→").foregroundStyle(GlyphColor.quiet)
                TextField(t("customRulesReplacement"), text: $rule.replacement)
                    .font(GlyphFont.data(11)).textFieldStyle(.roundedBorder)
            }
            if !patternValid {
                Text(t("customRulesInvalidPattern"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.amber)
            }
        }
        .padding(.vertical, 4)
    }
}
