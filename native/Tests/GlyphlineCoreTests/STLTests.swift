import Testing
import Foundation
@testable import GlyphlineCore

/// A minimal, valid EBU-STL file (1024-byte GSI + two 128-byte TTI blocks)
/// built INDEPENDENTLY in Python (struct-packed field by field against the
/// spec, not via this Swift code) — see the generation script in the PR/task
/// notes. Cross-checking against a second, independent implementation of the
/// same spec catches transcription mistakes a Swift-only round-trip test
/// can't: a bug present in both the encoder and decoder here would pass a
/// pure round trip while still producing files no other tool can read.
private let referenceSTLBase64 = """
NDM3U1RMMjUuMDExMDAwOVRlc3QgUHJvZ3JhbW1lICAgICAgICAgICAgICAgICAgRXBpc29kZSAxICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAyNDAxMDEyNDAxMDIwMTAwMDAyMDAwMDIwMDE0MDIzMTAwMDAwMDAwMDAwMDAxMDAxMVVTQSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAAAAP8AAAABAAAAAwAUAgBIZWxsbyB3b3JsZI+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+PAAEA/wAAAAUAAAAHDBQCAFNlY29uZCBsaW5lIG9uZYpTZWNvbmQgbGluZSB0d2+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj4+Pj48=
"""

@Suite("EBU-STL: golden byte reference (Python-generated)")
struct STLGoldenReferenceTests {
    private func referenceDoc() -> SubtitleDocument {
        let data = Data(base64Encoded: referenceSTLBase64.replacingOccurrences(of: "\n", with: ""))!
        #expect(data.count == 1280)
        let raw = bytesToLatin1String([UInt8](data))
        return parseStl(raw)
    }

    @Test("parses the declared frame rate from DFC")
    func parsesFrameRate() {
        #expect(referenceDoc().frameRate == 25)
    }

    @Test("parses GSI free-text fields")
    func parsesGSIFields() {
        let doc = referenceDoc()
        #expect(doc.meta["stlOPT"] == "Test Programme")
        #expect(doc.meta["stlOET"] == "Episode 1")
        #expect(doc.meta["stlCO"] == "USA")
        #expect(doc.meta["stlCD"] == "240101")
        #expect(doc.meta["stlRD"] == "240102")
    }

    @Test("parses two cues at the expected times and text")
    func parsesCues() {
        let doc = referenceDoc()
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].text == "Hello world")
        #expect(doc.cues[0].start == 1.0)   // 00:00:01:00 @ 25fps
        #expect(doc.cues[0].end == 3.0)     // 00:00:03:00
        #expect(doc.cues[1].text == "Second line one\nSecond line two") // 0x8A → \n
        #expect(doc.cues[1].start == 5.0)
        #expect(abs(doc.cues[1].end - 7.48) < 1e-9) // 00:00:07:12 @ 25fps = 7 + 12/25
    }

    @Test("padding bytes (0x8F) don't leak into the decoded text")
    func stripsPadding() {
        let doc = referenceDoc()
        #expect(!doc.cues[0].text.contains("\u{8F}"))
    }
}

@Suite("EBU-STL: round trip")
struct STLRoundTripTests {
    @Test("plain ASCII text round-trips exactly")
    func plainText() {
        var doc = SubtitleDocument(format: .stl)
        doc.frameRate = 25
        doc.cues = [
            Cue(id: "a", start: 1, end: 3, text: "Hello world"),
            Cue(id: "b", start: 5, end: 7.48, text: "Second line one\nSecond line two"),
        ]
        let out = parseStl(serializeStl(doc))
        #expect(out.cues.count == 2)
        #expect(out.cues[0].text == "Hello world")
        #expect(out.cues[1].text == "Second line one\nSecond line two")
        #expect(abs(out.cues[0].start - 1) < 1.0 / 25)
        #expect(abs(out.cues[1].end - 7.48) < 1.0 / 25)
    }

    @Test("accented Latin characters round-trip via the diacritic mechanism")
    func accentedText() {
        var doc = SubtitleDocument(format: .stl)
        doc.frameRate = 25
        doc.cues = [Cue(id: "a", start: 0, end: 2, text: "café à Zürich, garçon")]
        let out = parseStl(serializeStl(doc))
        #expect(out.cues[0].text == "café à Zürich, garçon")
    }

    @Test("30fps DFC round-trips as 30")
    func thirtyFps() {
        var doc = SubtitleDocument(format: .stl)
        doc.frameRate = 30
        doc.cues = [Cue(id: "a", start: 1, end: 2, text: "hi")]
        let out = parseStl(serializeStl(doc))
        #expect(out.frameRate == 30)
    }

    @Test("25fps is the default when frameRate is unset")
    func defaultsTo25() {
        var doc = SubtitleDocument(format: .stl)
        doc.cues = [Cue(id: "a", start: 1, end: 2, text: "hi")]
        let out = parseStl(serializeStl(doc))
        #expect(out.frameRate == 25)
    }

    @Test("GSI free-text fields round-trip through meta")
    func gsiFieldsRoundTrip() {
        var doc = SubtitleDocument(format: .stl)
        doc.meta["stlOPT"] = "My Show"
        doc.meta["stlCO"] = "KOR"
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "x")]
        let out = parseStl(serializeStl(doc))
        #expect(out.meta["stlOPT"] == "My Show")
        #expect(out.meta["stlCO"] == "KOR")
    }

    @Test("VP/JC/CS/CF cue metadata round-trips via cue.raw")
    func perCueMetadataRoundTrips() {
        var doc = SubtitleDocument(format: .stl)
        var cue = Cue(id: "a", start: 0, end: 1, text: "x")
        cue.raw = ["stlVP": "15", "stlJC": "1", "stlCS": "0", "stlCF": "0", "stlSGN": "0"]
        doc.cues = [cue]
        let out = parseStl(serializeStl(doc))
        #expect(out.cues[0].raw?["stlVP"] == "15")
        #expect(out.cues[0].raw?["stlJC"] == "1")
    }

    @Test("an empty document serializes to exactly one GSI block (1024 bytes)")
    func emptyDocument() {
        let bytes = latin1StringToBytes(serializeStl(SubtitleDocument(format: .stl)))
        #expect(bytes.count == 1024)
    }

    @Test("N cues serialize to GSI + N × 128-byte TTI blocks")
    func exactByteLength() {
        var doc = SubtitleDocument(format: .stl)
        doc.cues = (0..<5).map { Cue(id: "\($0)", start: Double($0), end: Double($0) + 0.5, text: "line \($0)") }
        let bytes = latin1StringToBytes(serializeStl(doc))
        #expect(bytes.count == 1024 + 5 * 128)
    }

    @Test("cues round-trip in time order regardless of input order")
    func sortsOnSerialize() {
        var doc = SubtitleDocument(format: .stl)
        doc.cues = [
            Cue(id: "b", start: 5, end: 6, text: "second"),
            Cue(id: "a", start: 1, end: 2, text: "first"),
        ]
        let out = parseStl(serializeStl(doc))
        #expect(out.cues.map(\.text) == ["first", "second"])
    }
}

@Suite("EBU-STL: ISO 6937 text codec")
struct ISO6937Tests {
    @Test("ASCII passes through unchanged")
    func asciiPassthrough() {
        #expect(iso6937Decode(Array("Hello, World! 123".utf8)) == "Hello, World! 123")
    }

    @Test("acute accent combines with the following base letter")
    func acuteAccent() {
        #expect(iso6937Decode([0xC2, UInt8(ascii: "e")]) == "é")
    }

    @Test("grave, circumflex, tilde, diaeresis, ring, cedilla all decode")
    func allSupportedDiacritics() {
        #expect(iso6937Decode([0xC1, UInt8(ascii: "a")]) == "à")
        #expect(iso6937Decode([0xC3, UInt8(ascii: "e")]) == "ê")
        #expect(iso6937Decode([0xC4, UInt8(ascii: "n")]) == "ñ")
        #expect(iso6937Decode([0xC8, UInt8(ascii: "u")]) == "ü")
        #expect(iso6937Decode([0xCA, UInt8(ascii: "a")]) == "å")
        #expect(iso6937Decode([0xCB, UInt8(ascii: "c")]) == "ç")
    }

    @Test("0x8A decodes to a row break")
    func rowBreak() {
        #expect(iso6937Decode([UInt8(ascii: "a"), 0x8A, UInt8(ascii: "b")]) == "a\nb")
    }

    @Test("0x8F padding truncates the rest of the field")
    func paddingTruncates() {
        #expect(iso6937Decode([UInt8(ascii: "h"), UInt8(ascii: "i"), 0x8F, UInt8(ascii: "X")]) == "hi")
    }

    @Test("encode then decode round-trips supported text")
    func roundTrip() {
        let text = "café\nà Zürich"
        let encoded = iso6937Encode(text, width: 112)
        #expect(iso6937Decode(encoded) == text)
    }

    @Test("encode truncates text longer than the field width")
    func encodeTruncates() {
        let encoded = iso6937Encode(String(repeating: "x", count: 200), width: 112)
        #expect(encoded.count == 112)
    }
}
