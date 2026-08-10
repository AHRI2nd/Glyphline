// Proofreading for subtitle text. Two independent checks, deliberately kept
// separate because they have very different reliability:
//
//   1. Dictionary check — flags words a spell dictionary doesn't recognize.
//      Backed by macOS's checker via the `SpellDictionary` protocol (injected,
//      so this file stays AppKit-free and testable). Measured behaviour:
//      English is accurate; Korean catches most typos but DOES produce false
//      positives; Japanese is not supported by macOS at all. So this check is
//      presented as "worth a look", never as authoritative — which is also why
//      the ignore list is a first-class feature rather than an afterthought.
//
//   2. Notation-variant check — finds one word spelled two ways in the SAME
//      document (サーバ vs サーバー, Netflix vs netflix). This is a statement of
//      fact about the document, not a guess, so it cannot false-positive. It
//      needs no dictionary and therefore works for Japanese too.
//
// Both collapse their findings BY WORD rather than by location: the useful
// unit of work is "this word is wrong/inconsistent — fix or ignore it
// everywhere", not "here is occurrence 37 of 50".

import Foundation
import NaturalLanguage

public enum CueField: String, Codable, Equatable, Sendable, CaseIterable {
    case text, translation
}

/// UTF-16 offsets, matching what NSSpellChecker reports and what AppKit text
/// APIs consume.
public struct TextSpan: Equatable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// Dictionary backend. The app target supplies an NSSpellChecker-backed
/// implementation; tests supply a deterministic fake.
public protocol SpellDictionary {
    func misspelledSpans(in text: String, language: String) -> [TextSpan]
    func suggestions(for word: String, language: String) -> [String]
}

public struct SpellIssue: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case unknownWord
        /// The other spellings of this same word found elsewhere in the document.
        case notationVariant(others: [String])
    }

    public let word: String
    public let kind: Kind
    public let occurrences: Int
    /// Where "jump to" lands — the first place this word appears.
    public let firstCueId: String
    public let firstField: CueField
    public let firstSpan: TextSpan

    public var id: String {
        switch kind {
        case .unknownWord: return "unknown|\(word)"
        case .notationVariant: return "notation|\(word)"
        }
    }

    public init(
        word: String, kind: Kind, occurrences: Int,
        firstCueId: String, firstField: CueField, firstSpan: TextSpan
    ) {
        self.word = word
        self.kind = kind
        self.occurrences = occurrences
        self.firstCueId = firstCueId
        self.firstField = firstField
        self.firstSpan = firstSpan
    }
}

public struct SpellCheckOptions: Sendable {
    /// BCP-47-ish code the dictionary understands ("ko", "en"). `nil` skips the
    /// dictionary pass for that field — which is what Japanese must do, since
    /// macOS ships no Japanese spelling dictionary.
    public var textLanguage: String?
    public var translationLanguage: String?
    public var checkNotation: Bool
    /// Words the user has told us to leave alone (project list ∪ system dictionary).
    public var ignored: Set<String>

    public init(
        textLanguage: String? = nil,
        translationLanguage: String? = nil,
        checkNotation: Bool = true,
        ignored: Set<String> = []
    ) {
        self.textLanguage = textLanguage
        self.translationLanguage = translationLanguage
        self.checkNotation = checkNotation
        self.ignored = ignored
    }
}

// ── entry point ──────────────────────────────────────────────────────────────

public func checkDocument(
    _ doc: SubtitleDocument,
    dictionary: SpellDictionary?,
    options: SpellCheckOptions,
    translationSelector: @escaping (Cue) -> String? = { $0.translation }
) -> [SpellIssue] {
    let cues = sortedCues(doc.cues)
    var issues: [SpellIssue] = []
    if let dictionary {
        issues += dictionaryIssues(cues, dictionary: dictionary, options: options, translationSelector: translationSelector)
    }
    if options.checkNotation {
        issues += notationIssues(cues, ignored: options.ignored, translationSelector: translationSelector)
    }
    // Most-frequent first: a word misspelled 30 times is the bigger problem.
    return issues.sorted {
        $0.occurrences != $1.occurrences ? $0.occurrences > $1.occurrences : $0.word < $1.word
    }
}

// ── 1. dictionary check ──────────────────────────────────────────────────────

private func dictionaryIssues(
    _ cues: [Cue],
    dictionary: SpellDictionary,
    options: SpellCheckOptions,
    translationSelector: (Cue) -> String?
) -> [SpellIssue] {
    var tally: [String: (count: Int, cueId: String, field: CueField, span: TextSpan)] = [:]

    for cue in cues {
        for (field, language) in [
            (CueField.text, options.textLanguage),
            (CueField.translation, options.translationLanguage),
        ] {
            guard let language else { continue }
            let content = field == .text ? cue.text : (translationSelector(cue) ?? "")
            guard !content.isEmpty else { continue }
            let ns = content as NSString

            for span in dictionary.misspelledSpans(in: content, language: language) {
                guard span.location >= 0, span.length > 0,
                      span.location + span.length <= ns.length else { continue }
                let word = ns.substring(with: NSRange(location: span.location, length: span.length))
                guard !options.ignored.contains(word) else { continue }
                if let existing = tally[word] {
                    tally[word] = (existing.count + 1, existing.cueId, existing.field, existing.span)
                } else {
                    tally[word] = (1, cue.id, field, span)
                }
            }
        }
    }

    return tally.map { word, hit in
        SpellIssue(word: word, kind: .unknownWord, occurrences: hit.count,
                   firstCueId: hit.cueId, firstField: hit.field, firstSpan: hit.span)
    }
}

// ── 2. notation-variant check ────────────────────────────────────────────────

/// Collapses the differences that are pure *notation* rather than different
/// words: full/half width, case, the Japanese long-vowel mark, and joiners
/// (interpunct, hyphen). Two tokens sharing a key are the same word written
/// two ways.
///
/// Deliberately does NOT do edit-distance matching — that would catch typo
/// pairs but also collide genuinely different words (갔다/왔다), destroying the
/// no-false-positive property this check is built around.
public func notationKey(_ token: String) -> String {
    var s = token.precomposedStringWithCompatibilityMapping.lowercased()
    s.removeAll { ch in
        ch == "ー" || ch == "・" || ch == "･" || ch == "-" || ch == "‐" || ch.isWhitespace
    }
    return s
}

private func notationIssues(_ cues: [Cue], ignored: Set<String>, translationSelector: (Cue) -> String?) -> [SpellIssue] {
    struct Sighting {
        var count = 0
        var cueId = ""
        var field = CueField.text
        var span = TextSpan(location: 0, length: 0)
    }
    // key → surface form → where/how often it appears
    var groups: [String: [String: Sighting]] = [:]
    let tokenizer = NLTokenizer(unit: .word)

    for cue in cues {
        for field in CueField.allCases {
            let content = field == .text ? cue.text : (translationSelector(cue) ?? "")
            guard !content.isEmpty else { continue }
            tokenizer.string = content
            let ns = content as NSString

            tokenizer.enumerateTokens(in: content.startIndex..<content.endIndex) { range, _ in
                let surface = String(content[range])
                // Single characters carry no notation signal and would group
                // wildly (every "a", every particle).
                guard surface.count >= 2, !ignored.contains(surface) else { return true }
                let key = notationKey(surface)
                guard key.count >= 2 else { return true }

                var sighting = groups[key]?[surface] ?? Sighting()
                if sighting.count == 0 {
                    let nsRange = NSRange(range, in: content)
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= ns.length else { return true }
                    sighting.cueId = cue.id
                    sighting.field = field
                    sighting.span = TextSpan(location: nsRange.location, length: nsRange.length)
                }
                sighting.count += 1
                groups[key, default: [:]][surface] = sighting
                return true
            }
        }
    }

    var issues: [SpellIssue] = []
    for (_, surfaces) in groups where surfaces.count > 1 {
        let all = surfaces.keys.sorted()
        for (surface, sighting) in surfaces {
            issues.append(SpellIssue(
                word: surface,
                kind: .notationVariant(others: all.filter { $0 != surface }),
                occurrences: sighting.count,
                firstCueId: sighting.cueId,
                firstField: sighting.field,
                firstSpan: sighting.span
            ))
        }
    }
    return issues
}
