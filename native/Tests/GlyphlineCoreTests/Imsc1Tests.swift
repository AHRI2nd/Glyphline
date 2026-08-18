import Testing
@testable import GlyphlineCore

@Suite("IMSC1 export")
struct Imsc1Tests {
    private func doc(_ cues: [Cue]) -> SubtitleDocument { SubtitleDocument(format: .imsc1, cues: cues) }

    @Test("declares the required namespaces and IMSC1.1 text profile")
    func conformantHeader() {
        let xml = serializeImsc1(doc([Cue(id: "a", start: 1, end: 2, text: "hi")]))
        #expect(xml.contains(#"xmlns="http://www.w3.org/ns/ttml""#))
        #expect(xml.contains(#"xmlns:ttp="http://www.w3.org/ns/ttml#parameter""#))
        #expect(xml.contains(#"xmlns:tts="http://www.w3.org/ns/ttml#styling""#))
        #expect(xml.contains(#"ttp:contentProfiles="http://www.w3.org/ns/ttml/profile/imsc1.1/text""#))
    }

    @Test("defines a single region using tts:origin/tts:extent, staying under the 4-region cap")
    func singleConformantRegion() {
        let xml = serializeImsc1(doc([Cue(id: "a", start: 1, end: 2, text: "hi")]))
        #expect(xml.contains(#"<region xml:id="subtitleRegion""#))
        #expect(xml.contains("tts:origin="))
        #expect(xml.contains("tts:extent="))
        // Exactly one <region ...> — this adapter never emits more than one.
        let count = xml.components(separatedBy: "<region ").count - 1
        #expect(count == 1)
    }

    @Test("cues become <p> elements referencing the region, with begin/end times")
    func cueToParagraph() {
        let xml = serializeImsc1(doc([Cue(id: "a", start: 1.5, end: 3.25, text: "hello")]))
        #expect(xml.contains(#"begin="00:00:01.500""#))
        #expect(xml.contains(#"end="00:00:03.250""#))
        #expect(xml.contains(#"region="subtitleRegion""#))
        #expect(xml.contains(">hello</p>"))
    }

    @Test("multi-line text joins with <br/>, matching the general TTML adapter")
    func multiline() {
        let xml = serializeImsc1(doc([Cue(id: "a", start: 0, end: 1, text: "line1\nline2")]))
        #expect(xml.contains("line1<br/>line2"))
    }

    @Test("text is XML-entity-escaped")
    func entityEscaping() {
        let xml = serializeImsc1(doc([Cue(id: "a", start: 0, end: 1, text: "A & B < C")]))
        #expect(xml.contains("A &amp; B &lt; C"))
    }

    @Test("cues are emitted in sorted (time) order regardless of input order")
    func sortedOrder() {
        let xml = serializeImsc1(doc([
            Cue(id: "b", start: 5, end: 6, text: "second"),
            Cue(id: "a", start: 1, end: 2, text: "first"),
        ]))
        let firstIndex = xml.range(of: ">first</p>")!.lowerBound
        let secondIndex = xml.range(of: ">second</p>")!.lowerBound
        #expect(firstIndex < secondIndex)
    }

    @Test("a plain TTML file still opens as general TTML, not IMSC1")
    func openingStaysGeneralTtml() {
        // .ttml/.xml resolve to the loose TTML adapter first in the registry
        // (see Registry.swift's ordering comment) — IMSC1 is export-only.
        #expect(detectFormat("subs.ttml") == .external(.ttml))
        #expect(detectFormat("subs.xml") == .external(.ttml))
    }
}
