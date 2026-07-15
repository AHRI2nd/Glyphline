import Testing
@testable import GlyphlineCore

// Vectors ported from ../../scripts/roundtrip-test.ts (SRT/SBV/LRC/TXT + time).

@Suite("Time")
struct TimeTests {
    @Test("SRT/VTT/ASS formatting")
    func formatting() {
        #expect(formatSrtTime(3.5) == "00:00:03,500")
        #expect(formatVttTime(3.5) == "00:00:03.500")
        #expect(formatAssTime(3.5) == "0:00:03.50")
        #expect(formatDisplayTime(3.5) == "00:03.500")
        #expect(formatDisplayTime(3661.0) == "01:01:01.000")
    }

    @Test("clock / ass / lenient parsing")
    func parsing() {
        #expect(parseClockTime("00:00:03,500") == 3.5)
        #expect(parseClockTime("garbage") == nil)
        #expect(parseClockTime("01:23.456") == 83.456)
        #expect(parseAssTime("0:00:03.50") == 3.5)
        #expect(parseTimestampInput("83.4") == 83.4)
        #expect(parseTimestampInput("00:01:23,456") == 83.456)
        #expect(parseTimestampInput("nonsense") == nil)
    }
}

@Suite("SRT")
struct SRTTests {
    let srt = """
    1
    00:00:01,000 --> 00:00:03,500
    Hello world
    second line

    2
    00:00:04,000 --> 00:00:06,000
    Goodbye

    """

    @Test("parse")
    func parse() {
        let doc = parseSrt(srt)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1 && doc.cues[0].end == 3.5)
        #expect(doc.cues[0].text == "Hello world\nsecond line")
    }

    @Test("round-trip stable")
    func roundTrip() {
        let doc = parseSrt(srt)
        let doc2 = parseSrt(serializeSrt(doc))
        #expect(doc2.cues.map { [$0.start, $0.end] } == doc.cues.map { [$0.start, $0.end] })
        #expect(doc2.cues.map(\.text) == doc.cues.map(\.text))
    }
}

@Suite("SBV")
struct SBVTests {
    let sbv = """
    0:00:01.000,0:00:03.500
    Hello world
    second line

    0:00:04.000,0:00:06.000
    Goodbye

    """

    @Test("parse + round-trip")
    func parseRoundTrip() {
        let doc = parseSbv(sbv)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1 && doc.cues[0].end == 3.5)
        #expect(doc.cues[0].text == "Hello world\nsecond line")
        let doc2 = parseSbv(serializeSbv(doc))
        #expect(doc2.cues.map { [$0.start, $0.end] } == doc.cues.map { [$0.start, $0.end] })
    }
}

@Suite("LRC")
struct LRCTests {
    let lrc = """
    [ti:Song]
    [00:01.00]first line
    [00:03.50]second line

    """

    @Test("metadata ignored + implied end")
    func parse() {
        let doc = parseLrc(lrc)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1 && doc.cues[0].end == 3.5)
        #expect(doc.cues[0].text == "first line")
        let doc2 = parseLrc(serializeLrc(doc))
        #expect(abs(doc2.cues[0].start - doc.cues[0].start) < 0.01)
    }
}

@Suite("TXT")
struct TXTTests {
    @Test("lines → cues, export text-only")
    func parse() {
        let doc = parseTxt("line one\nline two\n\nline three")
        #expect(doc.cues.count == 3)
        #expect(doc.cues[0].start == 0 && doc.cues[1].start == 2)
        let out = serializeTxt(doc)
        #expect(out.contains("line one") && !out.contains("00:"))
    }
}
