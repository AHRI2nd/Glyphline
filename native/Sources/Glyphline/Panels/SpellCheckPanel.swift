// Proofreading results for the whole document.
//
// Rows are WORDS, not locations: the unit of work is "this word is wrong or
// inconsistent — fix or ignore it everywhere", so a word misspelled 30 times
// is one row showing "30 places", not 30 rows. Sorted worst-first by count.
//
// Two dismissal paths, because they mean different things:
//   • "Ignore in this project" → the .glyph file's own list. For a character
//     name that's only correct in this show.
//   • "Add to dictionary" → the system macOS dictionary. For a word that's
//     correct everywhere ("Netflix").

import SwiftUI
import GlyphlineCore

struct SpellCheckPanel: View {
    let document: DocumentModel
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [SpellIssue] = []
    @State private var hasRun = false

    private var dictionary: SystemSpellDictionary { SystemSpellDictionary() }

    /// For translation index 1+, the language was already named when it was
    /// added (see CueEditorBox's language chip flow) — reuse that code as the
    /// dictionary rather than asking again via a picker that only ever applied
    /// to a single, unlabeled translation column. Index 0 (legacy single
    /// translation, no language attached) still needs the manual picker below.
    private var autoTranslationLangCode: String? {
        let idx = document.activeTranslationLanguageIndex
        guard idx > 0, let languages = document.doc.translationLanguages, languages.indices.contains(idx) else {
            return nil
        }
        let code = languages[idx]
        return SystemSpellDictionary.isSupported(code) ? code : nil
    }

    /// The raw language code for the active translation slot (1+), shown as a
    /// read-only label — independent of whether macOS actually has a
    /// dictionary for it, so an unsupported language (e.g. Japanese) still
    /// shows which language is active instead of silently reverting to the
    /// index-0 picker.
    private var activeTranslationLangLabel: String? {
        let idx = document.activeTranslationLanguageIndex
        guard idx > 0, let languages = document.doc.translationLanguages, languages.indices.contains(idx) else {
            return nil
        }
        return languages[idx]
    }

    /// index 0 (legacy, unlabeled translation) uses the manual picker;
    /// index 1+ always follows the language it was added with, never the
    /// picker's leftover value from a different slot.
    private var effectiveTranslationDictLanguage: String? {
        document.activeTranslationLanguageIndex > 0
            ? autoTranslationLangCode
            : (settings.spellTranslationLanguage.isEmpty ? nil : settings.spellTranslationLanguage)
    }

    var body: some View {
        PanelShell(title: t("spellCheck"), width: 520) {
            VStack(alignment: .leading, spacing: 14) {
                languageControls
                Divider()
                results
                if let ignored = document.doc.ignoredWords, !ignored.isEmpty {
                    Divider()
                    ignoredSection(ignored)
                }
            }
        } footer: {
            Button(t("spellRecheck")) { run() }
            Spacer()
            PanelCloseButton()
        }
        .onAppear { if !hasRun { run() } }
        .onChange(of: document.activeTranslationLanguageIndex) { run() }
    }

    // ── controls ─────────────────────────────────────────────────────────────

    private var languageControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("spellTextLanguage")).font(GlyphFont.body(12))
                Spacer()
                languagePicker(Binding(
                    get: { settings.spellTextLanguage },
                    set: { settings.spellTextLanguage = $0; run() }
                ))
            }
            HStack {
                Text(t("spellTranslationLanguage")).font(GlyphFont.body(12))
                Spacer()
                if let label = activeTranslationLangLabel {
                    Text(label.uppercased()).font(GlyphFont.data(12)).foregroundStyle(GlyphColor.quiet)
                } else {
                    languagePicker(Binding(
                        get: { settings.spellTranslationLanguage },
                        set: { settings.spellTranslationLanguage = $0; run() }
                    ))
                }
            }
            Text(t("spellDictHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

            Toggle(t("spellCheckNotationToggle"), isOn: Binding(
                get: { settings.spellCheckNotation },
                set: { settings.spellCheckNotation = $0; run() }
            ))
            .toggleStyle(.checkbox).font(GlyphFont.body(12))
            Text(t("spellNotationHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
        }
    }

    private func languagePicker(_ binding: Binding<String>) -> some View {
        Picker("", selection: binding) {
            Text(t("spellLangNone")).tag("")
            ForEach(SystemSpellDictionary.supportedLanguages, id: \.self) { code in
                Text(code.uppercased()).tag(code)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    // ── results ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var results: some View {
        if issues.isEmpty {
            Text(t("spellNoIssues"))
                .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("spellIssueCount", "\(issues.count)"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .padding(.bottom, 6)
                ForEach(issues) { issue in
                    IssueRow(
                        issue: issue,
                        onJump: { jump(to: issue) },
                        onIgnore: { document.ignoreWord(issue.word); run() },
                        onLearn: { dictionary.learn(issue.word); run() }
                    )
                    Divider()
                }
            }
        }
    }

    private func ignoredSection(_ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("spellIgnoredWords")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            ForEach(words, id: \.self) { word in
                HStack {
                    Text(word).font(GlyphFont.body(12))
                    Spacer()
                    Button(t("spellUnignore")) {
                        document.unignoreWord(word)
                        run()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // ── actions ──────────────────────────────────────────────────────────────

    private func run() {
        hasRun = true
        // A word silenced either way should stop being reported, so the
        // project list and the system dictionary are merged before checking.
        let options = SpellCheckOptions(
            textLanguage: settings.spellTextLanguage.isEmpty ? nil : settings.spellTextLanguage,
            translationLanguage: effectiveTranslationDictLanguage,
            checkNotation: settings.spellCheckNotation,
            ignored: Set(document.doc.ignoredWords ?? [])
        )
        let dict = dictionary
        let idx = document.activeTranslationLanguageIndex
        let langs = document.doc.translationLanguages ?? []
        var found = checkDocument(document.doc, dictionary: dict, options: options) { $0.translationText(at: idx, languages: langs) }
        // Words already in the system dictionary aren't "unknown" — drop them.
        found.removeAll { $0.kind == .unknownWord && dict.hasLearned($0.word) }
        issues = found
    }

    private func jump(to issue: SpellIssue) {
        document.setActiveCue(issue.firstCueId)
    }
}

private struct IssueRow: View {
    let issue: SpellIssue
    let onJump: () -> Void
    let onIgnore: () -> Void
    let onLearn: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onJump) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(issue.word)
                            .font(GlyphFont.body(13))
                            .foregroundStyle(GlyphColor.ink)
                        Text(t("spellOccurrences", "\(issue.occurrences)"))
                            .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                    }
                    Text(subtitleText)
                        .font(GlyphFont.body(10))
                        .foregroundStyle(kindColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(t("spellIgnoreInProject"), action: onIgnore).controlSize(.small)
            if issue.kind == .unknownWord {
                Button(t("spellLearnWord"), action: onLearn).controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitleText: String {
        switch issue.kind {
        case .unknownWord:
            return t("spellUnknownWord")
        case .notationVariant(let others):
            return "\(t("spellNotationVariant")) · \(t("spellVariantOf", others.joined(separator: ", ")))"
        }
    }

    private var kindColor: Color {
        switch issue.kind {
        case .unknownWord: return GlyphColor.amber
        case .notationVariant: return GlyphColor.signal
        }
    }
}
