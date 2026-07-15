import Testing
import Foundation
@testable import GlyphlineCore

// Baseline model tests — the seed of the "test-vector safety net". Format-adapter
// vectors ported from ../../scripts/roundtrip-test.ts land here as adapters are
// ported (M1).

@Suite("Model")
struct ModelTests {
    @Test("empty document")
    func emptyDoc() {
        let doc = SubtitleDocument.empty()
        #expect(doc.format == .srt)
        #expect(doc.cues.isEmpty)
        #expect(doc.meta.isEmpty)
    }

    @Test("cue round-trips through .glyph JSON losslessly")
    func cueRoundTrip() throws {
        let cue = Cue(
            id: "cue-1",
            start: 1.0,
            end: 3.5,
            text: "Hello\nsecond line",
            translation: "안녕\n둘째 줄",
            tokens: [SyncToken(text: "Hello", start: 1.0, end: 2.0)]
        )
        var doc = SubtitleDocument.empty()
        doc.cues = [cue]

        let data = try JSONEncoder().encode(GlyphFile(document: doc))
        let back = try JSONDecoder().decode(GlyphFile.self, from: data)
        #expect(back.document == doc)
        #expect(back.schemaVersion == GLYPH_SCHEMA_VERSION)
    }

    @Test("nil optionals are omitted from JSON (matches TS .glyph shape)")
    func omitsNilOptionals() throws {
        let cue = Cue(id: "cue-1", start: 0, end: 2, text: "x")
        let json = String(data: try JSONEncoder().encode(cue), encoding: .utf8)!
        #expect(!json.contains("translation"))
        #expect(!json.contains("tokens"))
        #expect(!json.contains("assSpans"))
        #expect(json.contains("\"text\""))
    }

    @Test("newCueId is unique and prefixed")
    func cueIds() {
        let a = newCueId()
        let b = newCueId()
        #expect(a != b)
        #expect(a.hasPrefix("cue-"))
    }
}
