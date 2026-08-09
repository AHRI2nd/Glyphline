import Testing
@testable import GlyphlineCore

private let NTSC_29_97 = 30000.0 / 1001.0
private let NTSC_59_94 = 60000.0 / 1001.0

@Suite("Drop-frame timecode")
struct DropFrameTimecodeTests {
    @Test("drop-frame only applies to NTSC pulldown rates")
    func candidacy() {
        #expect(isDropFrameCandidate(fps: NTSC_29_97))
        #expect(isDropFrameCandidate(fps: NTSC_59_94))
        #expect(!isDropFrameCandidate(fps: 30))
        #expect(!isDropFrameCandidate(fps: 25))
        #expect(!isDropFrameCandidate(fps: 24))
    }

    @Test("frame 0 is 00:00:00;00")
    func zero() {
        #expect(formatDropFrameTimecode(0, fps: NTSC_29_97) == "00:00:00;00")
    }

    // Hand-derived reference points (SMPTE 12M drop-frame algorithm), verified
    // by hand-tracing the standard conversion before trusting the code:
    // raw frame 1798 (≈60.0s of real time at 29.97fps) falls just before the
    // minute-1 boundary, still unlabeled-corrected → 00:00:59;28.
    @Test("just before a minute boundary reads uncorrected")
    func beforeMinuteBoundary() {
        let seconds = 1798.0 / NTSC_29_97
        #expect(formatDropFrameTimecode(seconds, fps: NTSC_29_97) == "00:00:59;28")
    }

    // The very next physical frame (1800) crosses into minute 1, which is NOT
    // a multiple of 10 — so labels ;00 and ;01 are skipped, landing on ;02.
    @Test("skips ;00 and ;01 crossing into a non-tenth minute")
    func skipsAtMinuteBoundary() {
        let seconds = 1800.0 / NTSC_29_97
        #expect(formatDropFrameTimecode(seconds, fps: NTSC_29_97) == "00:01:00;02")
    }

    // Every TENTH minute drops nothing, so it lands exactly on ;00.
    @Test("no drop at a tenth-minute boundary")
    func noDropAtTenthMinute() {
        let seconds = 17982.0 / NTSC_29_97
        #expect(formatDropFrameTimecode(seconds, fps: NTSC_29_97) == "00:10:00;00")
    }

    @Test("drop-frame round-trips through parse")
    func roundTrip() {
        for raw in [0.0, 59.5, 60.06, 600.0, 3600.234, 5999.9] {
            let label = formatDropFrameTimecode(raw, fps: NTSC_29_97)
            let parsed = parseDropFrameTimecode(label, fps: NTSC_29_97)
            #expect(parsed != nil)
            // Round-trip agrees to within one frame (label quantizes to frames).
            #expect(abs((parsed ?? -999) - raw) < 1.0 / NTSC_29_97 + 1e-6)
        }
    }

    @Test("59.94 uses 4 dropped frames per non-tenth minute")
    func fiftyNineNinetyFour() {
        // Just after crossing minute 1 at 59.94: skip ;00..;03, land on ;04.
        let seconds = 3600.0 / NTSC_59_94 // raw frame 3600 = 1 minute nominal-60fps
        #expect(formatDropFrameTimecode(seconds, fps: NTSC_59_94) == "00:01:00;04")
    }

    @Test("falls back to plain NDF formatting at a non-DF rate")
    func fallsBackAtNonDFRate() {
        #expect(formatDropFrameTimecode(1.0, fps: 25) == formatFrameTimecode(1.0, fps: 25))
        #expect(parseDropFrameTimecode("00:00:01:00", fps: 25) == parseFrameTimecode("00:00:01:00", fps: 25))
    }

    @Test("parseDropFrameTimecode accepts a plain ':' before the frame field too")
    func acceptsColonSeparator() {
        let a = parseDropFrameTimecode("00:01:00;02", fps: NTSC_29_97)
        let b = parseDropFrameTimecode("00:01:00:02", fps: NTSC_29_97)
        #expect(a == b)
    }

    @Test("garbage input parses to nil, not a crash")
    func rejectsGarbage() {
        #expect(parseDropFrameTimecode("not a timecode", fps: NTSC_29_97) == nil)
        #expect(parseDropFrameTimecode("00:99", fps: NTSC_29_97) == nil)
    }

    // ── display + offset ─────────────────────────────────────────────────────

    @Test("displayTimecode adds the offset before formatting")
    func displayWithOffset() {
        // 10:00:00:00 house start, internal time 5s in.
        let s = displayTimecode(5.0, fps: 25, offsetSec: 36_000)
        #expect(s == "10:00:05:00")
    }

    @Test("parseDisplayTimecode removes the offset")
    func parseWithOffset() {
        let t = parseDisplayTimecode("10:00:05:00", fps: 25, offsetSec: 36_000)
        #expect(t == 5.0)
    }

    // Regression: a code-review pass found that a label BEFORE the house
    // start (e.g. typing 05:00:00:00 under a 10:00:00:00 offset) silently
    // produced a NEGATIVE internal seconds value, which every other
    // assumption in the app (cue sort order, SRT export's time formatter,
    // "duration ≥ 0" quality checks) doesn't expect. The grid's edit handler
    // already reverts on a nil parse — this makes that the outcome instead
    // of quietly corrupting the cue.
    @Test("parseDisplayTimecode rejects a label earlier than the offset, rather than going negative")
    func rejectsBelowOffset() {
        let t = parseDisplayTimecode("05:00:00:00", fps: 25, offsetSec: 36_000)
        #expect(t == nil)
    }

    @Test("a label exactly AT the offset parses to zero, not rejected")
    func acceptsExactlyAtOffset() {
        let t = parseDisplayTimecode("10:00:00:00", fps: 25, offsetSec: 36_000)
        #expect(t == 0)
    }

    @Test("display/parse with offset round-trips")
    func offsetRoundTrip() {
        let original = 123.4
        let label = displayTimecode(original, fps: 25, offsetSec: 36_000)
        let back = parseDisplayTimecode(label, fps: 25, offsetSec: 36_000)
        #expect(back != nil)
        #expect(abs((back ?? -1) - original) < 1.0 / 25 + 1e-6)
    }

    @Test("displayTimecode with offset and drop-frame together")
    func offsetAndDropFrame() {
        // 36000.0s isn't an exact multiple of a 29.97fps frame duration, so this
        // rounds to raw frame 1078921 (one past the exact 10-hour/600-minute
        // boundary at 1078920) — landing on ;01, not ;00. That's the correct,
        // if slightly counterintuitive, consequence of quantizing a plain
        // seconds offset to frames; it isn't a bug in the drop-frame algorithm
        // itself (verified separately above against hand-derived frame counts).
        let s = displayTimecode(0, fps: NTSC_29_97, offsetSec: 36_000, dropFrame: true)
        #expect(s == "10:00:00;01")
    }

    @Test("negative internal time before the offset floor clamps to zero rather than going negative")
    func clampsBelowZero() {
        let s = displayTimecode(-10, fps: 25, offsetSec: 5)
        #expect(s == "00:00:00:00")
    }

    // ── document-level settings ──────────────────────────────────────────────

    @Test("timecodeStartOffsetSec defaults to zero and round-trips through meta")
    func documentOffsetDefault() {
        var doc = SubtitleDocument()
        #expect(doc.timecodeStartOffsetSec == 0)
        doc.timecodeStartOffsetSec = 36_000
        #expect(doc.timecodeStartOffsetSec == 36_000)
        #expect(doc.meta["tcStartOffsetSec"] == "36000.0")
    }

    @Test("setting the offset back to zero clears the meta key rather than storing '0'")
    func documentOffsetClearsAtZero() {
        var doc = SubtitleDocument()
        doc.timecodeStartOffsetSec = 3600
        doc.timecodeStartOffsetSec = 0
        #expect(doc.meta["tcStartOffsetSec"] == nil)
    }

    @Test("timecodeDropFrame defaults to false and round-trips through meta")
    func documentDropFrameDefault() {
        var doc = SubtitleDocument()
        #expect(!doc.timecodeDropFrame)
        doc.timecodeDropFrame = true
        #expect(doc.timecodeDropFrame)
        doc.timecodeDropFrame = false
        #expect(doc.meta["tcDropFrame"] == nil)
    }
}
