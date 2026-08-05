import Testing
@testable import GlyphlineCore

@Suite("Translation consistency")
struct TermConsistencyTests {
    private func cue(_ id: String, _ start: Double, _ text: String, _ translation: String? = nil) -> Cue {
        Cue(id: id, start: start, end: start + 1, text: text, translation: translation)
    }
    private func doc(_ cues: [Cue]) -> SubtitleDocument {
        SubtitleDocument(format: .srt, cues: cues)
    }

    // ── repeated source, divergent translation ──────────────────────────────

    @Test("same source translated two ways is flagged")
    func divergent() {
        let d = doc([
            cue("a", 0, "ありがとう", "고마워"),
            cue("b", 10, "ありがとう", "감사합니다"),
        ])
        let issues = divergentTranslations(in: d)
        #expect(issues.count == 1)
        #expect(issues[0].source == "ありがとう")
        if case .divergentTranslation(let variants) = issues[0].kind {
            #expect(Set(variants) == ["고마워", "감사합니다"])
        } else {
            Issue.record("wrong kind")
        }
    }

    @Test("consistent repeats are not flagged")
    func consistent() {
        let d = doc([
            cue("a", 0, "ありがとう", "고마워"),
            cue("b", 10, "ありがとう", "고마워"),
            cue("c", 20, "はい", "네"),
        ])
        #expect(divergentTranslations(in: d).isEmpty)
    }

    @Test("differences in line wrapping alone are not a divergence")
    func wrapping() {
        let d = doc([
            cue("a", 0, "おはよう\nございます", "안녕하세요"),
            cue("b", 10, "おはよう ございます", "안녕하세요"),
        ])
        #expect(divergentTranslations(in: d).isEmpty)
    }

    @Test("untranslated cues are skipped, not treated as a variant")
    func untranslated() {
        let d = doc([
            cue("a", 0, "ありがとう", "고마워"),
            cue("b", 10, "ありがとう", ""),
            cue("c", 20, "ありがとう", nil),
        ])
        // Only one actual translation exists, so there is nothing inconsistent.
        #expect(divergentTranslations(in: d).isEmpty)
    }

    @Test("a source line appearing once is never flagged")
    func single() {
        #expect(divergentTranslations(in: doc([cue("a", 0, "ありがとう", "고마워")])).isEmpty)
    }

    // ── glossary ────────────────────────────────────────────────────────────

    @Test("glossary term missing from the translation is flagged")
    func glossaryMiss() {
        let d = doc([
            cue("a", 0, "鈴木さん、こんにちは", "스즈키 씨, 안녕하세요"),
            cue("b", 10, "鈴木は来ない", "즈즈키는 안 와"),
        ])
        let issues = glossaryIssues(in: d, entries: [GlossaryEntry(source: "鈴木", target: "스즈키")])
        #expect(issues.count == 1)
        #expect(issues[0].occurrences == 1)
        #expect(issues[0].firstCueId == "b")
        if case .glossaryMismatch(let expected) = issues[0].kind {
            #expect(expected == "스즈키")
        } else {
            Issue.record("wrong kind")
        }
    }

    @Test("a fully consistent glossary term produces nothing")
    func glossaryClean() {
        let d = doc([
            cue("a", 0, "鈴木さん", "스즈키 씨"),
            cue("b", 10, "鈴木は来ない", "스즈키는 안 와"),
        ])
        #expect(glossaryIssues(in: d, entries: [GlossaryEntry(source: "鈴木", target: "스즈키")]).isEmpty)
    }

    @Test("cues without the term, and untranslated cues, are ignored")
    func glossaryScope() {
        let d = doc([
            cue("a", 0, "こんにちは", "안녕하세요"),   // term absent
            cue("b", 10, "鈴木さん", ""),              // not translated yet
        ])
        #expect(glossaryIssues(in: d, entries: [GlossaryEntry(source: "鈴木", target: "스즈키")]).isEmpty)
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        let d = doc([cue("a", 0, "NETFLIX original", "넷플릭스 오리지널")])
        #expect(glossaryIssues(in: d, entries: [GlossaryEntry(source: "netflix", target: "넷플릭스")]).isEmpty)
    }

    @Test("blank glossary rows are skipped rather than matching everything")
    func blankEntries() {
        let d = doc([cue("a", 0, "何か", "뭔가")])
        let entries = [
            GlossaryEntry(source: "", target: "x"),
            GlossaryEntry(source: "y", target: "  "),
        ]
        #expect(glossaryIssues(in: d, entries: entries).isEmpty)
    }

    @Test("combined check reports both kinds, worst first")
    func combined() {
        let d = doc([
            cue("a", 0, "鈴木", "즈즈키"),
            cue("b", 10, "鈴木", "즈즈키"),
            cue("c", 20, "はい", "네"),
            cue("d", 30, "はい", "예"),
        ])
        let issues = checkTranslationConsistency(
            d, glossary: [GlossaryEntry(source: "鈴木", target: "스즈키")]
        )
        #expect(issues.count == 2)
        // 2 glossary misses outrank the 2-variant divergence tie-break by name.
        #expect(issues.contains { if case .glossaryMismatch = $0.kind { return true }; return false })
        #expect(issues.contains { if case .divergentTranslation = $0.kind { return true }; return false })
    }

    @Test("glossary round-trips through .glyph and is absent when unused")
    func persistence() throws {
        var d = doc([cue("a", 0, "鈴木", "스즈키")])
        d.glossary = [GlossaryEntry(source: "鈴木", target: "스즈키", note: "주인공")]
        let decoded = try parseGlyph(try serializeGlyph(d))
        #expect(decoded.glossary?.count == 1)
        #expect(decoded.glossary?[0].target == "스즈키")
        #expect(decoded.glossary?[0].note == "주인공")

        let plain = doc([cue("a", 0, "x", "y")])
        #expect(!(try serializeGlyph(plain)).contains("glossary"))
        // Files written before this feature existed still decode.
        #expect(try parseGlyph(try serializeGlyph(plain)).glossary == nil)
    }
}
