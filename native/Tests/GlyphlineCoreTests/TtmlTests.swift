import Testing
@testable import GlyphlineCore

@Suite("TTML/DFXP")
struct TtmlTests {
    private let sample = """
    <?xml version="1.0" encoding="utf-8"?>
    <tt xmlns="http://www.w3.org/ns/ttml" xmlns:tts="http://www.w3.org/ns/ttml#styling" xml:lang="en" ttp:frameRate="25">
      <head>
        <styling>
          <style xml:id="s1" tts:color="white" tts:fontSize="100%"/>
        </styling>
        <layout>
          <region xml:id="bottom" tts:origin="10% 80%"/>
        </layout>
      </head>
      <body>
        <div>
          <p begin="00:00:01.000" end="00:00:03.500" region="bottom" style="s1">Hello world</p>
          <p begin="00:00:04.000" end="00:00:06.000">Two<br/>lines</p>
          <p begin="00:00:07.000" dur="00:00:02.000">Uses dur</p>
        </div>
      </body>
    </tt>
    """

    @Test("parses timings, text and line breaks")
    func parse() {
        let doc = parseTtml(sample)
        #expect(doc.cues.count == 3)
        #expect(doc.cues[0].start == 1 && doc.cues[0].end == 3.5)
        #expect(doc.cues[0].text == "Hello world")
        #expect(doc.cues[1].text == "Two\nlines")
    }

    @Test("dur is accepted as an alternative to end")
    func durAttribute() {
        let doc = parseTtml(sample)
        #expect(doc.cues[2].start == 7)
        #expect(doc.cues[2].end == 9)
    }

    @Test("region/style attributes are carried per cue")
    func attributes() {
        let doc = parseTtml(sample)
        #expect(doc.cues[0].raw?["region"] == "bottom")
        #expect(doc.cues[0].raw?["style"] == "s1")
        #expect(doc.cues[1].raw?["region"] == nil)
    }

    @Test("frameRate is read from the root element")
    func frameRate() {
        #expect(parseTtml(sample).frameRate == 25)
    }

    @Test("offset time expressions parse, including frames")
    func offsetTimes() {
        #expect(parseTtmlTime("1.5s", frameRate: nil) == 1.5)
        #expect(parseTtmlTime("250ms", frameRate: nil) == 0.25)
        #expect(parseTtmlTime("2m", frameRate: nil) == 120)
        #expect(parseTtmlTime("25f", frameRate: 25) == 1)
        // Frames are meaningless without a rate, and ticks aren't supported.
        #expect(parseTtmlTime("25f", frameRate: nil) == nil)
        #expect(parseTtmlTime("100t", frameRate: 25) == nil)
    }

    @Test("head styling/layout is preserved verbatim through a round trip")
    func preservesHead() {
        let out = serializeTtml(parseTtml(sample))
        #expect(out.contains(#"<style xml:id="s1""#))
        #expect(out.contains(#"<region xml:id="bottom""#))
    }

    @Test("round trip keeps cue count, timings, text and attributes")
    func roundTrip() {
        let once = parseTtml(sample)
        let twice = parseTtml(serializeTtml(once))
        #expect(twice.cues.count == once.cues.count)
        for (a, b) in zip(once.cues, twice.cues) {
            #expect(abs(a.start - b.start) < 0.001)
            #expect(abs(a.end - b.end) < 0.001)
            #expect(a.text == b.text)
            #expect(a.raw?["region"] == b.raw?["region"])
        }
    }

    @Test("serializing twice is stable")
    func idempotent() {
        let once = serializeTtml(parseTtml(sample))
        #expect(serializeTtml(parseTtml(once)) == once)
    }

    @Test("XML entities survive both directions")
    func entities() {
        let doc = parseTtml("""
        <tt><body><div>
        <p begin="0s" end="1s">A &amp; B &lt;tag&gt; &quot;q&quot;</p>
        </div></body></tt>
        """)
        #expect(doc.cues[0].text == "A & B <tag> \"q\"")
        // And they come back escaped, not raw.
        let out = serializeTtml(doc)
        #expect(out.contains("&amp;") && out.contains("&lt;tag&gt;"))
        #expect(parseTtml(out).cues[0].text == "A & B <tag> \"q\"")
    }

    @Test("a paragraph with no usable timing is skipped, not crashed on")
    func malformed() {
        let doc = parseTtml("""
        <tt><body><div>
        <p>no timing at all</p>
        <p begin="00:00:01.000">no end or dur</p>
        <p begin="00:00:02.000" end="00:00:03.000">good</p>
        </div></body></tt>
        """)
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "good")
    }

    @Test("registered in the format registry under its extensions")
    func registered() {
        #expect(detectFormat("deliverable.ttml") == .external(.ttml))
        #expect(detectFormat("deliverable.dfxp") == .external(.ttml))
        #expect(detectFormat("deliverable.xml") == .external(.ttml))
        #expect(adapterForFormat(.ttml).extensions.first == "ttml")
    }

    @Test("converting from SRT produces a valid TTML skeleton")
    func fromSrt() {
        let srt = parseSrt("1\n00:00:01,000 --> 00:00:03,000\nHello\n")
        let out = serializeTtml(srt)
        #expect(out.contains("<tt "))
        #expect(out.contains(#"begin="00:00:01.000""#))
        #expect(parseTtml(out).cues.count == 1)
    }
}
