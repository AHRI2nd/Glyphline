import Testing
@testable import GlyphlineCore

@Suite("Glyph")
struct GlyphTests {
    @Test("full document round-trips losslessly (tokens, translation, meta, styles)")
    func roundTrip() throws {
        var doc = SubtitleDocument.empty(.vtt)
        doc.meta = ["vttPreamble": "WEBVTT"]
        doc.styles = [AssStyle(name: "Default")]
        doc.cues = [
            Cue(
                id: "cue-1", start: 1, end: 3.5, text: "Hello",
                translation: "안녕",
                tokens: [SyncToken(text: "Hel", start: 1, end: 2), SyncToken(text: "lo", start: 2, end: 3.5)],
                assSpans: [AssSpan(tags: "\\b1", text: "Hello")],
                actor: "NARRATOR"
            ),
        ]
        let doc2 = try parseGlyph(serializeGlyph(doc))
        #expect(doc2 == doc)
    }

    @Test("schemaVersion default when absent")
    func lenientVersion() throws {
        let json = #"{"document":{"format":"srt","cues":[],"meta":{}}}"#
        let doc = try parseGlyph(json)
        #expect(doc.format == .srt)
        #expect(doc.cues.isEmpty)
    }

    @Test("invalid JSON throws")
    func invalid() {
        #expect(throws: GlyphError.self) { _ = try parseGlyph("{ not json") }
    }

    @Test("ignoredWords round-trips losslessly")
    func ignoredWordsRoundTrip() throws {
        var doc = SubtitleDocument.empty(.ass)
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "遊戯")]
        doc.ignoredWords = ["遊戯", "Yuugi"]
        let back = try parseGlyph(serializeGlyph(doc))
        #expect(back == doc)
        #expect(back.ignoredWords == ["遊戯", "Yuugi"])
    }

    @Test("files written before ignoredWords existed still load")
    func backwardCompatible() throws {
        // No "ignoredWords" key at all — the shape every .glyph saved so far has.
        let json = #"{"schemaVersion":1,"document":{"format":"srt","cues":[],"meta":{}}}"#
        let doc = try parseGlyph(json)
        #expect(doc.ignoredWords == nil)
    }

    @Test("an unused ignore list adds no key to the file")
    func nilOmittedFromJSON() throws {
        let doc = SubtitleDocument.empty(.srt)
        #expect(doc.ignoredWords == nil)
        let json = try serializeGlyph(doc)
        #expect(!json.contains("ignoredWords"))
    }
}
