import Testing
@testable import GlyphlineCore

@Suite("Timing post-process")
struct TimingPostProcessTests {
    private func cues() -> [Cue] {
        [
            Cue(id: "a", start: 2, end: 4, text: "one"),
            Cue(id: "b", start: 6, end: 8, text: "two"),
            Cue(id: "c", start: 9, end: 11, text: "three"),
        ]
    }

    // ── lead-in/out ──────────────────────────────────────────────────────────

    @Test("lead-in pulls start earlier, lead-out pushes end later")
    func basicLeadInOut() {
        let (out, changed) = applyLeadInOut(cues(), leadInSec: 0.5, leadOutSec: 0.5)
        #expect(changed == 3)
        #expect(out[0].start == 1.5 && out[0].end == 4.5)
    }

    @Test("lead-in never crosses into the previous cue's end")
    func leadInClampsAtPrevEnd() {
        // Gap between a (ends 4) and b (starts 6) is 2s; a lead-in of 3s on b
        // would want start=3, which is fine (still after prevEnd=4)... use a
        // tighter gap to force the clamp.
        let tight = [
            Cue(id: "a", start: 0, end: 4, text: "one"),
            Cue(id: "b", start: 4.2, end: 8, text: "two"),
        ]
        let (out, _) = applyLeadInOut(tight, leadInSec: 1.0, leadOutSec: 0)
        #expect(out[1].start == 4) // clamped to prevEnd, not 4.2 - 1.0 = 3.2
    }

    @Test("lead-out never crosses into the next cue's start")
    func leadOutClampsAtNextStart() {
        let tight = [
            Cue(id: "a", start: 0, end: 4, text: "one"),
            Cue(id: "b", start: 4.2, end: 8, text: "two"),
        ]
        let (out, _) = applyLeadInOut(tight, leadInSec: 0, leadOutSec: 1.0)
        #expect(out[0].end == 4.2) // clamped to next.start, not 4 + 1.0 = 5.0
    }

    @Test("zero lead-in and lead-out is a no-op")
    func zeroIsNoOp() {
        let (out, changed) = applyLeadInOut(cues(), leadInSec: 0, leadOutSec: 0)
        #expect(changed == 0)
        #expect(out == cues())
    }

    @Test("the very first cue's lead-in is clamped at zero")
    func firstCueClampedAtZero() {
        let short = [Cue(id: "a", start: 0.3, end: 2, text: "hi")]
        let (out, _) = applyLeadInOut(short, leadInSec: 1.0, leadOutSec: 0)
        #expect(out[0].start == 0)
    }

    // ── gap bridging ─────────────────────────────────────────────────────────

    @Test("bridges a gap at or under the threshold")
    func bridgesSmallGap() {
        // gap a→b = 2s, b→c = 1s
        let (out, changed) = bridgeSmallGaps(cues(), maxGapSec: 1.5)
        #expect(changed == 1)
        #expect(out[1].end == 9) // b extended to meet c's start
        #expect(out[0].end == 4) // a→b gap (2s) exceeds threshold, untouched
    }

    @Test("leaves gaps larger than the threshold alone")
    func leavesLargeGapsAlone() {
        let (out, changed) = bridgeSmallGaps(cues(), maxGapSec: 0.5)
        #expect(changed == 0)
        #expect(out == cues())
    }

    @Test("does not touch cues that already overlap or touch (zero gap)")
    func skipsZeroGap() {
        let touching = [
            Cue(id: "a", start: 0, end: 2, text: "one"),
            Cue(id: "b", start: 2, end: 4, text: "two"),
        ]
        let (out, changed) = bridgeSmallGaps(touching, maxGapSec: 1.0)
        #expect(changed == 0)
        #expect(out == touching)
    }

    // ── scene cut snapping ───────────────────────────────────────────────────

    @Test("snaps start and end independently to nearby cuts")
    func snapsIndependently() {
        let one = [Cue(id: "a", start: 2.05, end: 4.1, text: "hi")]
        let (out, changed) = snapCuesToSceneCuts(one, sceneCuts: [2.0, 4.0], toleranceSec: 0.15)
        #expect(changed == 1)
        #expect(out[0].start == 2.0 && out[0].end == 4.0)
    }

    @Test("leaves a cue alone when no cut is within tolerance")
    func noNearbyySceneCut() {
        let one = [Cue(id: "a", start: 2, end: 4, text: "hi")]
        let (out, changed) = snapCuesToSceneCuts(one, sceneCuts: [10], toleranceSec: 0.1)
        #expect(changed == 0)
        #expect(out == one)
    }

    @Test("refuses a snap that would collapse or invert the cue")
    func refusesDegenerateSnap() {
        // Both cuts sit near the (very short) cue's boundaries and close to
        // each other — end snapping past start would invert it.
        let one = [Cue(id: "a", start: 1.0, end: 1.05, text: "hi")]
        let (out, _) = snapCuesToSceneCuts(one, sceneCuts: [0.98, 1.0], toleranceSec: 0.1)
        #expect(out[0].end > out[0].start)
    }

    @Test("empty cut list is a no-op")
    func emptyCutsNoOp() {
        let (out, changed) = snapCuesToSceneCuts(cues(), sceneCuts: [], toleranceSec: 0.1)
        #expect(changed == 0)
        #expect(out == cues())
    }
}
