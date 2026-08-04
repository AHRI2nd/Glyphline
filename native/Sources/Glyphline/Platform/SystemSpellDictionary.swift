// NSSpellChecker-backed SpellDictionary. Lives in the app target so
// GlyphlineCore stays free of AppKit and testable against a fake.
//
// Measured behaviour of macOS's dictionaries (see SpellCheck.swift's header):
// English is reliable; Korean flags most typos but also some correct words;
// Japanese is absent from `availableLanguages` entirely. `isSupported` lets
// the UI say so plainly rather than silently returning nothing.

import AppKit
import GlyphlineCore

@MainActor
struct SystemSpellDictionary: SpellDictionary {
    /// One tag per document scope so "ignore for now" state doesn't leak
    /// between checks.
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()

    static func isSupported(_ language: String) -> Bool {
        NSSpellChecker.shared.availableLanguages.contains(language)
    }

    /// The macOS spelling languages we surface, in menu order. Filtered to
    /// what this machine actually has, so the picker can't offer a language
    /// that would silently return nothing.
    static var supportedLanguages: [String] {
        ["ko", "en"].filter(isSupported)
    }

    nonisolated func misspelledSpans(in text: String, language: String) -> [TextSpan] {
        let checker = NSSpellChecker.shared
        let ns = text as NSString
        var spans: [TextSpan] = []
        var offset = 0
        while offset < ns.length {
            let range = checker.checkSpelling(
                of: text, startingAt: offset, language: language,
                wrap: false, inSpellDocumentWithTag: tag, wordCount: nil
            )
            guard range.location != NSNotFound, range.length > 0 else { break }
            spans.append(TextSpan(location: range.location, length: range.length))
            offset = range.location + range.length
        }
        return spans
    }

    nonisolated func suggestions(for word: String, language: String) -> [String] {
        NSSpellChecker.shared.guesses(
            forWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word, language: language, inSpellDocumentWithTag: tag
        ) ?? []
    }

    /// Adds to the user's system-wide macOS dictionary — the right home for a
    /// word that's correct everywhere ("Netflix"), as opposed to one that's
    /// only correct in this project (a character's name), which belongs in the
    /// document's own ignore list.
    nonisolated func learn(_ word: String) {
        NSSpellChecker.shared.learnWord(word)
    }

    nonisolated func hasLearned(_ word: String) -> Bool {
        NSSpellChecker.shared.hasLearnedWord(word)
    }

    nonisolated func unlearn(_ word: String) {
        NSSpellChecker.shared.unlearnWord(word)
    }
}
