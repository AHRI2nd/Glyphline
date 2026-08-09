import Testing
@testable import GlyphlineCore

@Suite("Position preview")
struct PositionPreviewTests {
    @Test("crosshair is centered at the requested coordinate")
    func centeredAtCoordinate() {
        let cue = positionPreviewCue(x: 100, y: 200, radius: 10)
        #expect(cue.text.contains("m 90 200"))
        #expect(cue.text.contains("110 200"))
    }

    @Test("preview cue spans the whole timeline")
    func spansWholeTimeline() {
        let cue = positionPreviewCue(x: 0, y: 0)
        #expect(cue.start == 0)
        #expect(cue.end >= 86_400)
    }

    @Test("withPositionPreview adds exactly one cue and one style")
    func additive() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 2, text: "hi")]
        doc.styles = [AssStyle(name: "Default")]
        let out = withPositionPreview(doc, x: 50, y: 50)
        #expect(out.cues.count == 2)
        #expect(out.styles?.count == 2)
        #expect(doc.cues.count == 1) // original untouched (value semantics)
    }

    @Test("preview serializes as an ASS drawing on a high layer")
    func serializes() {
        var doc = SubtitleDocument()
        doc.styles = [AssStyle(name: "Default")]
        let ass = serializeAss(withPositionPreview(doc, x: 100, y: 100))
        #expect(ass.contains("Style: \(POSITION_PREVIEW_STYLE)"))
        #expect(ass.contains("Dialogue: 200,"))
        #expect(ass.contains("\\p1}"))
    }
}
