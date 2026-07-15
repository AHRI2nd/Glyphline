import Testing
@testable import GlyphlineCore

// Vectors ported from ../../scripts/roundtrip-test.ts (ASS + embedded + tags).

@Suite("ASS")
struct AssTests {
    let ass = #"""
    [Script Info]
    ScriptType: v4.00+

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\k50}Ka{\k50}ra{\k100}oke
    Dialogue: 0,0:00:04.00,0:00:05.50,Default,Bob,0,0,0,,Hello, with comma

    """#

    @Test("styles, cues, karaoke, comma-in-text, actor")
    func parse() {
        let doc = parseAss(ass)
        #expect(doc.styles?.count == 1)
        #expect(doc.styles?[0].fontName == "Arial")
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].tokens?.count == 3)
        #expect(doc.cues[1].text == "Hello, with comma") // Text is last column
        #expect(doc.cues[1].actor == "Bob")
    }

    @Test("round-trip preserves cues + karaoke")
    func roundTrip() {
        let doc = parseAss(ass)
        let doc2 = parseAss(serializeAss(doc))
        #expect(doc2.cues.count == 2)
        #expect(doc2.cues[0].tokens?.count == 3)
        #expect(doc2.cues[1].text == "Hello, with comma")
    }
}

@Suite("ASS embedded [Fonts]/[Graphics]")
struct AssEmbeddedTests {
    let embedAss = """
    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

    [Fonts]
    fontname: myfont_0.ttf
    !!!!encoded-line-one!!!!
    ####encoded-line-two####
    fontname: other_1.otf
    ABCDEF

    [Graphics]
    filename: logo_0.png
    GFXDATA0123

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,hi

    """

    @Test("parsed verbatim, no header leak")
    func parse() {
        let doc = parseAss(embedAss)
        #expect(doc.fonts?.count == 2)
        #expect(doc.fonts?[0].name == "myfont_0.ttf")
        #expect(doc.fonts?[0].data == "!!!!encoded-line-one!!!!\n####encoded-line-two####")
        #expect(doc.fonts?[1].name == "other_1.otf")
        #expect(doc.fonts?[1].data == "ABCDEF")
        #expect(doc.graphics?.count == 1)
        #expect(doc.graphics?[0].name == "logo_0.png")
        #expect(doc.cues.count == 1 && doc.cues[0].text == "hi")
        #expect((doc.meta["assExtra"] ?? "").lowercased().contains("[fonts]") == false)
    }

    @Test("round-trip lossless")
    func roundTrip() {
        let doc = parseAss(embedAss)
        let out = serializeAss(doc)
        #expect(out.contains("[Fonts]") && out.contains("fontname: myfont_0.ttf"))
        #expect(out.contains("[Graphics]") && out.contains("filename: logo_0.png"))
        let doc2 = parseAss(out)
        #expect(doc2.fonts == doc.fonts)
        #expect(doc2.graphics == doc.graphics)
    }

    @Test("embeddedByteSize estimates without decoding")
    func byteSize() {
        #expect(embeddedByteSize("ABCD") == 3)     // 4 chars → 3 bytes
        #expect(embeddedByteSize("ABCDEFGH") == 6)
        #expect(embeddedByteSize("ABC") == 2)      // remainder 3 → 2 bytes
    }
}

@Suite("ASS tags")
struct AssTagTests {
    @Test("spans round-trip every tag verbatim (known or not)")
    func spans() {
        let raw = #"{\pos(100,200)\1c&H00FF00&}Hello {\zzz9}world"#
        let spans = parseAssText(raw)
        #expect(serializeAssText(spans) == raw) // byte-for-byte
        #expect(spansToPlain(spans) == "Hello world")
        #expect(hasOverrideTags(spans))
    }

    @Test("decodeTags: order, unknown tags, nested parens")
    func decode() {
        let tags = decodeTags(#"\pos(100,200)\b1\zzz9\t(\frz360)"#)
        #expect(tags.map(\.name) == ["pos", "b", "zzz", "t"])
        #expect(tags[0].arg == "(100,200)")
        #expect(tags[1].arg == "1")
        #expect(tags[2].known == false)          // unknown preserved
        #expect(tags[3].arg == #"(\frz360)"#)    // nested parens kept
    }

    @Test("drawing regions (\\p) dropped from plain text; \\pos is not a drawing tag")
    func drawing() {
        let spans = parseAssText(#"{\p1}m 0 0 l 10 10{\p0}real text"#)
        #expect(spansToPlain(spans) == "real text")
        let posSpans = parseAssText(#"{\pos(1,2)}visible"#)
        #expect(spansToPlain(posSpans) == "visible")
    }

    @Test("hard breaks and spaces normalize")
    func breaks() {
        let spans = parseAssText(#"line1\Nline2\hend"#)
        #expect(spansToPlain(spans) == "line1\nline2 end")
    }

    @Test("categorizeTag maps to loss categories")
    func categories() {
        #expect(categorizeTag("pos") == .position)
        #expect(categorizeTag("k") == .karaoke)
        #expect(categorizeTag("p") == .drawing)
        #expect(categorizeTag("zzz") == .other)
    }
}
