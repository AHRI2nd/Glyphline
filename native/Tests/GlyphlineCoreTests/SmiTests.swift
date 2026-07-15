import Testing
@testable import GlyphlineCore

// Vectors ported from ../../scripts/roundtrip-test.ts (SMI + ASS→SMI lossy).

@Suite("SMI")
struct SmiTests {
    let smi = """
    <SAMI>
    <HEAD>
    <TITLE>Test</TITLE>
    <STYLE TYPE="text/css"><!--
    .KRCC { Name: Korean; lang: ko-KR; }
    --></STYLE>
    </HEAD>
    <BODY>
    <SYNC Start=1000><P Class=KRCC>안녕하세요
    <SYNC Start=3000><P Class=KRCC>&nbsp;
    <SYNC Start=4000><P Class=KRCC>두<br>번째 줄
    <SYNC Start=6000><P Class=KRCC>&nbsp;
    </BODY>
    </SAMI>
    """

    @Test("blanks are boundaries, <br> becomes newline")
    func parse() {
        let doc = parseSmi(smi)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1)
        #expect(doc.cues[0].end == 3) // closed by the blank marker
        #expect(doc.cues[1].text == "두\n번째 줄")
        #expect(doc.meta["smiMainClass"] == "KRCC")
    }

    @Test("round-trip stable")
    func roundTrip() {
        let doc = parseSmi(smi)
        let doc2 = parseSmi(serializeSmi(doc))
        #expect(doc2.cues.count == 2)
        #expect(doc2.cues[1].text == "두\n번째 줄")
        #expect(doc2.cues[0].start == doc.cues[0].start && doc2.cues[0].end == doc.cues[0].end)
    }
}

@Suite("SMI ← ASS lossy conversion")
struct SmiFromAssTests {
    let styledAss = #"""
    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\pos(10,20)\b1\1c&H0000FF&}Red bold{\b0} plain{\k50}\Nline2{\p1}m 0 0 l 5 5{\p0}

    """#

    @Test("representable formatting converts; rest drops + reports")
    func convert() {
        let doc = parseAss(styledAss)
        let spans = try! #require(doc.cues[0].assSpans)
        let conv = spansToSmiHtml(spans)
        #expect(conv.html.contains("<b>Red bold"))
        #expect(conv.html.uppercased().contains("COLOR=\"#FF0000\"")) // BGR reversed
        #expect(conv.html.contains("<br>"))                          // \N → <br>
        #expect(!conv.html.contains("m 0 0"))                        // drawing dropped
        #expect(conv.dropped.contains(.position))
        #expect(conv.dropped.contains(.karaoke))
        #expect(conv.dropped.contains(.drawing))
    }

    @Test("smiExportLoss aggregates + serialize emits SYNC")
    func aggregate() {
        let doc = parseAss(styledAss)
        let loss = smiExportLoss(doc)
        #expect(loss.contains(.position) && loss.contains(.drawing))
        #expect(serializeSmi(doc).contains("<SYNC Start=1000>"))
    }
}
