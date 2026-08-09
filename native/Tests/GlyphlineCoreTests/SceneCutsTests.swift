import Testing
@testable import GlyphlineCore

@Suite("Scene cuts")
struct SceneCutsTests {
    @Test("parses pts_time out of real ffmpeg showinfo output")
    func parsesShowinfo() {
        let sample = """
        [Parsed_showinfo_1 @ 0x600002a1c0a0] n:   0 pts:      0 pts_time:0       \
        duration:      1 duration_time:0.04 fmt:yuv420p sar:0/1 s:320x240 i:P iskey:1 type:I
        [Parsed_showinfo_1 @ 0x600002a1c0a0] n:   1 pts:     50 pts_time:2.000000 \
        duration:      1 duration_time:0.04 fmt:yuv420p sar:0/1 s:320x240 i:P iskey:1 type:I
        [Parsed_showinfo_1 @ 0x600002a1c0a0] n:   2 pts:    100 pts_time:4.000000 \
        duration:      1 duration_time:0.04 fmt:yuv420p sar:0/1 s:320x240 i:P iskey:1 type:I
        """
        #expect(parseFFmpegSceneChangeOutput(sample) == [0, 2, 4])
    }

    @Test("returns nothing for text with no pts_time fields")
    func parsesEmpty() {
        #expect(parseFFmpegSceneChangeOutput("frame=100 fps=25").isEmpty)
    }

    @Test("output is sorted regardless of input order")
    func sortsOutput() {
        let text = "pts_time:5.0 pts_time:1.0 pts_time:3.0"
        #expect(parseFFmpegSceneChangeOutput(text) == [1, 3, 5])
    }

    @Test("nearestCut finds the closest cut within tolerance")
    func nearestWithinTolerance() {
        #expect(nearestCut(to: 10.05, in: [5, 10, 20], within: 0.2) == 10)
    }

    @Test("nearestCut returns nil when nothing is close enough")
    func nearestOutsideTolerance() {
        #expect(nearestCut(to: 10.5, in: [5, 20], within: 0.2) == nil)
    }

    @Test("nearestCut on an empty cut list is nil, not a crash")
    func nearestEmptyCuts() {
        #expect(nearestCut(to: 1, in: [], within: 1) == nil)
    }

    @Test("snapToNearestCut quantizes to the cut when close, passes through otherwise")
    func snapBehavior() {
        #expect(snapToNearestCut(10.05, cuts: [10], within: 0.2) == 10)
        #expect(snapToNearestCut(15.0, cuts: [10], within: 0.2) == 15.0)
    }

    @Test("cutsInside finds cuts strictly between start and end")
    func cutsInsideBasic() {
        let cue = Cue(id: "a", start: 1, end: 5, text: "hi")
        #expect(cutsInside(cue, cuts: [0, 3, 6]) == [3])
    }

    @Test("a cut exactly on a boundary is not a violation")
    func cutsOnBoundaryExcluded() {
        let cue = Cue(id: "a", start: 1, end: 5, text: "hi")
        #expect(cutsInside(cue, cuts: [1, 5]).isEmpty)
    }

    @Test("a zero or negative-length cue has no interior, so no violation")
    func cutsInsideDegenerateCue() {
        let cue = Cue(id: "a", start: 3, end: 3, text: "hi")
        #expect(cutsInside(cue, cuts: [3]).isEmpty)
    }

    @Test("evaluateCue sets crossesCut only when a cut is inside the span")
    func evaluateCueCrossesCut() {
        let cue = Cue(id: "a", start: 1, end: 5, text: "hi")
        #expect(evaluateCue(cue, prev: nil, sceneCuts: [3]).crossesCut)
        #expect(!evaluateCue(cue, prev: nil, sceneCuts: [1, 5]).crossesCut)
        #expect(!evaluateCue(cue, prev: nil, sceneCuts: []).crossesCut)
    }

    @Test("crossesCut alone makes hasAnyIssue true")
    func crossesCutFlagsIssue() {
        let cue = Cue(id: "a", start: 1, end: 5, text: "hi")
        let q = evaluateCue(cue, prev: nil, sceneCuts: [3])
        #expect(hasAnyIssue(q))
    }
}
