import Testing
@testable import GlyphlineCore

@Suite("Resolution resample: style scaling")
struct ResampleStyleTests {
    @Test("uniform 2x scale doubles font/border/shadow/margins")
    func uniformScale() {
        let style = AssStyle(name: "Default", fontSize: 40, outline: 2, shadow: 1,
                             marginL: 10, marginR: 10, marginV: 20)
        let out = resampleStyle(style, scale: ResampleScale(x: 2, y: 2))
        #expect(out.fontSize == 80)
        #expect(out.outline == 4)
        #expect(out.shadow == 2)
        #expect(out.marginL == 20)
        #expect(out.marginR == 20)
        #expect(out.marginV == 40)
    }

    @Test("non-uniform scale uses x for horizontal margins, y for vertical/font")
    func nonUniformScale() {
        let style = AssStyle(name: "Default", fontSize: 40, marginL: 10, marginR: 10, marginV: 20)
        let out = resampleStyle(style, scale: ResampleScale(x: 1, y: 2))
        #expect(out.fontSize == 80) // scales with y
        #expect(out.marginL == 10) // scales with x (unchanged)
        #expect(out.marginV == 40) // scales with y
    }
}

@Suite("Resolution resample: tag block scaling")
struct ResampleTagBlockTests {
    @Test("\\pos scales both coordinates independently")
    func posScaling() {
        let out = scaleAssTagBlock(#"\pos(100,200)"#, scale: ResampleScale(x: 2, y: 0.5))
        #expect(out == #"\pos(200,100)"#)
    }

    @Test("\\org scales like \\pos")
    func orgScaling() {
        let out = scaleAssTagBlock(#"\org(50,50)"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\org(100,100)"#)
    }

    @Test("\\move scales the 4 coordinates but leaves optional timing args alone")
    func moveScalingWithTiming() {
        let out = scaleAssTagBlock(#"\move(0,0,100,100,500,1500)"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\move(0,0,200,200,500,1500)"#)
    }

    @Test("\\move without optional timing args still scales correctly")
    func moveScalingNoTiming() {
        let out = scaleAssTagBlock(#"\move(0,0,100,100)"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\move(0,0,200,200)"#)
    }

    @Test("\\fs, \\bord, \\shad, \\blur scale with the vertical factor")
    func verticalSizeTags() {
        let out = scaleAssTagBlock(#"\fs40\bord2\shad1\blur0.5"#, scale: ResampleScale(x: 1, y: 2))
        #expect(out == #"\fs80\bord4\shad2\blur1"#)
    }

    @Test("\\xbord/\\xshad scale with x, \\ybord/\\yshad scale with y")
    func axisSpecificTags() {
        let out = scaleAssTagBlock(#"\xbord2\ybord4\xshad1\yshad3"#, scale: ResampleScale(x: 2, y: 0.5))
        #expect(out == #"\xbord4\ybord2\xshad2\yshad1.5"#)
    }

    @Test("negative coordinates scale correctly")
    func negativeCoordinates() {
        let out = scaleAssTagBlock(#"\pos(-100,-50)"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\pos(-200,-100)"#)
    }

    @Test("unrelated tags in the same block are left untouched")
    func unrelatedTagsPassThrough() {
        let out = scaleAssTagBlock(#"\b1\pos(10,10)\i1"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\b1\pos(20,20)\i1"#)
    }

    @Test("a scale factor of 1 leaves integral values integral, not '10.0'")
    func identityScaleStaysIntegral() {
        let out = scaleAssTagBlock(#"\pos(10,10)"#, scale: ResampleScale(x: 1, y: 1))
        #expect(out == #"\pos(10,10)"#)
    }

    @Test("a block with no scalable tags is unchanged")
    func noScalableTags() {
        let out = scaleAssTagBlock(#"\b1\i1"#, scale: ResampleScale(x: 2, y: 2))
        #expect(out == #"\b1\i1"#)
    }
}

@Suite("Resolution resample: document")
struct ResampleDocumentTests {
    private func docAt1080p() -> SubtitleDocument {
        var doc = SubtitleDocument(format: .ass)
        doc.meta["assScriptInfo"] = "ScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n"
        doc.styles = [AssStyle(name: "Default", fontSize: 40, outline: 2, shadow: 1)]
        doc.cues = [Cue(
            id: "a", start: 0, end: 1, text: "hi",
            assSpans: [AssSpan(tags: #"\pos(960,540)"#, text: "hi")]
        )]
        return doc
    }

    @Test("scaling to 4K doubles style metrics and tag coordinates")
    func scalesTo4K() {
        let out = resampleDocument(docAt1080p(), toWidth: 3840, toHeight: 2160)
        #expect(out.styles?[0].fontSize == 80)
        #expect(out.cues[0].assSpans?[0].tags == #"\pos(1920,1080)"#)
    }

    @Test("PlayResX/Y in meta are updated to the new resolution")
    func updatesPlayRes() {
        let out = resampleDocument(docAt1080p(), toWidth: 3840, toHeight: 2160)
        let res = scriptResolution(of: out)
        #expect(res.x == 3840 && res.y == 2160)
    }

    @Test("resampling to the same resolution is a no-op")
    func sameResolutionNoOp() {
        let original = docAt1080p()
        let out = resampleDocument(original, toWidth: 1920, toHeight: 1080)
        #expect(out.styles?[0].fontSize == original.styles?[0].fontSize)
        #expect(out.cues[0].assSpans?[0].tags == original.cues[0].assSpans?[0].tags)
    }

    @Test("a document with no styles/spans doesn't crash and still updates PlayRes")
    func handlesEmptyDocument() {
        var doc = SubtitleDocument(format: .ass)
        doc.cues = [Cue(id: "a", start: 0, end: 1, text: "plain, no tags")]
        let out = resampleDocument(doc, toWidth: 3840, toHeight: 2160)
        #expect(out.cues[0].text == "plain, no tags")
        let res = scriptResolution(of: out)
        #expect(res.x == 3840 && res.y == 2160)
    }
}
