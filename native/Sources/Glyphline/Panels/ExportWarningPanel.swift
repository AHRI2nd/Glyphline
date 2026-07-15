// Warns before a lossy ASS→SMI export (ported from
// ../../../src/components/Modals/ExportWarningModal.tsx).

import SwiftUI
import GlyphlineCore

struct ExportWarningPanel: View {
    let pending: PendingExport
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private func label(_ c: LossCategory) -> String {
        switch c {
        case .position: return t("lossPosition")
        case .karaoke: return t("lossKaraoke")
        case .animation: return t("lossAnimation")
        case .transform: return t("lossTransform")
        case .borderShadow: return t("lossBorderShadow")
        case .drawing: return t("lossDrawing")
        case .clip: return t("lossClip")
        case .color: return t("lossColor")
        case .other: return t("lossOther")
        }
    }

    var body: some View {
        PanelShell(title: t("exportLossTitle"), width: 380) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("exportLossDesc"))
                    .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.ink)
                ForEach(pending.categories, id: \.self) { c in
                    HStack(spacing: 6) {
                        Circle().fill(GlyphColor.warn).frame(width: 5, height: 5)
                        Text(label(c)).font(GlyphFont.body(12))
                    }
                }
                Text(t("exportLossKeepHint"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { onCancel() }.keyboardShortcut(.cancelAction)
            Button(t("continueExport")) { onConfirm() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.warn)
        }
    }
}
