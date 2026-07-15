// ASS style CRUD (ported from ../../../src/components/Settings/StyleManagerModal.tsx).
//
// Edits are buffered in local @State and committed via a single `updateStyle`
// call on "적용" — NOT a live binding straight to DocumentModel. A ColorPicker's
// binding fires continuously while dragging; wiring that directly to
// `updateStyle` (which snapshots undo history on every call) would flood the
// 50-entry history with drag-intermediate states in a single gesture.

import SwiftUI
import AppKit
import GlyphlineCore

struct StyleManagerPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedName: String?
    @State private var editing: AssStyle?

    var body: some View {
        PanelShell(title: t("styleManager"), width: 560) {
            HStack(alignment: .top, spacing: 12) {
                styleList
                Divider()
                if let editing {
                    editorForm(editing)
                } else {
                    Text(t("selectStyleHint")).foregroundStyle(GlyphColor.quiet).frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: 320)
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .onAppear { selectFirst() }
    }

    private var styleList: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(document.doc.styles ?? [], id: \.name, selection: $selectedName) { style in
                Text(style.name).font(GlyphFont.body(12)).tag(style.name)
            }
            .frame(width: 150)
            .onChange(of: selectedName) { _, name in
                editing = (document.doc.styles ?? []).first { $0.name == name }
            }

            HStack {
                Button(t("addStyle")) {
                    document.addStyle()
                    selectedName = document.doc.styles?.last?.name
                }
                Button(t("deleteStyle")) {
                    guard let selectedName else { return }
                    document.deleteStyle(selectedName)
                    self.selectedName = nil
                    editing = nil
                }.disabled(selectedName == nil)
            }
            .controlSize(.small)
        }
    }

    private func editorForm(_ style: AssStyle) -> some View {
        Form {
            TextField(t("styleName"), text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
            TextField(t("font"), text: Binding(get: { editing?.fontName ?? "" }, set: { editing?.fontName = $0 }))
            HStack {
                Text(t("fontSize"))
                Stepper(value: Binding(get: { editing?.fontSize ?? 48 }, set: { editing?.fontSize = $0 }), in: 4...200) {
                    Text("\(Int(editing?.fontSize ?? 48))")
                }
            }
            colorRow(t("colorPrimary"), \.primaryColour)
            colorRow(t("colorOutline"), \.outlineColour)
            colorRow(t("colorBack"), \.backColour)
            Toggle(t("bold"), isOn: Binding(get: { editing?.bold ?? false }, set: { editing?.bold = $0 }))
            Toggle(t("italic"), isOn: Binding(get: { editing?.italic ?? false }, set: { editing?.italic = $0 }))
            HStack {
                Text(t("alignment"))
                Picker("", selection: Binding(get: { editing?.alignment ?? 2 }, set: { editing?.alignment = $0 })) {
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                }.labelsHidden().frame(width: 60)
            }
            HStack {
                marginStepper(t("marginLeft"), \.marginL)
                marginStepper(t("marginRight"), \.marginR)
                marginStepper(t("marginVertical"), \.marginV)
            }
            Button(t("apply")) { commit() }
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marginStepper(_ label: String, _ kp: WritableKeyPath<AssStyle, Int>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            Stepper(value: Binding(get: { editing?[keyPath: kp] ?? 0 }, set: { editing?[keyPath: kp] = $0 }), in: 0...500) {
                Text("\(editing?[keyPath: kp] ?? 0)").font(GlyphFont.data(11)).frame(width: 30)
            }
        }
    }

    private func colorRow(_ label: String, _ kp: WritableKeyPath<AssStyle, String>) -> some View {
        HStack {
            Text(label)
            ColorPicker("", selection: Binding(
                get: { Color(assHex: editing?[keyPath: kp] ?? "&H00FFFFFF") },
                set: { editing?[keyPath: kp] = $0.assColorHex(alpha: assAlpha(editing?[keyPath: kp] ?? "&H00")) }
            ))
            .labelsHidden()
        }
    }

    private func selectFirst() {
        guard let first = document.doc.styles?.first else { return }
        selectedName = first.name
        editing = first
    }

    private func commit() {
        guard let editing, let selectedName else { return }
        document.updateStyle(selectedName) { $0 = editing }
        self.selectedName = editing.name
    }
}

private extension Color {
    /// Decode an ASS "&HAABBGGRR" colour (alpha ignored — handled separately).
    init(assHex: String) {
        let hex = assColorToHex(assHex) // "#RRGGBB"
        let r = Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 255
        let g = Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 255
        let b = Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 255
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// Encode back to ASS "&HAABBGGRR", preserving the given alpha byte.
    func assColorHex(alpha: String) -> String {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        func byte(_ c: CGFloat) -> String { String(format: "%02X", Int((c * 255).rounded())) }
        let hex = "#\(byte(ns.redComponent))\(byte(ns.greenComponent))\(byte(ns.blueComponent))"
        return hexToAssColor(hex, alpha: alpha)
    }
}
