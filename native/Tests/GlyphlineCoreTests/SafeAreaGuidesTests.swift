import Testing
@testable import GlyphlineCore

@Suite("Safe area guides")
struct SafeAreaGuidesTests {
    @Test("falls back to libass's default script resolution")
    func defaultResolution() {
        let res = scriptResolution(of: SubtitleDocument())
        #expect(res.x == 384 && res.y == 288)
    }

    @Test("reads PlayResX/Y out of the preserved Script Info block")
    func readsPlayRes() {
        var d = SubtitleDocument()
        d.meta["assScriptInfo"] = "ScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n"
        let res = scriptResolution(of: d)
        #expect(res.x == 1920 && res.y == 1080)
    }

    @Test("ignores a zero or malformed resolution")
    func rejectsBadPlayRes() {
        var d = SubtitleDocument()
        d.meta["assScriptInfo"] = "PlayResX: 0\nPlayResY: nonsense\n"
        let res = scriptResolution(of: d)
        #expect(res.x == 384 && res.y == 288)
    }

    @Test("action-safe box insets 3.5% on each side of 1920x1080")
    func actionSafeBox() {
        let shape = safeBoxDrawing(fraction: ACTION_SAFE_FRACTION, width: 1920, height: 1080)
        // 1920 * 0.07 / 2 = 67.2 → 67;  1080 * 0.07 / 2 = 37.8 → 38
        #expect(shape == "m 67 38 l 1853 38 1853 1042 67 1042")
    }

    @Test("title-safe box is strictly inside the action-safe box")
    func nesting() {
        #expect(TITLE_SAFE_FRACTION < ACTION_SAFE_FRACTION)
        let action = safeBoxDrawing(fraction: ACTION_SAFE_FRACTION, width: 1000, height: 1000)
        let title = safeBoxDrawing(fraction: TITLE_SAFE_FRACTION, width: 1000, height: 1000)
        #expect(action == "m 35 35 l 965 35 965 965 35 965")
        #expect(title == "m 50 50 l 950 50 950 950 50 950")
    }

    @Test("adds exactly two cues and one style, leaving the original alone")
    func additive() {
        var d = SubtitleDocument()
        d.cues = [Cue(id: "a", start: 1, end: 2, text: "hi")]
        d.styles = [AssStyle(name: "Default")]
        let out = withSafeAreaGuides(d, duration: 120)
        #expect(out.cues.count == 3)
        #expect(out.styles?.count == 2)
        #expect(d.cues.count == 1)          // input untouched (value semantics)
        #expect(out.cues[0].id == "a")      // real cues stay first
    }

    @Test("guides span the whole file regardless of reported duration")
    func spansWholeFile() {
        let out = withSafeAreaGuides(SubtitleDocument(), duration: 12)
        #expect(out.cues.allSatisfy { $0.start == 0 && $0.end >= 86_400 })
    }

    @Test("guide cues survive ASS serialization as drawings on a high layer")
    func serializes() {
        var d = SubtitleDocument()
        d.meta["assScriptInfo"] = "PlayResX: 1920\nPlayResY: 1080\n"
        d.styles = [AssStyle(name: "Default")]
        let ass = serializeAss(withSafeAreaGuides(d, duration: 60))
        #expect(ass.contains("Style: \(SAFE_GUIDE_STYLE)"))
        #expect(ass.contains("\\p1}m 67 38"))
        #expect(ass.contains("Dialogue: 100,"))
    }
}
