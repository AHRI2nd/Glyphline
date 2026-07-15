// Shift every timestamp by a fixed offset (ported from App.tsx's ShiftModal).

import SwiftUI
import GlyphlineCore

struct ShiftTimePanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var seconds = "0"

    private var hasSelection: Bool { !document.selectedIds.isEmpty }

    var body: some View {
        PanelShell(title: t("shiftTime"), width: 360) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("shiftPrompt")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                TextField("", text: $seconds)
                    .font(GlyphFont.data(13))
                    .textFieldStyle(.roundedBorder)
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            if hasSelection {
                Button(t("shiftSelected")) { apply(.selected) }
            }
            Button(t("shiftAll")) { apply(.all) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
    }

    private func apply(_ scope: EditScope) {
        if let delta = Double(seconds), delta != 0 {
            document.shiftTime(deltaSec: delta, scope: scope)
        }
        dismiss()
    }
}
