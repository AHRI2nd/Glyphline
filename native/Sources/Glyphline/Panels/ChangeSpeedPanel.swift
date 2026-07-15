// Multiply all timestamps by a ratio (ported from ../../../src/components/Modals/ChangeSpeedModal.tsx).

import SwiftUI
import GlyphlineCore

struct ChangeSpeedPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var factorStr = "1.0"
    @State private var invalid = false

    private static let presets: [(String, Double)] = [
        ("23.976 → 25", 23.976 / 25),
        ("25 → 23.976", 25 / 23.976),
        ("24 → 25", 24.0 / 25),
        ("25 → 24", 25.0 / 24),
    ]

    var body: some View {
        PanelShell(title: t("changeSpeed"), width: 380) {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("changeSpeedHint"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Self.presets, id: \.0) { label, factor in
                        Button(label) { apply(factor) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Text(t("customFactor")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                    TextField("", text: $factorStr)
                        .font(GlyphFont.data(12))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("×").foregroundStyle(GlyphColor.quiet)
                    Spacer()
                    Button(t("apply")) { apply(Double(factorStr) ?? -1) }
                        .buttonStyle(.borderedProminent)
                        .tint(GlyphColor.accent)
                }
                if invalid {
                    Text(t("changeSpeedInvalid")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.warn)
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func apply(_ factor: Double) {
        if document.changeSpeed(factor) { dismiss() } else { invalid = true }
    }
}
