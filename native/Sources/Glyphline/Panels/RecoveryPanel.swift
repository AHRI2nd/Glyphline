// Offered at startup when a crash-recovery autosave exists (ported from
// ../../../src/components/Modals/SafetyModals.tsx's RecoveryModal).

import SwiftUI

struct RecoveryPanel: View {
    let data: AutosaveData
    let onRestore: () -> Void
    let onDiscard: () -> Void

    private var when: String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: data.savedAt)
    }

    var body: some View {
        PanelShell(title: t("recoveryTitle"), width: 380) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("recoveryMessage"))
                    .font(GlyphFont.body(12))
                Text("\(data.fileName ?? t("recoveryUntitled")) · \(when)")
                    .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("recoveryDiscard")) { onDiscard() }
            Button(t("recoveryRestore")) { onRestore() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
    }
}
