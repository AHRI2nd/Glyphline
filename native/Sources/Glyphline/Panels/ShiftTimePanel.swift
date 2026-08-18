// Shift every timestamp by a fixed offset (ported from App.tsx's ShiftModal).

import SwiftUI
import GlyphlineCore

struct ShiftTimePanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var seconds = "0"
    @State private var error: String?

    private var hasSelection: Bool { !document.selectedIds.isEmpty }

    var body: some View {
        PanelShell(title: t("shiftTime"), width: 360) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("shiftPrompt")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                TextField("", text: $seconds)
                    .font(GlyphFont.data(13))
                    .textFieldStyle(.roundedBorder)
                if let error {
                    Text(error).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.warn)
                }
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            if hasSelection {
                // Return defaults to whichever action the selection implies
                // was intended — previously always "Shift All" even with
                // cues selected specifically to shift only them, so the
                // reflexive Enter-to-submit could silently retime the whole
                // document instead of the narrower, likely-intended scope.
                Button(t("shiftSelected")) { apply(.selected) }
                    .keyboardShortcut(.defaultAction)
                Button(t("shiftAll")) { apply(.all) }
                    .buttonStyle(.borderedProminent)
                    .tint(GlyphColor.accent)
            } else {
                Button(t("shiftAll")) { apply(.all) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(GlyphColor.accent)
            }
        }
    }

    private func apply(_ scope: EditScope) {
        guard let delta = Double(seconds) else {
            error = t("shiftInvalidValue")
            return
        }
        guard delta != 0 else { dismiss(); return } // a deliberate no-op, not an error
        document.shiftTime(deltaSec: delta, scope: scope)
        dismiss()
    }
}
