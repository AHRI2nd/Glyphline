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

    @State private var issues: [TermIssue] = []
    @State private var newSource = ""
    @State private var newTarget = ""
    @State private var hasRun = false

    private var glossary: [GlossaryEntry] { document.doc.glossary ?? [] }

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
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .onAppear { if !hasRun { run() } }
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
            Text(t("tcGlossary")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            Text(t("tcGlossaryHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

            if glossary.isEmpty {
                Text(t("tcGlossaryEmpty"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .padding(.vertical, 4)
            } else {
                ForEach(glossary) { entry in
                    HStack(spacing: 8) {
                        Text(entry.source).font(GlyphFont.body(12)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("→").font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                        Text(entry.target).font(GlyphFont.body(12)).frame(maxWidth: .infinity, alignment: .leading)
                        Button(t("tcRemoveTerm")) {
                            document.removeGlossaryEntry(source: entry.source)
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
                    newTarget = (cue.translation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        document.upsertGlossaryEntry(source: newSource, target: newTarget)
        newSource = ""
        newTarget = ""
        run()
    }

    private func run() {
        hasRun = true
        issues = checkTranslationConsistency(
            document.doc,
            glossary: glossary,
            checkDivergent: settings.checkDivergentTranslations
        )
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
