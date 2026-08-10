// Translation consistency for the source/translation pair. Two checks, both
// deliberately deterministic — this file makes no guess about meaning, so
// nothing it reports can be a false positive about the language itself.
//
//   1. Repeated source, divergent translation — the same source line appears
//      more than once but was rendered differently each time. Common with
//      recurring lines (「はい」, a catchphrase, a recurring sign) where the
//      inconsistency is invisible while you work because the occurrences are
//      hundreds of cues apart. Zero configuration and zero false positives:
//      it only ever states "this identical input produced different output".
//
//   2. Glossary — the user declares "source term X must appear as Y", and
//      every cue whose source contains X is checked for Y in its translation.
//      This is where character names, place names and invented terms belong,
//      because no amount of analysis can infer that 鈴木 is meant to be 스즈키
//      in THIS show.
//
// Why not auto-extract terms: morphological analysis (lemma/part-of-speech)
// is unavailable for Korean and Japanese on this platform — verified against
// NLTagger before this was designed — so any automatic notion of "term" would
// be guesswork presented as fact. Substring matching against a declared
// glossary is honest about what it knows.

import Foundation

/// One declared term mapping. `.glyph`-only, like the proofreader's ignore
/// list — external subtitle formats have nowhere to carry it.
public struct GlossaryEntry: Codable, Equatable, Sendable, Identifiable {
    public var source: String
    public var target: String
    /// Free-form reminder for the translator ("keep honorific", "brand name").
    public var note: String?
    /// Which translation language `target` is correct for — nil means "any
    /// language" (today's behavior: a project with a single, unlabeled
    /// translation just never sets this). Set once a project has more than
    /// one translation language, since a glossary target is only meaningful
    /// for ONE target language ("스즈키" is right for Japanese, wrong for
    /// English "Suzuki").
    public var language: String?

    /// Composite so the same source term can have a different target per
    /// language without colliding in a SwiftUI List/upsert-by-id.
    public var id: String { "\(source)#\(language ?? "")" }

    public init(source: String, target: String, note: String? = nil, language: String? = nil) {
        self.source = source
        self.target = target
        self.note = note
        self.language = language
    }
}

public struct TermIssue: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// One source line, several different translations of it.
        case divergentTranslation(variants: [String])
        /// Source contains the glossary term but the translation lacks its target.
        case glossaryMismatch(expected: String)
    }

    public let kind: Kind
    /// The source text this is about (the repeated line, or the glossary term).
    public let source: String
    public let occurrences: Int
    /// Where "jump to" lands.
    public let firstCueId: String

    public var id: String {
        switch kind {
        case .divergentTranslation: return "div:\(source)"
        case .glossaryMismatch: return "glo:\(source)"
        }
    }

    public init(kind: Kind, source: String, occurrences: Int, firstCueId: String) {
        self.kind = kind
        self.source = source
        self.occurrences = occurrences
        self.firstCueId = firstCueId
    }
}

/// Normalizes for comparison: trims, collapses runs of whitespace (including
/// the line breaks that differ purely because of where a line was wrapped) to
/// a single space. Two cues that differ only in wrapping are the same line.
func consistencyKey(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// Cues whose source text repeats but whose translations don't agree.
///
/// Cues with an empty translation are skipped rather than counted as a variant:
/// "not translated yet" is a different problem from "translated inconsistently",
/// and conflating them would bury the real finding under every untranslated line.
public func divergentTranslations(
    in doc: SubtitleDocument,
    translationSelector: (Cue) -> String? = { $0.translation }
) -> [TermIssue] {
    var bySource: [String: (first: String, display: String, variants: [String])] = [:]
    for cue in sortedCues(doc.cues) {
        let src = consistencyKey(cue.text)
        guard !src.isEmpty else { continue }
        let translated = consistencyKey(translationSelector(cue) ?? "")
        guard !translated.isEmpty else { continue }
        if var entry = bySource[src] {
            if !entry.variants.contains(translated) { entry.variants.append(translated) }
            bySource[src] = entry
        } else {
            bySource[src] = (first: cue.id, display: cue.text, variants: [translated])
        }
    }
    return bySource.values
        .filter { $0.variants.count > 1 }
        .map {
            TermIssue(
                kind: .divergentTranslation(variants: $0.variants),
                source: $0.display,
                occurrences: $0.variants.count,
                firstCueId: $0.first
            )
        }
        .sorted { $0.occurrences != $1.occurrences ? $0.occurrences > $1.occurrences : $0.source < $1.source }
}

/// Cues whose source contains a glossary term while the translation is missing
/// that term's target.
///
/// Matching is plain, case-insensitive substring containment — no word
/// boundaries, because Korean and Japanese don't delimit words with spaces, so
/// a boundary rule tuned for English would silently miss every CJK term.
public func glossaryIssues(
    in doc: SubtitleDocument,
    entries: [GlossaryEntry],
    translationSelector: (Cue) -> String? = { $0.translation }
) -> [TermIssue] {
    let usable = entries.filter { !$0.source.trimmed().isEmpty && !$0.target.trimmed().isEmpty }
    guard !usable.isEmpty else { return [] }
    let cues = sortedCues(doc.cues)

    return usable.compactMap { entry -> TermIssue? in
        let source = entry.source.lowercased()
        let target = entry.target.lowercased()
        var misses = 0
        var firstMiss: String?
        for cue in cues {
            guard cue.text.lowercased().contains(source) else { continue }
            // Untranslated cues aren't glossary violations — see above.
            let translation = (translationSelector(cue) ?? "").trimmed()
            guard !translation.isEmpty else { continue }
            if !translation.lowercased().contains(target) {
                misses += 1
                if firstMiss == nil { firstMiss = cue.id }
            }
        }
        guard misses > 0, let firstMiss else { return nil }
        return TermIssue(
            kind: .glossaryMismatch(expected: entry.target),
            source: entry.source,
            occurrences: misses,
            firstCueId: firstMiss
        )
    }
    .sorted { $0.occurrences != $1.occurrences ? $0.occurrences > $1.occurrences : $0.source < $1.source }
}

/// Both checks, worst-first.
public func checkTranslationConsistency(
    _ doc: SubtitleDocument,
    glossary: [GlossaryEntry],
    checkDivergent: Bool = true,
    translationSelector: (Cue) -> String? = { $0.translation }
) -> [TermIssue] {
    var out = glossaryIssues(in: doc, entries: glossary, translationSelector: translationSelector)
    if checkDivergent { out += divergentTranslations(in: doc, translationSelector: translationSelector) }
    return out
}
