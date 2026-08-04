// Keyboard shortcuts reference (ported from ../../../src/components/Modals/HelpModal.tsx).

import SwiftUI

struct HelpPanel: View {
    @Environment(\.dismiss) private var dismiss

    private var rows: [(String, String)] {
        [
            ("⌘Z", t("scUndo")), ("⌘⇧Z", t("scRedo")),
            ("⌘N", t("scNew")), ("⌘⇧O", t("scOpenMedia")),
            ("⌘F", t("scFind")), ("⌘Return", t("addCue")),
            ("↑ ↓", t("scNavCues")),
            ("I", t("scTimingIn")),
            ("O", t("scTimingOut")),
            ("P", t("scTimingChain")),
            ("Space", t("playPause")),
            ("← →", t("scNudgeCue")),
            ("⌥← ⌥→", t("scNudgeStart")),
            ("⌥⇧← ⌥⇧→", t("scNudgeEnd")),
        ]
    }

    var body: some View {
        PanelShell(title: t("shortcuts"), width: 340) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(rows, id: \.1) { key, desc in
                    GridRow {
                        // Keycap style per CLAUDE.md: rounded border-zinc-600 bg-zinc-800 font-mono.
                        Text(key)
                            .font(GlyphFont.data(11, weight: .semibold))
                            .foregroundStyle(GlyphColor.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(GlyphColor.border, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x52525b), lineWidth: 0.5))
                        Text(desc).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.ink)
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }
}
