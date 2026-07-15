import Testing
@testable import GlyphlineCore

@Suite("VTT")
struct VTTTests {
    let vtt = """
    WEBVTT

    00:00:01.000 --> 00:00:03.500 align:start
    Hello world

    intro
    00:00:04.000 --> 00:00:06.000
    Goodbye

    """

    @Test("parse header + settings + identifier")
    func parse() {
        let doc = parseVtt(vtt)
        #expect(doc.cues.count == 2)
        #expect(doc.cues[0].start == 1 && doc.cues[0].end == 3.5)
        #expect(doc.cues[0].raw?["settings"] == "align:start")
        #expect(doc.cues[1].raw?["identifier"] == "intro")
        #expect(doc.meta["vttPreamble"]?.hasPrefix("WEBVTT") == true)
    }

    @Test("inline timestamps → tokens, round-trip")
    func tokens() {
        let src = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\none<00:00:01.000>two"
        let doc = parseVtt(src)
        #expect(doc.cues[0].tokens?.count == 2)
        #expect(doc.cues[0].text == "onetwo")
        let doc2 = parseVtt(serializeVtt(doc))
        #expect(doc2.cues[0].tokens?.count == 2)
    }
}

@Suite("Color")
struct ColorTests {
    @Test("ASS ↔ hex with alpha")
    func convert() {
        #expect(assColorToHex("&H00FFCC00") == "#00CCFF")
        #expect(assAlpha("&H80FFCC00") == "80")
        #expect(hexToAssColor("#00CCFF") == "&H00FFCC00")          // RGB→BGR reversed
        #expect(hexToAssColor("#00CCFF", alpha: "80") == "&H80FFCC00")
    }
}

@Suite("Quality")
struct QualityTests {
    @Test("cps and duration checks")
    func checks() {
        let cue = Cue(id: "a", start: 0, end: 1, text: "abcdefghijklmnopqrstuvwxyz") // 26 chars / 1s
        let q = evaluateCue(cue, prev: nil)
        #expect(q.cpsTooHigh) // 26 > 20
        #expect(q.durationTooShort == false) // 1s ≥ 0.7
        #expect(hasAnyIssue(q))
    }

    @Test("line length / count + netflix preset")
    func lines() {
        let cue = Cue(id: "a", start: 0, end: 5, text: "one\ntwo\nthree")
        let q = evaluateCue(cue, prev: nil)
        #expect(q.tooManyLines) // 3 > 2
        #expect(NETFLIX_THRESHOLDS.maxCps == 17)
    }
}
