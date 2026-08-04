import Testing
import Foundation
@testable import GlyphlineCore

// The dictionary pass is tested against a fake rather than NSSpellChecker:
// the real checker's Korean results are inconsistent (measured: it flags the
// correct "반갑습니다" and misses the typo "날시"), so asserting against it
// would be testing macOS, not our code — and would break whenever Apple
// changes its dictionaries.
private struct FakeDictionary: SpellDictionary {
    /// Exact words to treat as misspelled.
    var bad: Set<String>
    var guesses: [String: [String]] = [:]

    func misspelledSpans(in text: String, language: String) -> [TextSpan] {
        let ns = text as NSString
        var out: [TextSpan] = []
        // Naive whitespace tokenizer — enough to locate the planted words.
        var index = 0
        for piece in text.components(separatedBy: " ") {
            let len = (piece as NSString).length
            if bad.contains(piece) { out.append(TextSpan(location: index, length: len)) }
            index += len + 1
        }
        _ = ns
        return out
    }

    func suggestions(for word: String, language: String) -> [String] { guesses[word] ?? [] }
}

private func cue(_ id: String, _ text: String, translation: String? = nil, at start: Double = 0) -> Cue {
    Cue(id: id, start: start, end: start + 1, text: text, translation: translation)
}

@Suite("SpellCheck: dictionary pass")
struct SpellCheckDictionaryTests {
    @Test("flags unknown words and counts every occurrence")
    func countsOccurrences() {
        let doc = SubtitleDocument(cues: [
            cue("a", "hello wrng", at: 0),
            cue("b", "wrng again", at: 1),
            cue("c", "all fine here", at: 2),
        ])
        let issues = checkDocument(doc, dictionary: FakeDictionary(bad: ["wrng"]),
                                   options: SpellCheckOptions(textLanguage: "en", checkNotation: false))
        #expect(issues.count == 1)
        #expect(issues[0].word == "wrng")
        #expect(issues[0].occurrences == 2)
        #expect(issues[0].firstCueId == "a") // jump target is the first sighting
        #expect(issues[0].kind == .unknownWord)
    }

    @Test("ignored words are dropped entirely")
    func ignoreList() {
        let doc = SubtitleDocument(cues: [cue("a", "Yuugi wrng")])
        let dict = FakeDictionary(bad: ["Yuugi", "wrng"])
        let all = checkDocument(doc, dictionary: dict,
                               options: SpellCheckOptions(textLanguage: "en", checkNotation: false))
        #expect(all.count == 2)

        let filtered = checkDocument(doc, dictionary: dict,
                                     options: SpellCheckOptions(textLanguage: "en", checkNotation: false,
                                                                ignored: ["Yuugi"]))
        #expect(filtered.map(\.word) == ["wrng"])
    }

    @Test("a nil language skips that field — Japanese has no macOS dictionary")
    func nilLanguageSkipsField() {
        let doc = SubtitleDocument(cues: [cue("a", "wrng", translation: "wrng")])
        let dict = FakeDictionary(bad: ["wrng"])
        // Only the translation is checked; the (Japanese) source is skipped.
        let issues = checkDocument(doc, dictionary: dict,
                                   options: SpellCheckOptions(textLanguage: nil, translationLanguage: "ko",
                                                              checkNotation: false))
        #expect(issues.count == 1)
        #expect(issues[0].occurrences == 1)
        #expect(issues[0].firstField == .translation)
    }

    @Test("no dictionary means no dictionary issues")
    func noDictionary() {
        let doc = SubtitleDocument(cues: [cue("a", "wrng")])
        let issues = checkDocument(doc, dictionary: nil,
                                   options: SpellCheckOptions(textLanguage: "en", checkNotation: false))
        #expect(issues.isEmpty)
    }

    @Test("results are ordered by frequency, worst first")
    func ordering() {
        let doc = SubtitleDocument(cues: [
            cue("a", "aaa bbb", at: 0),
            cue("b", "bbb", at: 1),
            cue("c", "bbb", at: 2),
        ])
        let issues = checkDocument(doc, dictionary: FakeDictionary(bad: ["aaa", "bbb"]),
                                   options: SpellCheckOptions(textLanguage: "en", checkNotation: false))
        #expect(issues.map(\.word) == ["bbb", "aaa"])
    }
}

@Suite("SpellCheck: notation variants")
struct SpellCheckNotationTests {
    @Test("Japanese long-vowel variants of one word are paired")
    func japaneseLongVowel() {
        let doc = SubtitleDocument(cues: [
            cue("a", "サーバーに接続します", at: 0),
            cue("b", "サーバに接続します", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        let words = Set(issues.map(\.word))
        #expect(words.contains("サーバー"))
        #expect(words.contains("サーバ"))

        let server = issues.first { $0.word == "サーバ" }
        #expect(server?.kind == .notationVariant(others: ["サーバー"]))
    }

    @Test("case-only differences in Latin text are flagged")
    func caseVariants() {
        let doc = SubtitleDocument(cues: [
            cue("a", "watch Netflix tonight", at: 0),
            cue("b", "watch netflix again", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        #expect(Set(issues.map(\.word)) == ["Netflix", "netflix"])
    }

    @Test("a consistently spelled document produces nothing")
    func consistentDocIsClean() {
        let doc = SubtitleDocument(cues: [
            cue("a", "サーバーに接続します", at: 0),
            cue("b", "サーバーを再起動します", at: 1),
            cue("c", "안녕하세요 반갑습니다", at: 2),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        #expect(issues.isEmpty)
    }

    @Test("different words are never grouped just for being similar")
    func noEditDistanceGrouping() {
        // 갔다/왔다 differ by one character. Edit-distance matching would pair
        // them; notation keys must not.
        let doc = SubtitleDocument(cues: [
            cue("a", "그는 갔다", at: 0),
            cue("b", "그는 왔다", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        #expect(issues.isEmpty)
    }

    @Test("variants are counted and point at their own first sighting")
    func variantCounts() {
        let doc = SubtitleDocument(cues: [
            cue("a", "サーバー です", at: 0),
            cue("b", "サーバー です", at: 1),
            cue("c", "サーバ です", at: 2),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        let major = issues.first { $0.word == "サーバー" }
        let minor = issues.first { $0.word == "サーバ" }
        #expect(major?.occurrences == 2)
        #expect(major?.firstCueId == "a")
        #expect(minor?.occurrences == 1)
        #expect(minor?.firstCueId == "c") // the odd one out, which is what you'd fix
    }

    @Test("notation check reads the translation column too")
    func checksTranslationField() {
        let doc = SubtitleDocument(cues: [
            cue("a", "x", translation: "サーバー 연결", at: 0),
            cue("b", "y", translation: "サーバ 연결", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        #expect(Set(issues.map(\.word)).isSuperset(of: ["サーバー", "サーバ"]))
        #expect(issues.first { $0.word == "サーバ" }?.firstField == .translation)
    }

    @Test("ignored words are excluded from notation grouping")
    func ignoredExcluded() {
        let doc = SubtitleDocument(cues: [
            cue("a", "サーバー です", at: 0),
            cue("b", "サーバ です", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil,
                                   options: SpellCheckOptions(checkNotation: true, ignored: ["サーバ"]))
        // With one side ignored the pair is no longer a pair.
        #expect(issues.isEmpty)
    }

    @Test("spans locate the word inside its cue field")
    func spanAccuracy() {
        let doc = SubtitleDocument(cues: [
            cue("a", "abc Netflix", at: 0),
            cue("b", "netflix", at: 1),
        ])
        let issues = checkDocument(doc, dictionary: nil, options: SpellCheckOptions(checkNotation: true))
        let hit = issues.first { $0.word == "Netflix" }
        #expect(hit != nil)
        let text = "abc Netflix" as NSString
        let span = hit!.firstSpan
        #expect(text.substring(with: NSRange(location: span.location, length: span.length)) == "Netflix")
    }
}

@Suite("SpellCheck: notationKey")
struct NotationKeyTests {
    @Test("absorbs width, case, long vowels and joiners")
    func normalization() {
        #expect(notationKey("サーバー") == notationKey("サーバ"))
        #expect(notationKey("Netflix") == notationKey("netflix"))
        #expect(notationKey("e-mail") == notationKey("email"))
        #expect(notationKey("ＡＢＣ") == notationKey("abc")) // full-width → half
    }

    @Test("keeps genuinely different words apart")
    func distinctWordsStayDistinct() {
        #expect(notationKey("갔다") != notationKey("왔다"))
        #expect(notationKey("cat") != notationKey("cut"))
    }
}
