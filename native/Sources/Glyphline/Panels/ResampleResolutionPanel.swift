// Retarget a script at a new PlayRes — font/border/shadow/margins and every
// \pos/\move/\org/\fs/\bord/\shad/\blur override scaled to match (see
// ResolutionResample.swift for what's covered and what isn't).

import SwiftUI
import GlyphlineCore

struct ResampleResolutionPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText: String
    @State private var heightText: String
    @State private var keepAspect = true

    private let presets: [(String, Double, Double)] = [
        ("SD (720×480)", 720, 480),
        ("HD (1280×720)", 1280, 720),
        ("Full HD (1920×1080)", 1920, 1080),
        ("4K UHD (3840×2160)", 3840, 2160),
    ]

    init(document: DocumentModel) {
        self.document = document
        let current = scriptResolution(of: document.doc)
        _widthText = State(initialValue: String(Int(current.x)))
        _heightText = State(initialValue: String(Int(current.y)))
    }

    private var current: (x: Double, y: Double) { scriptResolution(of: document.doc) }
    private var targetWidth: Double? { Double(widthText) }
    private var targetHeight: Double? { Double(heightText) }

    var body: some View {
        PanelShell(title: t("resampleResolution"), width: 380) {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("resampleCurrentRes", "\(Int(current.x))", "\(Int(current.y))"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)

                HStack {
                    Text(t("resampleTarget")).font(GlyphFont.body(12))
                    Spacer()
                    Menu(t("resamplePresets")) {
                        ForEach(presets, id: \.0) { name, w, h in
                            Button(name) { widthText = String(Int(w)); heightText = String(Int(h)) }
                        }
                    }
                    .controlSize(.small)
                }
                HStack(spacing: 6) {
                    NumberField(label: t("resampleWidth"), value: $widthText, width: 70)
                        .onChange(of: widthText) { _, new in guard keepAspect, let w = Double(new) else { return }
                            heightText = String(Int((w * current.y / current.x).rounded())) }
                    Text("×").foregroundStyle(GlyphColor.quiet)
                    NumberField(label: t("resampleHeight"), value: $heightText, width: 70)
                        .onChange(of: heightText) { _, new in guard keepAspect, let h = Double(new) else { return }
                            widthText = String(Int((h * current.x / current.y).rounded())) }
                }
                Toggle(t("resampleKeepAspect"), isOn: $keepAspect).toggleStyle(.checkbox).font(GlyphFont.body(12))

                Text(t("resampleHint"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("apply")) {
                guard let w = targetWidth, let h = targetHeight, w > 0, h > 0 else { return }
                document.resampleResolution(toWidth: w, toHeight: h)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(GlyphColor.accent)
            .disabled((targetWidth ?? 0) <= 0 || (targetHeight ?? 0) <= 0)
        }
    }
}
