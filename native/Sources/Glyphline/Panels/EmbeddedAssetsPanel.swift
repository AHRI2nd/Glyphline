// Embedded ASS [Fonts]/[Graphics] listing (ported from
// ../../../src/components/Settings/EmbeddedAssetsModal.tsx). Read-only.

import SwiftUI
import GlyphlineCore

struct EmbeddedAssetsPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PanelShell(title: t("embeddedAssets"), width: 380) {
            VStack(alignment: .leading, spacing: 16) {
                section(t("embeddedFonts"), document.doc.fonts ?? [])
                section(t("embeddedGraphics"), document.doc.graphics ?? [])
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func section(_ title: String, _ items: [AssEmbedded]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            if items.isEmpty {
                Text(t("embeddedEmpty")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            } else {
                ForEach(items, id: \.name) { item in
                    HStack {
                        Text(item.name).font(GlyphFont.body(12))
                        Spacer()
                        Text(formatBytes(embeddedByteSize(item.data)))
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                    }
                }
            }
        }
    }

    private func formatBytes(_ n: Int) -> String {
        n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024)
    }
}
