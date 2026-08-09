import Testing
@testable import GlyphlineCore

@Suite("Auto-spotting")
struct AutoSpottingTests {
    private let sampleRate = 8000.0

    /// A tone burst at a given amplitude, `seconds` long.
    private func tone(seconds: Double, amplitude: Float) -> [Float] {
        [Float](repeating: amplitude, count: Int(seconds * sampleRate))
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    @Test("empty input produces no segments")
    func emptyInput() {
        #expect(detectSpeechSegments(samples: [], sampleRate: sampleRate).isEmpty)
    }

    @Test("all-silence input produces no segments")
    func allSilence() {
        let segs = detectSpeechSegments(samples: silence(seconds: 2), sampleRate: sampleRate)
        #expect(segs.isEmpty)
    }

    @Test("a single loud stretch surrounded by silence becomes one segment")
    func singleSegment() {
        let samples = silence(seconds: 1) + tone(seconds: 1, amplitude: 0.5) + silence(seconds: 1)
        let segs = detectSpeechSegments(samples: samples, sampleRate: sampleRate, paddingSec: 0)
        #expect(segs.count == 1)
        #expect(abs(segs[0].start - 1.0) < 0.05)
        #expect(abs(segs[0].end - 2.0) < 0.05)
    }

    @Test("two loud stretches separated by a long silence become two segments")
    func twoSegments() {
        let samples = tone(seconds: 0.5, amplitude: 0.5)
            + silence(seconds: 1.0)
            + tone(seconds: 0.5, amplitude: 0.5)
        let segs = detectSpeechSegments(
            samples: samples, sampleRate: sampleRate,
            minSilenceSec: 0.3, minSpeechSec: 0.2, paddingSec: 0
        )
        #expect(segs.count == 2)
    }

    @Test("a short silence gap is bridged into one segment")
    func bridgesShortGap() {
        let samples = tone(seconds: 0.5, amplitude: 0.5)
            + silence(seconds: 0.1) // shorter than minSilenceSec
            + tone(seconds: 0.5, amplitude: 0.5)
        let segs = detectSpeechSegments(
            samples: samples, sampleRate: sampleRate,
            minSilenceSec: 0.3, minSpeechSec: 0.2, paddingSec: 0
        )
        #expect(segs.count == 1)
    }

    @Test("a very short blip below minSpeechSec is discarded")
    func discardsShortBlip() {
        let samples = silence(seconds: 1) + tone(seconds: 0.05, amplitude: 0.5) + silence(seconds: 1)
        let segs = detectSpeechSegments(
            samples: samples, sampleRate: sampleRate,
            minSpeechSec: 0.3
        )
        #expect(segs.isEmpty)
    }

    @Test("padding extends both ends without crossing file bounds")
    func paddingClampsAtBounds() {
        let samples = tone(seconds: 1, amplitude: 0.5)
        let segs = detectSpeechSegments(
            samples: samples, sampleRate: sampleRate,
            minSpeechSec: 0.2, paddingSec: 0.5
        )
        #expect(segs.count == 1)
        #expect(segs[0].start == 0)
        #expect(segs[0].end <= 1.0 + 1e-6)
    }

    @Test("padding does not cross into a neighboring segment")
    func paddingClampsAtNeighbor() {
        // Two loud stretches with exactly 0.4s of silence between — long
        // enough to stay two segments, but shorter than 2×padding (0.6s),
        // so naive padding would make them overlap without the clamp.
        let samples = tone(seconds: 0.5, amplitude: 0.5)
            + silence(seconds: 0.4)
            + tone(seconds: 0.5, amplitude: 0.5)
        let segs = detectSpeechSegments(
            samples: samples, sampleRate: sampleRate,
            minSilenceSec: 0.3, minSpeechSec: 0.2, paddingSec: 0.3
        )
        #expect(segs.count == 2)
        #expect(segs[0].end <= segs[1].start)
    }

    @Test("a quiet tone below threshold is not detected as speech")
    func belowThresholdIsSilence() {
        let samples = tone(seconds: 1, amplitude: 0.001) // very quiet
        let segs = detectSpeechSegments(samples: samples, sampleRate: sampleRate, thresholdDb: -35)
        #expect(segs.isEmpty)
    }

    @Test("zero sample rate is a no-op, not a crash")
    func zeroSampleRate() {
        #expect(detectSpeechSegments(samples: [0.5, 0.5], sampleRate: 0).isEmpty)
    }
}

@Suite("Auto-spotting cue insertion")
struct AutoSpottingCueInsertionTests {
    @Test("inserts a cue per segment when the document is empty")
    func insertsIntoEmptyDoc() {
        let doc = DocumentModel()
        let n = doc.addCuesFromSpeechSegments([
            SpeechSegment(start: 1, end: 2),
            SpeechSegment(start: 5, end: 6),
        ])
        #expect(n == 2)
        #expect(doc.doc.cues.count == 2)
    }

    @Test("skips a segment that overlaps an existing cue")
    func skipsOverlappingSegment() {
        let doc = DocumentModel()
        doc.addCueAt(start: 1, end: 2)
        let before = doc.doc.cues.count
        let n = doc.addCuesFromSpeechSegments([
            SpeechSegment(start: 1.5, end: 2.5), // overlaps the manual cue
            SpeechSegment(start: 10, end: 11),   // clear
        ])
        #expect(n == 1)
        #expect(doc.doc.cues.count == before + 1)
    }

    @Test("no-op on an all-overlapping segment list leaves history untouched")
    func noOpDoesNotPushHistory() {
        let doc = DocumentModel()
        doc.addCueAt(start: 1, end: 2)
        #expect(!doc.canUndo == false) // sanity: the manual add IS undoable
        let canUndoBefore = doc.canUndo
        let n = doc.addCuesFromSpeechSegments([SpeechSegment(start: 1, end: 2)])
        #expect(n == 0)
        #expect(doc.canUndo == canUndoBefore)
    }
}
