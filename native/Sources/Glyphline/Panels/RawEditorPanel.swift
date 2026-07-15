// Raw text editor for the current document's serialized form (ported from
// ../../../src/components/Modals/RawEditorModal.tsx). Re-parses on apply,
// replacing the document (one undo step, via DocumentModel.loadFromRaw).

import SwiftUI
import GlyphlineCore

struct RawEditorPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        PanelShell(title: "\(t("rawEdit")) (\(document.doc.format.rawValue.uppercased()))", width: 520) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("rawEditHint"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                TextEditor(text: $text)
                    .font(GlyphFont.data(11))
                    .frame(minHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(GlyphColor.borderStrong, lineWidth: 0.5))
                if let error {
                    Text(error).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.warn)
                }
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("apply")) { apply() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
        .onAppear { text = document.serializeCurrent() }
    }

    private func apply() {
        document.loadFromRaw(text, format: document.doc.format)
        dismiss()
    }
}
