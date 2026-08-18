// The multi-line editor for the active cue, sitting under the grid.
//
// WHY this exists: the grid edits in single-line NSTextFields with truncating
// display, so a two-line subtitle showed as "first line second li…" and there
// was no way to type a line break at all. Deciding where a subtitle breaks is
// half of subtitle work, and it can't be done in a control that won't show or
// accept the break. Both Subtitle Edit and Aegisub pair their grid with a
// dedicated edit box for exactly this reason.
//
// Per-line character counts sit under the box and turn amber past the quality
// threshold — the same number the quality check flags on, so the warning and
// the fix are in one place instead of one telling you and the other hiding it.

import SwiftUI
import GlyphlineCore

struct CueEditorBox: View {
    let document: DocumentModel
    let settings: AppSettings

    /// Local draft. The document is the source of truth, but binding a
    /// TextEditor straight to it would fight the user: every keystroke mutates
    /// the doc, which re-renders this view, which can reset the caret mid-word.
    /// So the draft is authoritative WHILE editing and re-synced only when the
    /// active cue changes.
    @State private var text = ""
    @State private var translation = ""
    @State private var editingCueId: String?
    @State private var textSelection: TextSelection?
    @FocusState private var focus: Field?
    @State private var showingAddLanguage = false
    @State private var newPrimaryCode = ""
    @State private var newLanguageCode = ""
    /// Set when the user taps a language chip's remove button while that
    /// language actually has translated content somewhere in the document —
    /// a single small "x" click otherwise wiped that language from every cue
    /// with no confirmation at all.
    @State private var languagePendingRemoval: (index: Int, code: String)?

    private enum Field { case text, translation }

    /// Empty when the document has never added a second translation language
    /// (`doc.translationLanguages == nil`) — the single-language, unlabeled
    /// case every existing project is in today.
    private var languages: [String] { document.doc.translationLanguages ?? [] }
    private var activeIndex: Int { document.activeTranslationLanguageIndex }

    private var cue: Cue? {
        guard let id = document.activeCueId else { return nil }
        return document.doc.cues.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cue {
                editor(for: cue)
            } else {
                Text(t("noActiveCueShort"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .top)
        .onChange(of: document.activeCueId) { _, _ in syncFromDocument() }
        .onChange(of: document.activeTranslationLanguageIndex) { _, _ in syncFromDocument() }
        .onAppear { syncFromDocument() }
        // Without this, an interactive bracket left open by typing (below)
        // only closed on the NEXT cue change — so clicking away to do
        // something else entirely (Find & Replace's "Replace All", a
        // batch-cleanup action, …) while this box still had focus-less
        // pending keystrokes got silently fused into the same undo step.
        .onChange(of: focus) { _, newValue in
            if newValue == nil, editingCueId != nil {
                document.endInteractive()
                editingCueId = nil
            }
        }
        .confirmationDialog(
            t("removeTranslationLanguageConfirmTitle"),
            isPresented: Binding(
                get: { languagePendingRemoval != nil },
                set: { if !$0 { languagePendingRemoval = nil } }
            ),
            presenting: languagePendingRemoval
        ) { pending in
            Button(t("removeTranslationLanguageConfirmAction"), role: .destructive) {
                document.removeTranslationLanguage(at: pending.index)
            }
            Button(t("cancel"), role: .cancel) {}
        } message: { pending in
            Text(t("removeTranslationLanguageConfirmMessage", pending.code.uppercased()))
        }
    }

    @ViewBuilder
    private func editor(for cue: Cue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextEditor(text: $text, selection: $textSelection)
                    .font(GlyphFont.body(13))
                    .scrollContentBackground(.hidden)
                    .background(GlyphColor.bg)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(GlyphColor.borderStrong, lineWidth: 0.5))
                    .frame(height: 56)
                    .focused($focus, equals: .text)
                    .onChange(of: text) { _, next in commit(cue.id) { $0.text = next } }
                HStack(spacing: 4) {
                    styleButton(.bold, "bold")
                    styleButton(.italic, "italic")
                    styleButton(.underline, "underline")
                    Divider().frame(height: 12)
                    lineCounts(text)
                }
            }

            if settings.showTranslation {
                VStack(alignment: .leading, spacing: 3) {
                    translationHeader
                    TextEditor(text: $translation)
                        .font(GlyphFont.body(13))
                        .scrollContentBackground(.hidden)
                        .background(GlyphColor.bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(GlyphColor.borderStrong, lineWidth: 0.5))
                        .frame(height: 56)
                        .focused($focus, equals: .translation)
                        .onChange(of: translation) { _, next in
                            let idx = activeIndex; let langs = languages
                            commit(cue.id) { $0.setTranslationText(next, at: idx, languages: langs) }
                        }
                    lineCounts(translation)
                }
            }

            VStack(spacing: 4) {
                Button(t("autoBreakLines")) {
                    let next = breakLines(text,
                                          maxLineLength: settings.quality.maxLineLength,
                                          maxLines: settings.quality.maxLines)
                    text = next
                }
                .controlSize(.small)
                Button(t("unbreakLines")) { text = unbreakLines(text) }
                    .controlSize(.small)
            }
            .frame(width: 92)
        }
    }

    /// The markup dialect this document's format speaks — HTML tags for
    /// SRT/VTT/SMI/TTML, override blocks for ASS, nothing for plain-text
    /// formats (where the buttons are disabled rather than writing markup that
    /// would be delivered literally).
    private var markup: InlineMarkup { InlineMarkup.forFormat(document.doc.format) }

    private func styleButton(_ style: InlineStyle, _ symbol: String) -> some View {
        Button {
            applyStyle(style)
        } label: {
            Image(systemName: symbol).frame(width: 14)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(markup == InlineMarkup.none)
        .help(t("style_\(style.rawValue)"))
        .keyboardShortcut(shortcut(for: style), modifiers: [.command, .option])
    }

    // ⌘⌥B/I/U rather than the usual ⌘B/I/U: plain ⌘B is AppKit's rich-text
    // "bold face" on the field editor, which a plain-text TextEditor answers by
    // doing nothing — so the tag would never get written.
    private func shortcut(for style: InlineStyle) -> KeyEquivalent {
        switch style {
        case .bold: return "b"
        case .italic: return "i"
        case .underline: return "u"
        }
    }

    private func applyStyle(_ style: InlineStyle) {
        let offsets = selectedOffsets()
        let result = toggleInlineStyle(style, in: text, selection: offsets, markup: markup)
        text = result.text
        // Re-select the same words in the rewritten string, so a second press
        // (or a second style) acts on what's still highlighted instead of on a
        // collapsed caret at position 0.
        let chars = result.text.count
        let lo = result.text.index(result.text.startIndex, offsetBy: min(result.selection.lowerBound, chars))
        let hi = result.text.index(result.text.startIndex, offsetBy: min(result.selection.upperBound, chars))
        textSelection = TextSelection(range: lo..<hi)
    }

    /// The current selection as character offsets. An absent or multi-range
    /// selection collapses to empty, which `toggleInlineStyle` reads as
    /// "the whole cue".
    private func selectedOffsets() -> Range<Int> {
        guard let textSelection, case .selection(let range) = textSelection.indices else { return 0..<0 }
        let lo = text.distance(from: text.startIndex, to: range.lowerBound)
        let hi = text.distance(from: text.startIndex, to: range.upperBound)
        return lo..<hi
    }

    /// One count per line, amber past the threshold, plus the CPS the quality
    /// check actually measures.
    @ViewBuilder
    private func lineCounts(_ value: String) -> some View {
        let limit = settings.quality.maxLineLength
        let lines = value.components(separatedBy: "\n")
        HStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\(line.count)")
                    .font(GlyphFont.data(10))
                    .foregroundStyle(line.count > limit ? GlyphColor.amber : GlyphColor.quiet)
            }
            if lines.count > settings.quality.maxLines {
                Text(t("tooManyLines")).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.amber)
            }
            Spacer()
            if let cue, cueDuration(cue) > 0 {
                let rate = cps(cue)
                Text(String(format: "%.0f cps", rate))
                    .font(GlyphFont.data(10))
                    .foregroundStyle(rate > settings.quality.maxCps ? GlyphColor.amber : GlyphColor.quiet)
            }
        }
    }

    // ── document sync ────────────────────────────────────────────────────────

    private func syncFromDocument() {
        // Close out whatever gesture the previous cue's edits belonged to before
        // adopting a new one, so its undo entry doesn't absorb the next cue too.
        if editingCueId != nil { document.endInteractive(); editingCueId = nil }
        text = cue?.text ?? ""
        translation = cue?.translationText(at: activeIndex, languages: languages) ?? ""
    }

    // ── translation language switcher ───────────────────────────────────────

    @ViewBuilder
    private var translationHeader: some View {
        HStack(spacing: 4) {
            if languages.count > 1 {
                ForEach(Array(languages.enumerated()), id: \.offset) { idx, code in
                    languageChip(code: code, index: idx)
                }
            } else {
                Text(t("translation")).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
            }
            Button { showingAddLanguage = true } label: {
                Image(systemName: "plus.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GlyphColor.quiet)
            .help(t("addTranslationLanguage"))
            .popover(isPresented: $showingAddLanguage) { addLanguagePopover }
            Spacer()
        }
    }

    private func languageChip(code: String, index: Int) -> some View {
        HStack(spacing: 2) {
            Text(code.uppercased()).font(GlyphFont.data(10, weight: index == activeIndex ? .bold : .regular))
            if index > 0 {
                Button { requestRemoveLanguage(at: index, code: code) } label: {
                    Image(systemName: "xmark").font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help(t("removeTranslationLanguage"))
            }
        }
        .foregroundStyle(index == activeIndex ? GlyphColor.ink : GlyphColor.quiet)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(index == activeIndex ? GlyphColor.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { document.activeTranslationLanguageIndex = index }
    }

    @ViewBuilder
    private var addLanguagePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if languages.isEmpty {
                Text(t("labelPrimaryLanguagePrompt")).font(GlyphFont.body(11))
                TextField(t("languageCode"), text: $newPrimaryCode).textFieldStyle(.roundedBorder).frame(width: 100)
            }
            Text(t("addTranslationLanguagePrompt")).font(GlyphFont.body(11))
            TextField(t("languageCode"), text: $newLanguageCode).textFieldStyle(.roundedBorder).frame(width: 100)
            HStack {
                Spacer()
                Button(t("add")) { addLanguage() }
                    .disabled(newLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (languages.isEmpty && newPrimaryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(10)
        .frame(width: 220)
    }

    /// Skips the confirmation for a language nobody's translated into yet —
    /// only a real removal (content that would actually be lost) needs one.
    private func requestRemoveLanguage(at index: Int, code: String) {
        let hasContent = document.doc.cues.contains {
            !($0.translationText(at: index, languages: languages) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasContent {
            languagePendingRemoval = (index, code)
        } else {
            document.removeTranslationLanguage(at: index)
        }
    }

    private func addLanguage() {
        document.addTranslationLanguage(newLanguageCode, primaryLanguageCode: newPrimaryCode)
        if let langs = document.doc.translationLanguages, !langs.isEmpty {
            document.activeTranslationLanguageIndex = langs.count - 1
        }
        newLanguageCode = ""
        newPrimaryCode = ""
        showingAddLanguage = false
    }

    /// Typing is one continuous gesture per cue: the first keystroke opens an
    /// interactive bracket so a sentence lands as ONE undo step rather than one
    /// per character. It closes when the active cue changes (above).
    private func commit(_ id: String, _ edit: @escaping CueEdit) {
        if editingCueId != id {
            if editingCueId != nil { document.endInteractive() }
            document.beginInteractive()
            editingCueId = id
        }
        document.updateCue(id, edit)
    }
}
