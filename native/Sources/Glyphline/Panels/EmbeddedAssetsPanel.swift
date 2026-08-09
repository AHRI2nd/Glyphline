// Embedded ASS [Fonts]/[Graphics] listing (ported from
// ../../../src/components/Settings/EmbeddedAssetsModal.tsx). Read-only,
// except for the font collector (task N): finds every font this script's
// styles/tags reference but don't already embed, resolves it on the system
// via CoreText, and embeds it — the reverse of what this panel used to only
// display.

import SwiftUI
import GlyphlineCore

struct EmbeddedAssetsPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var collectResult: (added: Int, notFound: [String])?

    private var missingCount: Int { missingEmbeddedFonts(document.doc).count }

    var body: some View {
        PanelShell(title: t("embeddedAssets"), width: 380) {
            VStack(alignment: .leading, spacing: 16) {
                fontsSection
                section(t("embeddedGraphics"), document.doc.graphics ?? [])
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var fontsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("embeddedFonts")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                Spacer()
                if missingCount > 0 {
                    Button(t("fontCollectorRun", "\(missingCount)")) { collect() }.controlSize(.small)
                }
            }
            if (document.doc.fonts ?? []).isEmpty {
                Text(t("embeddedEmpty")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            } else {
                ForEach(document.doc.fonts ?? [], id: \.name) { item in
                    HStack {
                        Text(item.name).font(GlyphFont.body(12))
                        Spacer()
                        Text(formatBytes(embeddedByteSize(item.data)))
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                    }
                }
            }
            if let collectResult {
                VStack(alignment: .leading, spacing: 2) {
                    if collectResult.added > 0 {
                        Text(t("fontCollectorAdded", "\(collectResult.added)"))
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.good)
                    }
                    if !collectResult.notFound.isEmpty {
                        Text(t("fontCollectorNotFound", collectResult.notFound.joined(separator: ", ")))
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.amber)
                    }
                }
            }
        }
    }

    private func collect() {
        let result = FontCollector.collect(for: document.doc)
        document.addEmbeddedFonts(result.embedded)
        collectResult = (result.embedded.count, result.notFound)
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
