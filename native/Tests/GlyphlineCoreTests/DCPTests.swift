import Testing
@testable import GlyphlineCore

@Suite("DCP subtitle (Interop XML)")
struct DCPTests {
    private func doc(_ cues: [Cue]) -> SubtitleDocument { SubtitleDocument(format: .dcp, cues: cues) }

    @Test("root element and version, per the CineCanvas Rev C spec")
    func rootElement() {
        let xml = serializeDcp(doc([Cue(id: "a", start: 1, end: 2, text: "hi")]))
        #expect(xml.contains(#"<DCSubtitle Version="1.1">"#))
    }

    @Test("required children appear before any Subtitle element, in spec order")
    func requiredChildrenOrder() {
        let xml = serializeDcp(doc([Cue(id: "a", start: 1, end: 2, text: "hi")]))
        let subtitleIdRange = xml.range(of: "<SubtitleID>")!
        let movieTitleRange = xml.range(of: "<MovieTitle>")!
        let reelNumberRange = xml.range(of: "<ReelNumber>")!
        let languageRange = xml.range(of: "<Language>")!
        let firstSubtitleRange = xml.range(of: "<Subtitle ")!
        #expect(subtitleIdRange.lowerBound < movieTitleRange.lowerBound)
        #expect(movieTitleRange.lowerBound < reelNumberRange.lowerBound)
        #expect(reelNumberRange.lowerBound < languageRange.lowerBound)
        #expect(languageRange.lowerBound < firstSubtitleRange.lowerBound)
    }

    @Test("SubtitleID is a well-formed hex UUID, fresh on every export")
    func subtitleIdIsUuid() throws {
        func subtitleId(_ xml: String) throws -> String {
            let openTag = try #require(xml.range(of: "<SubtitleID>"))
            let closeTag = try #require(xml.range(of: "</SubtitleID>"))
            return String(xml[openTag.upperBound..<closeTag.lowerBound])
        }
        let idA = try subtitleId(serializeDcp(doc([Cue(id: "a", start: 0, end: 1, text: "x")])))
        let idB = try subtitleId(serializeDcp(doc([Cue(id: "a", start: 0, end: 1, text: "x")])))
        #expect(idA != idB) // fresh identity on every export
        let hexUuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        #expect(idA.range(of: hexUuidPattern, options: .regularExpression) != nil)
    }

    @Test("TimeIn/TimeOut use the spec's decimal-seconds alternative format")
    func timeFormat() {
        let xml = serializeDcp(doc([Cue(id: "a", start: 1.5, end: 3.25, text: "hi")]))
        #expect(xml.contains(#"TimeIn="00:00:01.500""#))
        #expect(xml.contains(#"TimeOut="00:00:03.250""#))
    }

    @Test("SpotNumber increments per cue in sorted order")
    func spotNumberSequence() {
        let xml = serializeDcp(doc([
            Cue(id: "b", start: 5, end: 6, text: "second"),
            Cue(id: "a", start: 1, end: 2, text: "first"),
        ]))
        #expect(xml.contains(#"SpotNumber="1""#))
        #expect(xml.contains(#"SpotNumber="2""#))
        let firstIndex = xml.range(of: ">first<")!.lowerBound
        let spot1Index = xml.range(of: #"SpotNumber="1""#)!.lowerBound
        #expect(spot1Index < firstIndex)
    }

    @Test("multi-line cues become one <Text> per line, stacked with the last line closest to the bottom")
    func multilineStacking() {
        let xml = serializeDcp(doc([Cue(id: "a", start: 0, end: 1, text: "top\nbottom")]))
        let bottomIndex = xml.range(of: ">bottom<")!.lowerBound
        let topIndex = xml.range(of: ">top<")!.lowerBound
        // Lower VPosition = closer to the bottom edge; "bottom" (the later
        // line) should get the smaller VPosition and appear first in the XML.
        #expect(bottomIndex < topIndex)
        #expect(xml.contains(#"VPosition="8.0""#))
        #expect(xml.contains(#"VPosition="16.0""#))
    }

    @Test("text is XML-entity-escaped")
    func entityEscaping() {
        let xml = serializeDcp(doc([Cue(id: "a", start: 0, end: 1, text: "A & B < C")]))
        #expect(xml.contains("A &amp; B &lt; C"))
    }

    @Test("a plain .xml file still opens as TTML, not DCP — DCP is export-only")
    func openingStaysGeneralTtml() {
        #expect(detectFormat("subs.xml") == .external(.ttml))
    }
}
