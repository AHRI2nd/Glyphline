import Testing
@testable import GlyphlineCore

@Suite("Multi-language translation tracks")
struct MultiLanguageTranslationTests {
    // ── Cue.translationText / setTranslationText ────────────────────────────

    @Test("index 0 always reads/writes the plain translation field")
    func indexZeroIsPrimary() {
        var cue = Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕")
        #expect(cue.translationText(at: 0, languages: []) == "안녕")
        #expect(cue.translationText(at: 0, languages: ["ko", "ja"]) == "안녕") // languages irrelevant for index 0
        cue.setTranslationText("여어", at: 0, languages: ["ko", "ja"])
        #expect(cue.translation == "여어")
        #expect(cue.translations == nil) // untouched
    }

    @Test("index 1+ reads/writes translations[languages[index]]")
    func additionalLanguageSlot() {
        var cue = Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕")
        let languages = ["ko", "ja", "en"]
        cue.setTranslationText("こんにちは", at: 1, languages: languages)
        cue.setTranslationText("hello", at: 2, languages: languages)
        #expect(cue.translationText(at: 1, languages: languages) == "こんにちは")
        #expect(cue.translationText(at: 2, languages: languages) == "hello")
        #expect(cue.translation == "안녕") // primary untouched
        #expect(cue.translations == ["ja": "こんにちは", "en": "hello"])
    }

    @Test("setting an empty/nil string clears the slot")
    func clearingSlot() {
        var cue = Cue(id: "a", start: 0, end: 1, text: "hi", translation: "x", translations: ["ja": "y"])
        cue.setTranslationText("", at: 0, languages: ["ko", "ja"])
        cue.setTranslationText(nil, at: 1, languages: ["ko", "ja"])
        #expect(cue.translation == nil)
        #expect(cue.translations?["ja"] == nil)
    }

    @Test("out-of-range index is a no-op, not a crash")
    func outOfRange() {
        var cue = Cue(id: "a", start: 0, end: 1, text: "hi", translation: "x")
        #expect(cue.translationText(at: 5, languages: ["ko"]) == nil)
        cue.setTranslationText("y", at: 5, languages: ["ko"])
        #expect(cue.translations == nil) // nothing written
    }

    // ── GlossaryEntry.language ───────────────────────────────────────────────

    @Test("a language-tagged entry and an untagged entry for the same source coexist by id")
    func glossaryLanguageIdentity() {
        let universal = GlossaryEntry(source: "鈴木", target: "Suzuki")
        let japanese = GlossaryEntry(source: "鈴木", target: "스즈키", language: "ko")
        #expect(universal.id != japanese.id)
    }

    @Test("translationSelector lets glossaryIssues check any language slot")
    func selectorParameterized() {
        let languages = ["ko", "ja"]
        var doc = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "鈴木さん", translation: "스즈키 씨", translations: ["ja": "鈴木さん、こんにちは"]),
            // cue b's ja translation deliberately drops 鈴木 (replaced with 田中) — the ja miss this test looks for.
            Cue(id: "b", start: 10, end: 11, text: "鈴木は来ない", translation: "즈즈키는 안 와", translations: ["ja": "田中は来ない"]),
        ])
        doc.translationLanguages = languages
        let jaSelector: (Cue) -> String? = { $0.translationText(at: 1, languages: languages) }

        // Primary (index 0, default selector): cue b's ko text "즈즈키" doesn't contain "스즈키".
        let koIssues = glossaryIssues(in: doc, entries: [GlossaryEntry(source: "鈴木", target: "스즈키")])
        #expect(koIssues.count == 1)
        #expect(koIssues[0].firstCueId == "b")

        // ja slot (index 1), checked against a JAPANESE-target glossary entry: same cue "b" misses
        // for a completely different reason (target text itself, not language mismatch), proving the
        // selector actually redirected which text was read rather than silently reading the primary field.
        let jaIssues = glossaryIssues(
            in: doc, entries: [GlossaryEntry(source: "鈴木", target: "鈴木", language: "ja")],
            translationSelector: jaSelector)
        #expect(jaIssues.count == 1)
        #expect(jaIssues[0].firstCueId == "b")
    }

    @Test("checkTranslationConsistency threads the selector through both sub-checks")
    func checkThreadsSelector() {
        let languages = ["ko", "ja"]
        var doc = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "はい", translation: "네", translations: ["ja": "はい、そうです"]),
            Cue(id: "b", start: 10, end: 11, text: "はい", translation: "네", translations: ["ja": "うん"]),
        ])
        doc.translationLanguages = languages
        // Primary (ko) is consistent ("네"/"네"); the ja slot diverges ("はい、そうです" vs "うん").
        #expect(checkTranslationConsistency(doc, glossary: []).isEmpty)
        let jaSelector: (Cue) -> String? = { $0.translationText(at: 1, languages: languages) }
        let jaResult = checkTranslationConsistency(doc, glossary: [], translationSelector: jaSelector)
        #expect(jaResult.count == 1)
        if case .divergentTranslation = jaResult[0].kind {} else { Issue.record("expected divergentTranslation") }
    }

    // ── DocumentModel.exportContent(translationIndex:) ──────────────────────

    @Test("translationIndex 0 is unchanged from today's single-language export")
    func exportPrimaryUnchanged() {
        let doc = DocumentModel(doc: SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕"),
        ]))
        let out = doc.exportContent(format: .srt, source: .translation)
        #expect(out.contains("안녕"))
    }

    @Test("translationIndex 1 exports the additional language, not the primary")
    func exportAdditionalLanguage() {
        var sd = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕", translations: ["ja": "こんにちは"]),
        ])
        sd.translationLanguages = ["ko", "ja"]
        let doc = DocumentModel(doc: sd)
        let out = doc.exportContent(format: .srt, source: .translation, translationIndex: 1)
        #expect(out.contains("こんにちは"))
        #expect(!out.contains("안녕"))
    }

    // ── DocumentModel language management ────────────────────────────────────

    @Test("adding the first additional language bootstraps translationLanguages with the primary code")
    func addFirstLanguageBootstraps() {
        let doc = DocumentModel(doc: SubtitleDocument(format: .srt, cues: []))
        #expect(doc.doc.translationLanguages == nil)
        doc.addTranslationLanguage("ja", primaryLanguageCode: "ko")
        #expect(doc.doc.translationLanguages == ["ko", "ja"])
    }

    @Test("adding a duplicate language code is a no-op")
    func addDuplicateIsNoOp() {
        let doc = DocumentModel(doc: SubtitleDocument(format: .srt, cues: []))
        doc.addTranslationLanguage("ja", primaryLanguageCode: "ko")
        doc.addTranslationLanguage("ja")
        #expect(doc.doc.translationLanguages == ["ko", "ja"])
    }

    @Test("removing index 0 is refused — the primary language always exists")
    func removePrimaryRefused() {
        let doc = DocumentModel(doc: SubtitleDocument(format: .srt, cues: []))
        doc.addTranslationLanguage("ja", primaryLanguageCode: "ko")
        doc.removeTranslationLanguage(at: 0)
        #expect(doc.doc.translationLanguages == ["ko", "ja"])
    }

    @Test("removing a language clears it from every cue's translations dict")
    func removeLanguageClearsCueData() {
        var sd = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕", translations: ["ja": "こんにちは"]),
        ])
        sd.translationLanguages = ["ko", "ja"]
        let doc = DocumentModel(doc: sd)
        doc.removeTranslationLanguage(at: 1)
        #expect(doc.doc.translationLanguages == ["ko"])
        #expect(doc.doc.cues[0].translations?["ja"] == nil)
        #expect(doc.doc.cues[0].translation == "안녕") // primary untouched
    }

    @Test("removing the active language resets activeTranslationLanguageIndex to 0")
    func removeActiveLanguageResetsIndex() {
        var sd = SubtitleDocument(format: .srt, cues: [])
        sd.translationLanguages = ["ko", "ja"]
        let doc = DocumentModel(doc: sd)
        doc.activeTranslationLanguageIndex = 1
        doc.removeTranslationLanguage(at: 1)
        #expect(doc.activeTranslationLanguageIndex == 0)
    }

    @Test("language management is undoable")
    func languageChangesAreUndoable() {
        let doc = DocumentModel(doc: SubtitleDocument(format: .srt, cues: []))
        doc.addTranslationLanguage("ja", primaryLanguageCode: "ko")
        #expect(doc.canUndo)
        doc.undo()
        #expect(doc.doc.translationLanguages == nil)
    }

    // ── Backward compatibility: old .glyph JSON (no new fields) decodes fine ──

    @Test("a .glyph document written before this feature decodes with nil translations/translationLanguages")
    func legacyGlyphDecodesUnchanged() throws {
        let legacy = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕"),
        ])
        let json = try serializeGlyph(legacy)
        #expect(!json.contains("translationLanguages"))
        #expect(!json.contains("\"translations\""))
        let decoded = try parseGlyph(json)
        #expect(decoded.translationLanguages == nil)
        #expect(decoded.cues[0].translations == nil)
        #expect(decoded.cues[0].translation == "안녕") // legacy field untouched
    }

    @Test("multi-language document round-trips through .glyph losslessly")
    func multiLanguageGlyphRoundTrip() throws {
        var sd = SubtitleDocument(format: .srt, cues: [
            Cue(id: "a", start: 0, end: 1, text: "hi", translation: "안녕", translations: ["ja": "こんにちは", "en": "hello"]),
        ])
        sd.translationLanguages = ["ko", "ja", "en"]
        let decoded = try parseGlyph(try serializeGlyph(sd))
        #expect(decoded.translationLanguages == ["ko", "ja", "en"])
        #expect(decoded.cues[0].translations == ["ja": "こんにちは", "en": "hello"])
    }
}
