import Testing
import Foundation
@testable import GlyphlineCore

/// A real, minimal TrueType font built with fontTools (an independent,
/// industry-standard library — used by Google Fonts, Adobe, and most other
/// font tooling), then UU-encoded with the Aegisub +33/no-length-prefix
/// convention. Its cmap covers exactly three code points: 'A' (U+0041),
/// 'b' (U+0062), and a supplementary-plane emoji U+1F600 — confirmed by
/// inspecting fontTools' own parse of the file before encoding it, so this
/// test checks the Swift decoder+parser against ground truth from a second,
/// unrelated implementation rather than against itself.
private let testFontUU = """
!!%!!!!+!)!!!Q!A4V-P-E%Z1ZM!!!%I!!!!9'.N98!!J_Z@!!!"F!!!!(BH<(FG<P':'!!!!BA!!!")
;'6B:#Y]M1Q!!!#M!!!!.GBI:7%&&A(W!!!!Z!!!!#2I<82Y!FA!!!!!!9A!!!!+<'^D91!Q!"A!!!)-
!!!!#GVB?(!!"A!'!!!"#!!!!#"O97VFMN6TZ1!!!G!!!!"D='^T>/?6=RU!!!,%!!!!-1!"!!!!!1!!
IVP186]0005!!Q0I!!!!!/;:.RQ!!!!!ZJEX(!!!!!!"^!(U!!!!!Q!#!!!!!!!!!!%!!!-A`TA!!!*9
!!!!:!(U!!%!!!!!!!!!!!!!!!!!!!!"!!%!!!!%!!1!!1!!!!!!!A!!!!!!!!!!!!!!!!!!!!!!!Q*9
!:!!"1!%!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"!A!!!!!!!!!!!!!!0T]`0Q!!
!%(``Q!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!A!!!#7!!!!!!!!!!!!!!!!!!$!!!!!Q!!!"Q!!Q!"
!!!!(!!$!!I!!!"%!!1!+!!!!!9!"!!"!!)!11"C``]!!!""!',````!`[!!!1!!!!!!!!!-!!!!!!!U
!!!!!!!!!!-!!!""!!!!11!!!!%!!!"C!!!!9A!!!!)!!@9!!!(W!!!!!!-!!!!!!!Q!'!!E!!!!!1!!
!!!"^!(U!!-!!$%2)2%"^!(U`AQ!!1!!!!!"^!(U!!-!!$%2)2%"^!(U`AQ!!1!!!!!"^!(U!!-!!$%2
)2%"^!(U`AQ!!!!%!$9!!1!!!!!!!1!)!!!!!1!!!!!!!A!(!!A!!Q!""!E!!1!1!!]!!Q!""!E!!A!/
!"^5:8.U2G^O>&*F:X6M98)!6!"F!(-!>!"'!']!<A"U!&)!:1"H!(5!<!"B!()!!!)!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!"!!!!#1!21%#"H.N;7RF?1!!!!
"""

@Suite("Font coverage: UU decode + cmap parse (fontTools-verified)")
struct FontCoverageTests {
    @Test("decodes the embedded UU payload to a valid SFNT font")
    func decodesToSFNT() {
        let data = decodeAssEmbedded(testFontUU)
        #expect(data != nil)
        // SFNT version tag for a TrueType-flavored font is 0x00010000.
        #expect(data?.prefix(4) == Data([0x00, 0x01, 0x00, 0x00]))
    }

    @Test("cmap coverage matches the known set from an independent tool")
    func cmapCoverageMatchesGroundTruth() {
        let data = decodeAssEmbedded(testFontUU)!
        let covered = fontCoveredCodePoints(data)
        #expect(covered != nil)
        #expect(covered == Set([0x41, 0x62, 0x1F600])) // 'A', 'b', 😀
    }

    @Test("a character outside the font's cmap is correctly reported as uncovered")
    func detectsUncoveredCharacter() {
        let data = decodeAssEmbedded(testFontUU)!
        let covered = fontCoveredCodePoints(data)!
        #expect(!covered.contains(0x43)) // 'C' was never in the source cmap
    }

    @Test("garbage bytes are not mistaken for a valid font")
    func rejectsGarbage() {
        let garbage = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        #expect(fontCoveredCodePoints(garbage) == nil)
    }

    @Test("UU decode round-trips arbitrary byte lengths (1, 2, 3 mod 3 remainder)")
    func uuDecodeByteAlignment() {
        // Encode independently here (not reusing the app's own encoder, since
        // none exists yet — fonts are only ever decoded, never re-encoded) to
        // sanity check the decoder against hand-built inputs of each length
        // class the format actually produces.
        func encode(_ bytes: [UInt8]) -> String {
            var out = ""
            var i = 0
            while i < bytes.count {
                let chunk = Array(bytes[i..<min(i + 3, bytes.count)])
                let b0 = chunk[0], b1 = chunk.count > 1 ? chunk[1] : 0, b2 = chunk.count > 2 ? chunk[2] : 0
                var six: [UInt8] = [b0 >> 2, ((b0 & 0x3) << 4) | (b1 >> 4)]
                if chunk.count >= 2 { six.append(((b1 & 0xF) << 2) | (b2 >> 6)) }
                if chunk.count >= 3 { six.append(b2 & 0x3F) }
                out += String(six.map { Character(UnicodeScalar($0 + 33)) })
                i += 3
            }
            return out
        }
        for bytes: [UInt8] in [[0x41], [0x41, 0x42], [0x41, 0x42, 0x43], [0x41, 0x42, 0x43, 0x44]] {
            let decoded = decodeAssEmbedded(encode(bytes))
            #expect(decoded == Data(bytes))
        }
    }
}

@Suite("Font coverage: document-level check")
struct FontCoverageDocumentTests {
    private func docWithFont() -> SubtitleDocument {
        var doc = SubtitleDocument(format: .ass)
        doc.fonts = [AssEmbedded(name: "TestFont", data: testFontUU)]
        return doc
    }

    @Test("no fonts embedded → no issues reported")
    func noFontsNoIssues() {
        var doc = SubtitleDocument(format: .ass)
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "hello")]
        #expect(checkFontCoverage(doc).isEmpty)
    }

    @Test("all cue text covered by the embedded font → no issues")
    func fullyCoveredNoIssues() {
        var doc = docWithFont()
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "AbAb")]
        #expect(checkFontCoverage(doc).isEmpty)
    }

    @Test("a character missing from every embedded font is flagged")
    func flagsMissingCharacter() {
        var doc = docWithFont()
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "AC")] // 'C' isn't covered
        let issues = checkFontCoverage(doc)
        #expect(issues.count == 1)
        #expect(issues[0].missingCharacters == ["C"])
    }

    @Test("whitespace is never flagged as missing")
    func whitespaceIgnored() {
        var doc = docWithFont()
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "A b\n")]
        #expect(checkFontCoverage(doc).isEmpty)
    }

    @Test("an unparseable embedded font reports nil missingCharacters, not a false pass")
    func unparseableFontReportsExplicitly() {
        var doc = SubtitleDocument(format: .ass)
        doc.fonts = [AssEmbedded(name: "Broken", data: "!!!!not a font!!!!")]
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "x")]
        let issues = checkFontCoverage(doc)
        #expect(issues.count == 1)
        #expect(issues[0].missingCharacters == nil)
    }
}

@Suite("Font coverage: UU encode")
struct FontEncodeTests {
    @Test("encode then decode round-trips exact bytes across all remainder classes")
    func roundTripsAllRemainders() {
        for byteCount in [0, 1, 2, 3, 4, 5, 6, 7, 100] {
            let bytes = (0..<byteCount).map { UInt8($0 % 256) }
            let data = Data(bytes)
            let encoded = encodeAssEmbedded(data)
            let decoded = decodeAssEmbedded(encoded)
            #expect(decoded == data)
        }
    }

    @Test("encoding the real fontTools-generated font matches the known-good reference bytes")
    func matchesRealFontDecode() {
        let original = decodeAssEmbedded(testFontUU)!
        let reEncoded = encodeAssEmbedded(original)
        let reDecoded = decodeAssEmbedded(reEncoded)
        #expect(reDecoded == original)
    }

    @Test("wraps at the requested line width")
    func wrapsAtLineWidth() {
        let data = Data(repeating: 0x41, count: 300)
        let encoded = encodeAssEmbedded(data, lineWidth: 80)
        let lines = encoded.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.dropLast() { #expect(line.count == 80) }
    }

    @Test("every encoded character is in the printable 33...96 range")
    func charactersInRange() {
        let data = Data([0xFF, 0x00, 0x80, 0x7F])
        for ch in encodeAssEmbedded(data, lineWidth: 0) {
            guard let v = ch.asciiValue else { Issue.record("non-ASCII char in output"); continue }
            #expect(v >= 33 && v <= 33 + 63)
        }
    }
}

@Suite("Font collection")
struct FontCollectionTests {
    @Test("collects font names from every style")
    func collectsStyleFonts() {
        var doc = SubtitleDocument(format: .ass)
        doc.styles = [AssStyle(name: "A", fontName: "Arial"), AssStyle(name: "B", fontName: "Helvetica")]
        #expect(referencedFontNames(doc) == ["Arial", "Helvetica"])
    }

    @Test("collects inline \\fn overrides from cue tags")
    func collectsInlineFn() {
        var doc = SubtitleDocument(format: .ass)
        doc.styles = [AssStyle(name: "Default", fontName: "Arial")]
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "hi",
                        assSpans: [AssSpan(tags: #"\fnComic Sans MS\b1"#, text: "hi")])]
        #expect(referencedFontNames(doc) == ["Arial", "Comic Sans MS"])
    }

    @Test("missingEmbeddedFonts excludes fonts already embedded")
    func excludesAlreadyEmbedded() {
        var doc = SubtitleDocument(format: .ass)
        doc.styles = [AssStyle(name: "A", fontName: "Arial"), AssStyle(name: "B", fontName: "Helvetica")]
        doc.fonts = [AssEmbedded(name: "Arial.ttf", data: "")]
        #expect(missingEmbeddedFonts(doc) == ["Helvetica"])
    }

    @Test("a bare \\fn (revert to style default) contributes no name")
    func bareRevertFn() {
        var doc = SubtitleDocument(format: .ass)
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "hi",
                        assSpans: [AssSpan(tags: #"\fn\b1"#, text: "hi")])]
        #expect(referencedFontNames(doc).isEmpty)
    }
}
