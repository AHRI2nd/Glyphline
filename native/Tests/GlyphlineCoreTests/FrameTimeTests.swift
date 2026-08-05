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
