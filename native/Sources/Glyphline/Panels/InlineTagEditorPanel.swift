// ASS inline override-tag editor for the active cue (ported from
// ../../../src/components/Modals/InlineTagEditorModal.tsx).
//
// Two modes over a single source of truth (`value`, the raw tagged Dialogue
// text): Structured (per-category controls for the first override block's
// tags — toggle/color/pos/align/scalar/raw) and Raw (free-form text + insert
// toolbar). Apply re-parses into assSpans (lossless for every tag, known or
// not) and recomputes plain text, same as the raw-block-only version this
// replaces.

import SwiftUI
import AppKit
import GlyphlineCore

struct InlineTagEditorPanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var value = ""
    @State private var rawMode = false

    private var cue: Cue? {
        document.doc.cues.first { $0.id == document.activeCueId }
    }

    private var spans: [AssSpan] { parseAssText(value) }
    private var leadIndex: Int? { spans.firstIndex { $0.tags != nil } }
    private var decoded: [DecodedTag] {
        guard let leadIndex else { return [] }
        return decodeTags(spans[leadIndex].tags!)
    }
    private var plain: String { spansToPlain(spans) }

    var body: some View {
        PanelShell(title: t("inlineTagEditor"), width: 640) {
            if cue != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $rawMode) {
                        Text(t("tagStructured")).tag(false)
                        Text(t("tagRaw")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .labelsHidden()

                    if rawMode {
                        rawEditor
                    } else {
                        structuredEditor
                    }

                    Text("\(t("preview")):").font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    Text(plain.isEmpty ? "—" : plain)
                        .font(GlyphFont.body(13))
                        .foregroundStyle(GlyphColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(GlyphColor.bg, in: RoundedRectangle(cornerRadius: 6))

                    if !decoded.isEmpty {
                        chipRow
                    }
                }
            } else {
                Text(t("noActiveCueShort")).foregroundStyle(GlyphColor.quiet)
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("apply")) { commit(); dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
                .disabled(cue == nil)
        }
        .onAppear {
            guard let cue else { return }
            value = (cue.assSpans?.isEmpty == false) ? serializeAssText(cue.assSpans!) : cue.text
        }
    }

    // ── structured mode ─────────────────────────────────────────────────────────

    private var structuredEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if decoded.isEmpty {
                Text(t("noTags")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(decoded.enumerated()), id: \.offset) { i, tag in
                    TagRow(
                        tag: tag,
                        onChange: { editTag(i, $0) },
                        onRemove: { removeTag(i) }
                    )
                }
            }
            HStack(spacing: 6) {
                Text("\(t("addTag")):").font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                Menu("＋") {
                    ForEach(ADDABLE_TAGS, id: \.self) { name in
                        Button("\\\(name)") { addTag(name) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(8)
        .background(GlyphColor.bg, in: RoundedRectangle(cornerRadius: 6))
    }

    private var chipRow: some View {
        FlowChips(items: decoded)
    }

    private func commitTags(_ tags: [DecodedTag]) {
        let block = tags.map { "\\\($0.name)\($0.arg)" }.joined()
        var next = parseAssText(value)
        if let i = next.firstIndex(where: { $0.tags != nil }) {
            next[i] = block.isEmpty ? AssSpan(text: next[i].text) : AssSpan(tags: block, text: next[i].text)
        } else if !block.isEmpty {
            next.insert(AssSpan(tags: block, text: ""), at: 0)
        }
        value = serializeAssText(next)
    }

    private func editTag(_ idx: Int, _ arg: String) {
        var next = decoded
        guard idx < next.count else { return }
        next[idx].arg = arg
        commitTags(next)
    }
    private func removeTag(_ idx: Int) {
        var next = decoded
        guard idx < next.count else { return }
        next.remove(at: idx)
        commitTags(next)
    }
    private func addTag(_ name: String) {
        commitTags(decoded + [DecodedTag(name: name, arg: defaultTagArg(name), known: true)])
    }

    // ── raw mode ─────────────────────────────────────────────────────────────────

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                RawToolButton("B", bold: true) { wrap("{\\b1}", "{\\b0}") }
                RawToolButton("i", italic: true) { wrap("{\\i1}", "{\\i0}") }
                RawToolButton("U", underline: true) { wrap("{\\u1}", "{\\u0}") }
                Divider().frame(height: 14)
                RawToolButton("{\\pos}") { value += "{\\pos(960,540)}" }
                RawToolButton("{\\fad}") { value += "{\\fad(200,200)}" }
                RawToolButton("{\\an8}") { value += "{\\an8}" }
                RawToolButton("{\\r}") { value += "{\\r}" }
            }
            TextEditor(text: $value)
                .font(GlyphFont.data(11))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(GlyphColor.borderStrong, lineWidth: 0.5))
        }
    }

    /// Wraps the current selection in an override block pair, or appends both
    /// halves at the end if nothing is selected (no NSTextView selection range
    /// is exposed through SwiftUI's plain TextEditor binding).
    private func wrap(_ open: String, _ close: String) {
        value += "\(open)\(close)"
    }

    private func commit() {
        guard let cue else { return }
        let finalSpans = parseAssText(value)
        let finalPlain = spansToPlain(finalSpans)
        document.updateCue(cue.id) {
            $0.assSpans = finalSpans
            $0.text = finalPlain
        }
    }
}

// ─── per-tag control ─────────────────────────────────────────────────────────

private enum TagCtl { case toggle, color, pos, align, scalar, raw }

private let TOGGLE_TAGS: Set<String> = ["b", "i", "u", "s"]
private let COLOR_TAGS: Set<String> = ["c", "1c", "2c", "3c", "4c"]
private let POS_TAGS: Set<String> = ["pos", "move", "org"]
private let ALIGN_TAGS: Set<String> = ["an", "a"]
private let SCALAR_TAGS: Set<String> = [
    "fs", "fsp", "fscx", "fscy", "frx", "fry", "frz", "fr", "fax", "fay",
    "bord", "xbord", "ybord", "shad", "xshad", "yshad", "be", "blur",
    "k", "kf", "ko", "kt", "K",
]
private let ADDABLE_TAGS = ["b", "i", "u", "s", "1c", "fs", "fscx", "fscy", "frz", "bord", "shad", "blur", "pos", "an", "fad", "r"]

private func ctl(for name: String) -> TagCtl {
    if TOGGLE_TAGS.contains(name) { return .toggle }
    if COLOR_TAGS.contains(name) { return .color }
    if POS_TAGS.contains(name) { return .pos }
    if ALIGN_TAGS.contains(name) { return .align }
    if SCALAR_TAGS.contains(name) { return .scalar }
    return .raw
}

private func defaultTagArg(_ name: String) -> String {
    switch ctl(for: name) {
    case .toggle: return "1"
    case .color: return "&H0000FF"
    case .pos: return name == "move" ? "(0,0,0,0)" : "(960,540)"
    case .align: return "8"
    case .scalar: return "0"
    case .raw: return (name == "fad" || name == "fade") ? "(200,200)" : ""
    }
}

private struct TagRow: View {
    let tag: DecodedTag
    let onChange: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\\\(tag.name)")
                .font(GlyphFont.data(11, weight: .semibold))
                .foregroundStyle(tag.known ? GlyphColor.ink : GlyphColor.warn)
                .frame(width: 52)
                .padding(.vertical, 2)
                .background(tag.known ? Color.clear : GlyphColor.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

            control

            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(GlyphColor.quiet)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch ctl(for: tag.name) {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { tag.arg.trimmingCharacters(in: .whitespaces) == "1" },
                set: { onChange($0 ? "1" : "0") }
            )).toggleStyle(.checkbox).labelsHidden()
        case .color:
            ColorPicker("", selection: Binding(
                get: { Color(assHex: tag.arg) },
                set: { onChange($0.assColorHex(alpha: assAlpha(tag.arg))) }
            )).labelsHidden().frame(width: 44)
        case .pos:
            PosInputs(arg: tag.arg, onChange: onChange)
        case .align:
            Picker("", selection: Binding(
                get: { Int(tag.arg.trimmingCharacters(in: .whitespaces)) ?? 8 },
                set: { onChange("\($0)") }
            )) {
                ForEach([7, 8, 9, 4, 5, 6, 1, 2, 3], id: \.self) { Text("\($0)").tag($0) }
            }.labelsHidden().frame(width: 60)
        case .scalar:
            TextField("", text: Binding(get: { tag.arg }, set: { onChange($0) }))
                .font(GlyphFont.data(11)).frame(width: 70).textFieldStyle(.roundedBorder)
        case .raw:
            TextField("", text: Binding(get: { tag.arg }, set: { onChange($0) }))
                .font(GlyphFont.data(11)).textFieldStyle(.roundedBorder)
        }
    }
}

/// Parses "(a,b[,c,d])" into numeric inputs and rebuilds on change.
private struct PosInputs: View {
    let arg: String
    let onChange: (String) -> Void

    private var parts: [String] {
        let inner = arg.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        return inner.isEmpty ? ["0", "0"] : inner.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                TextField("", text: Binding(
                    get: { p },
                    set: { newVal in
                        var next = parts
                        next[i] = newVal
                        onChange("(\(next.joined(separator: ",")))")
                    }
                ))
                .font(GlyphFont.data(11)).frame(width: 44).textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct RawToolButton: View {
    let label: String
    var bold = false
    var italic = false
    var underline = false
    let action: () -> Void

    init(_ label: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: bold ? .bold : .regular).italic(italic))
                .underline(underline)
                .padding(.horizontal, 6).padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Detected-tag chips mirroring the structured block (known=good, unknown=warn).
private struct FlowChips: View {
    let items: [DecodedTag]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, d in
                Text("\\\(d.name)\(d.arg)")
                    .font(GlyphFont.data(10))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(
                        (d.known ? GlyphColor.good : GlyphColor.warn).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .foregroundStyle(d.known ? GlyphColor.good : GlyphColor.warn)
            }
        }
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
