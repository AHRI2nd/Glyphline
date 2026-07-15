// Two-point linear sync (ported from ../../../src/components/Modals/PointSyncModal.tsx).

import SwiftUI
import GlyphlineCore

struct PointSyncPanel: View {
    let document: DocumentModel
    let media: MediaModel
    @Environment(\.dismiss) private var dismiss

    @State private var srcA = "0:00.000"
    @State private var dstA = "0:00.000"
    @State private var srcB = "0:00.000"
    @State private var dstB = "0:00.000"
    @State private var error: String?

    var body: some View {
        PanelShell(title: t("pointSync"), width: 440) {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("pointSyncHint"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)

                pointRow(label: t("pointA"), src: $srcA, dst: $dstA)
                pointRow(label: t("pointB"), src: $srcB, dst: $dstB)

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
        .onAppear {
            let cues = sortedCues(document.doc.cues)
            if let first = cues.first { srcA = formatDisplayTime(first.start); dstA = srcA }
            if let last = cues.last { srcB = formatDisplayTime(last.start); dstB = srcB }
        }
    }

    private func pointRow(label: String, src: Binding<String>, dst: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            HStack(spacing: 6) {
                timeField(src)
                Button(t("useActiveCue")) {
                    if let id = document.activeCueId, let cue = document.doc.cues.first(where: { $0.id == id }) {
                        src.wrappedValue = formatDisplayTime(cue.start)
                    }
                }.controlSize(.small)
                Image(systemName: "arrow.right").foregroundStyle(GlyphColor.quiet)
                timeField(dst)
                if media.mediaPath != nil {
                    Button("⌖ \(t("usePlayhead"))") { dst.wrappedValue = formatDisplayTime(media.currentTime) }
                        .controlSize(.small)
                }
            }
        }
    }

    private func timeField(_ binding: Binding<String>) -> some View {
        TextField("", text: binding)
            .font(GlyphFont.data(12))
            .multilineTextAlignment(.center)
            .frame(width: 100)
            .textFieldStyle(.roundedBorder)
    }

    private func apply() {
        guard let a = parseTimestampInput(srcA), let a2 = parseTimestampInput(dstA),
              let b = parseTimestampInput(srcB), let b2 = parseTimestampInput(dstB) else {
            error = t("pointSyncInvalidTime")
            return
        }
        guard document.applyPointSync(srcA: a, dstA: a2, srcB: b, dstB: b2) else {
            error = t("pointSyncSamePoints")
            return
        }
        dismiss()
    }
}
