// Translation consistency: findings on top, the glossary that drives half of
// them underneath. They're one panel rather than two because the glossary is
// only ever edited in response to a finding — you see a term rendered two ways,
// you decide which is right, you write it down so it stays decided.
//
// The engine is in GlyphlineCore/TermConsistency.swift; this is presentation
// plus the two document actions (upsert/remove) that make the glossary stick.

import SwiftUI
import GlyphlineCore

struct TranslationCheckPanel: View {
    let document: DocumentModel
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var issues: [TermIssue] = []
    @State private var newSource = ""
    @State private var newTarget = ""
    @State private var hasRun = false
    @State private var refreshTask: Task<Void, Never>?

    private var glossary: [GlossaryEntry] { document.doc.glossary ?? [] }

    /// nil until the document has added a second translation language (see
    /// DocumentModel.addTranslationLanguage) — matches every existing
    /// project's untagged glossary entries (`GlossaryEntry.language == nil`).
    private var activeLanguageCode: String? {
        let languages = document.doc.translationLanguages ?? []
        guard languages.indices.contains(document.activeTranslationLanguageIndex) else { return nil }
        return languages[document.activeTranslationLanguageIndex]
    }

    /// Only entries that apply to the language currently being edited —
    /// language-tagged entries for a DIFFERENT language would just be noise
    /// (and false "misses") here. Untagged (`language == nil`) entries apply
    /// regardless, matching every existing single-language project exactly.
    private func forActiveLanguage(_ entries: [GlossaryEntry]) -> [GlossaryEntry] {
        entries.filter { $0.language == nil || $0.language == activeLanguageCode }
    }

    /// Document-local entries plus the shared (cross-project) glossary — see
    /// AppSettings.sharedGlossary. A document-local entry for the same source
    /// term wins, since it's the more specific override for this file.
    private var effectiveGlossary: [GlossaryEntry] {
        let docEntries = forActiveLanguage(glossary)
        let docSources = Set(docEntries.map(\.source))
        return docEntries + forActiveLanguage(settings.sharedGlossary).filter { !docSources.contains($0.source) }
    }

    var body: some View {
        PanelShell(title: t("translationCheck"), width: 560) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(t("tcCheckDivergent"), isOn: Binding(
                    get: { settings.checkDivergentTranslations },
                    set: { settings.checkDivergentTranslations = $0; run() }
                ))
                .toggleStyle(.checkbox).font(GlyphFont.body(12))
                Text(t("tcDivergentHint"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

                Divider()
                results
                Divider()
                glossarySection
            }
        } footer: {
            Button(t("spellRecheck")) { run() }
            Spacer()
            PanelCloseButton()
        }
        .onAppear { if !hasRun { run() } }
        // Same staleness fix as SpellCheckPanel: without this, editing a
        // translation while this panel sat open left findings frozen at
        // whatever they were when the panel last ran. Debounced for the same
        // reason (glossaryIssues is O(entries × cues) — see run() below).
        .onChange(of: document.doc.cues) { _, _ in scheduleRefresh() }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            run()
        }
    }

    // ── findings ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var results: some View {
        if issues.isEmpty {
            Text(t("tcNoIssues"))
                .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                .frame(maxWidth: .infinity, minHeight: 52)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("spellIssueCount", "\(issues.count)"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .padding(.bottom, 6)
                ForEach(issues) { issue in
                    IssueRow(issue: issue) { document.setActiveCue(issue.firstCueId) }
                    Divider()
                }
            }
        }
    }

    // ── glossary ─────────────────────────────────────────────────────────────

    private var glossarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("tcGlossary")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                Spacer()
                Button(t("tcOpenSharedGlossary")) { openWindow(id: SHARED_GLOSSARY_WINDOW_ID) }
                    .controlSize(.small)
            }
            Text(t("tcGlossaryHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            if !settings.sharedGlossary.isEmpty {
                Text(t("tcSharedGlossaryApplied", "\(settings.sharedGlossary.count)"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.signal)
            }

            let visible = forActiveLanguage(glossary)
            if visible.isEmpty {
                Text(t("tcGlossaryEmpty"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { entry in
                    HStack(spacing: 8) {
                        Text(entry.source).font(GlyphFont.body(12)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("→").font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                        Text(entry.target).font(GlyphFont.body(12)).frame(maxWidth: .infinity, alignment: .leading)
                        if let lang = entry.language {
                            Text(lang.uppercased()).font(GlyphFont.data(9)).foregroundStyle(GlyphColor.quiet)
                        }
                        Button(t("tcRemoveTerm")) {
                            document.removeGlossaryEntry(source: entry.source, language: entry.language)
                            run()
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(t("tcSourceTerm"), text: $newSource)
                    .textFieldStyle(.roundedBorder).font(GlyphFont.body(12))
                TextField(t("tcTargetTerm"), text: $newTarget)
                    .textFieldStyle(.roundedBorder).font(GlyphFont.body(12))
                Button(t("tcAddTerm")) { addTerm() }
                    .controlSize(.small)
                    .disabled(newSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || newTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Most terms are noticed while looking at a cue, so offer the
            // active cue's own text as the starting point instead of making
            // the user retype a name they're already looking at.
            if let cue = activeCue {
                Button(t("tcAddFromCue")) {
                    newSource = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let languages = document.doc.translationLanguages ?? []
                    let translation = cue.translationText(at: document.activeTranslationLanguageIndex, languages: languages) ?? ""
                    newTarget = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .controlSize(.small)
            }
        }
    }

    private var activeCue: Cue? {
        guard let id = document.activeCueId else { return nil }
        return document.doc.cues.first { $0.id == id }
    }

    // ── actions ──────────────────────────────────────────────────────────────

    private func addTerm() {
        document.upsertGlossaryEntry(source: newSource, target: newTarget, language: activeLanguageCode)
        newSource = ""
        newTarget = ""
        run()
    }

    private func run() {
        hasRun = true
        // Off the main actor: glossaryIssues is O(entries × cues) with a
        // substring search per pair, so a large house-style glossary checked
        // against a long document (measured: 200 terms × 5,000 cues ≈ 0.7s)
        // would otherwise stall the panel — everything captured here is a
        // Sendable value type, so the check itself can run on a background
        // thread with zero risk of touching document/settings off the main
        // actor.
        let idx = document.activeTranslationLanguageIndex
        let languages = document.doc.translationLanguages ?? []
        let doc = document.doc
        let glossary = effectiveGlossary
        let checkDivergent = settings.checkDivergentTranslations
        Task {
            let result = await Task.detached {
                checkTranslationConsistency(
                    doc, glossary: glossary, checkDivergent: checkDivergent
                ) { $0.translationText(at: idx, languages: languages) }
            }.value
            issues = result
        }
    }
}

private struct IssueRow: View {
    let issue: TermIssue
    let onJump: () -> Void

    var body: some View {
        Button(action: onJump) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(issue.source)
                        .font(GlyphFont.body(13)).foregroundStyle(GlyphColor.ink)
                        .lineLimit(1)
                    Text(countLabel)
                        .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                }
                Text(detail)
                    .font(GlyphFont.body(10)).foregroundStyle(kindColor)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var countLabel: String {
        switch issue.kind {
        case .divergentTranslation: return t("tcVariants", "\(issue.occurrences)")
        case .glossaryMismatch: return t("tcMissCount", "\(issue.occurrences)")
        }
    }

    private var detail: String {
        switch issue.kind {
        case .divergentTranslation(let variants):
            return "\(t("tcDivergent")) · \(variants.joined(separator: " / "))"
        case .glossaryMismatch(let expected):
            return "\(t("tcGlossaryMismatch")) · \(t("tcExpected", expected))"
        }
    }

    private var kindColor: Color {
        switch issue.kind {
        case .divergentTranslation: return GlyphColor.signal
        case .glossaryMismatch: return GlyphColor.amber
        }
    }
}
