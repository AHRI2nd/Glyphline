// Guards the app's own stated scaling goal ("수천 개 자막까지 스케일" — see
// CLAUDE.md) at the layer that's actually testable without driving the GUI:
// the pure core functions every UI surface calls on every relevant update.
// Thresholds are deliberately generous (10-100x realistic budgets) — this
// isn't a micro-benchmark, it's a tripwire for an accidental O(n²) creeping
// into a hot path, which is exactly the class of bug the CueGrid click-freeze
// and the waveform's unclipped per-frame redraw both turned out to be.

import Testing
@testable import GlyphlineCore

@Suite("Performance at scale")
struct PerformanceStressTests {
    /// Cues packed tight with ~15% intentionally overlapping their neighbor,
    /// covering both the common case and the overlap-coloring code path.
    private func syntheticCues(count: Int) -> [Cue] {
        var cues: [Cue] = []
        cues.reserveCapacity(count)
        var t = 0.0
        for i in 0..<count {
            let duration = 1.5 + Double(i % 5) * 0.3
            let overlap = i % 7 == 0 ? 0.4 : 0.0
            let start = max(0, t - overlap)
            let end = start + duration
            cues.append(Cue(id: "cue-\(i)", start: start, end: end, text: "Line \(i)\nSecond line of dialogue \(i)"))
            t = end + 0.1
        }
        return cues
    }

    private func measure(_ label: String, budget: Double, _ body: () -> Void) {
        let clock = ContinuousClock()
        let elapsed = clock.measure(body)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("[perf] \(label): \(String(format: "%.3f", seconds))s (budget \(budget)s)")
        #expect(seconds < budget, "\(label) took \(seconds)s, budget was \(budget)s")
    }

    @Test("5,000 cues: sort + overlap coloring")
    func sortAndOverlap() {
        let raw = syntheticCues(count: 5000).shuffled()
        var sorted: [Cue] = []
        measure("sortedCues(5000)", budget: 0.2) { sorted = sortedCues(raw) }
        measure("overlapColorSlots(5000)", budget: 0.2) {
            _ = overlapColorSlots(for: sorted, paletteSize: 5)
        }
    }

    @Test("5,000 cues: quality evaluation over the whole document")
    func qualityEvaluation() {
        let cues = sortedCues(syntheticCues(count: 5000))
        measure("evaluateCue × 5000", budget: 0.5) {
            for (i, cue) in cues.enumerated() {
                _ = evaluateCue(cue, prev: i > 0 ? cues[i - 1] : nil)
            }
        }
    }

    @Test(".glyph round-trip at 5,000 cues")
    func glyphRoundTrip() throws {
        let doc = SubtitleDocument(format: .srt, cues: sortedCues(syntheticCues(count: 5000)))
        var json = ""
        measure("serializeGlyph(5000)", budget: 1.0) { json = (try? serializeGlyph(doc)) ?? "" }
        #expect(!json.isEmpty)
        var decoded: SubtitleDocument?
        measure("parseGlyph(5000)", budget: 1.0) { decoded = try? parseGlyph(json) }
        #expect(decoded?.cues.count == 5000)
    }

    @Test("SRT round-trip at 5,000 cues (the subtitle push debounce path)")
    func srtRoundTrip() {
        let doc = SubtitleDocument(format: .srt, cues: sortedCues(syntheticCues(count: 5000)))
        var srt = ""
        measure("serializeSrt(5000)", budget: 0.5) { srt = serializeSrt(doc) }
        #expect(!srt.isEmpty)
        var reparsed: SubtitleDocument?
        measure("parseSrt(5000)", budget: 0.5) { reparsed = parseSrt(srt) }
        #expect(reparsed?.cues.count == 5000)
    }

    @Test("ASS serialization at 5,000 cues (the mpv subtitle-overlay push path)")
    func assSerialization() {
        let doc = SubtitleDocument(
            format: .ass,
            styles: [AssStyle(name: "Default")],
            cues: sortedCues(syntheticCues(count: 5000))
        )
        var ass = ""
        measure("serializeAss(5000)", budget: 1.0) { ass = serializeAss(doc) }
        #expect(!ass.isEmpty)
    }
}
