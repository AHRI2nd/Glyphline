import Testing
@testable import GlyphlineCore

@Suite("Frame-accurate timing")
struct FrameTimeTests {
    private let ntsc24 = 24000.0 / 1001.0  // 23.976…
    private let ntsc30 = 30000.0 / 1001.0  // 29.97…

    @Test("format at integer frame rates")
    func format() {
        #expect(formatFrameTimecode(0, fps: 24) == "00:00:00:00")
        #expect(formatFrameTimecode(1, fps: 24) == "00:00:01:00")
        #expect(formatFrameTimecode(1.5, fps: 24) == "00:00:01:12")
        #expect(formatFrameTimecode(3661, fps: 25) == "01:01:01:00")
        #expect(formatFrameTimecode(0.04, fps: 25) == "00:00:00:01")
    }

    @Test("parse HH:MM:SS:FF and MM:SS:FF")
    func parse() {
        #expect(parseFrameTimecode("00:00:01:12", fps: 24) == 1.5)
        #expect(parseFrameTimecode("00:01:12", fps: 24) == 1.5)
        #expect(parseFrameTimecode("01:01:01:00", fps: 25) == 3661)
    }

    @Test("malformed input is rejected")
    func rejects() {
        #expect(parseFrameTimecode("", fps: 24) == nil)
        #expect(parseFrameTimecode("1:2", fps: 24) == nil)
        #expect(parseFrameTimecode("00:00:01.500", fps: 24) == nil)
        #expect(parseFrameTimecode("aa:bb:cc:dd", fps: 24) == nil)
        #expect(parseFrameTimecode("00:00:-1:00", fps: 24) == nil)
        // fps of 0 has no frame grid to parse against.
        #expect(parseFrameTimecode("00:00:01:00", fps: 0) == nil)
    }

    @Test("an out-of-range frame field carries into seconds")
    func carries() {
        // 30 frames at 24fps = 1s + 6f, so 1s:30f → 2s + 6f = 2.25s
        #expect(parseFrameTimecode("00:00:01:30", fps: 24) == 2.25)
    }

    @Test("format/parse round-trip on every common frame rate")
    func roundTrip() {
        for fps in COMMON_FRAME_RATES {
            for frame in [0, 1, 7, 23, 100, 5000, 86_399] {
                let seconds = Double(frame) / fps
                let text = formatFrameTimecode(seconds, fps: fps)
                let back = parseFrameTimecode(text, fps: fps)
                #expect(back != nil, "\(text) @\(fps) failed to parse")
                if let back {
                    // Same frame in, same frame out — the seconds value may
                    // differ in the last bits, the frame index must not.
                    #expect(frameIndex(back, fps: fps) == frame,
                            "\(text) @\(fps): frame \(frameIndex(back, fps: fps)) != \(frame)")
                }
            }
        }
    }

    @Test("snapping is idempotent and lands on a boundary")
    func snap() {
        for fps in COMMON_FRAME_RATES {
            for raw in [0.0, 0.017, 1.234, 59.9, 3600.5] {
                let once = snapToFrame(raw, fps: fps)
                #expect(snapToFrame(once, fps: fps) == once, "not idempotent @\(fps)")
                // Within half a frame of where it started.
                #expect(abs(once - raw) <= 0.5 / fps + 1e-9)
            }
        }
    }

    @Test("zero/negative fps degrades instead of dividing by zero")
    func zeroFps() {
        #expect(snapToFrame(1.234, fps: 0) == 1.234)
        #expect(frameIndex(1.234, fps: 0) == 0)
        #expect(!formatFrameTimecode(1.5, fps: 0).isEmpty)
    }

    @Test("NTSC pulldown rates keep frame identity across an hour")
    func ntscDrift() {
        // At 23.976 an hour is 86 313 frames; the label is NDF (see FrameTime's
        // header), but the frame index must survive the round trip exactly.
        for fps in [ntsc24, ntsc30] {
            let frame = 86_313
            let text = formatFrameTimecode(Double(frame) / fps, fps: fps)
            #expect(frameIndex(parseFrameTimecode(text, fps: fps) ?? -1, fps: fps) == frame)
        }
    }

    @Test("frame rate labels are readable")
    func labels() {
        #expect(frameRateLabel(24) == "24")
        #expect(frameRateLabel(ntsc24) == "23.976")
        #expect(frameRateLabel(ntsc30) == "29.970")
    }
}

@Suite("Frame snapping preserves cue duration")
struct SnapCueBoundsTests {
    @Test("a sub-frame cue is widened to one frame instead of collapsing")
    func subFrame() {
        for fps in COMMON_FRAME_RATES {
            let b = snapCueBounds(start: 1.0001, end: 1.0002, fps: fps)
            #expect(b.end > b.start, "collapsed at \(frameRateLabel(fps))")
            // Exactly one frame wide, not more.
            #expect(abs((b.end - b.start) - 1.0 / fps) < 1e-9)
        }
    }

    @Test("a normal cue keeps both edges exactly on frame boundaries")
    func normal() {
        let b = snapCueBounds(start: 1.02, end: 3.47, fps: 25)
        #expect(b.start == snapToFrame(1.02, fps: 25))
        #expect(b.end == snapToFrame(3.47, fps: 25))
        #expect(b.end > b.start)
    }

    @Test("an already-empty or inverted cue is not given duration")
    func degenerate() {
        let empty = snapCueBounds(start: 2, end: 2, fps: 24)
        #expect(empty.start == empty.end)
        let inverted = snapCueBounds(start: 3, end: 2, fps: 24)
        #expect(inverted.end < inverted.start)
    }

    @Test("fps of zero passes the values through untouched")
    func zeroFps() {
        let b = snapCueBounds(start: 1.234, end: 5.678, fps: 0)
        #expect(b.start == 1.234 && b.end == 5.678)
    }
}

@Suite("Timecode notation ambiguity")
struct TimecodeAmbiguityTests {
    /// `00:01:23` is legal in BOTH notations and means very different things.
    /// The grid resolves this by only treating a full four-part value as a
    /// frame timecode (see CueGridCoordinator.parseTime); this pins the fact
    /// that drove that rule, so nobody "simplifies" it back later.
    @Test("a three-part value is 42x apart between the two parsers")
    func ambiguous() {
        let asFrames = parseFrameTimecode("00:01:23", fps: 24)
        let asClock = parseTimestampInput("00:01:23")
        #expect(asClock == 83)
        #expect(asFrames != nil)
        #expect(abs((asFrames ?? 0) - 83) > 80, "the two readings must not be conflated")
    }

    @Test("a four-part value is unambiguous — only the frame parser accepts it")
    func unambiguous() {
        #expect(parseFrameTimecode("00:00:01:12", fps: 24) == 1.5)
        #expect(parseTimestampInput("00:00:01:12") == nil)
    }
}
