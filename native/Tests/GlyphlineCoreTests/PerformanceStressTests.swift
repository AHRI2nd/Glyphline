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

    // ── beyond a single feature-length file: a season/series-sized batch ──────
    //
    // 5,000 cues covers a long feature; a delivery-pipeline run or a heavily
    // edited multi-season project can push well past that. These extend the
    // same tripwire to 20,000 cues so an accidental O(n²) that's still masked
    // at 5,000 (a 4x input growing a well-behaved O(n) or O(n log n) function
    // by ~4x, but an O(n²) one by ~16x) gets caught before it ships.

    @Test("20,000 cues: sort + overlap coloring")
    func sortAndOverlapAtScale() {
        let raw = syntheticCues(count: 20000).shuffled()
        var sorted: [Cue] = []
        measure("sortedCues(20000)", budget: 1.0) { sorted = sortedCues(raw) }
        measure("overlapColorSlots(20000)", budget: 1.0) {
            _ = overlapColorSlots(for: sorted, paletteSize: 5)
        }
    }

    @Test("20,000 cues: quality evaluation over the whole document")
    func qualityEvaluationAtScale() {
        let cues = sortedCues(syntheticCues(count: 20000))
        measure("evaluateCue × 20000", budget: 2.0) {
            for (i, cue) in cues.enumerated() {
                _ = evaluateCue(cue, prev: i > 0 ? cues[i - 1] : nil)
            }
        }
    }

    @Test("20,000 cues: .glyph round-trip")
    func glyphRoundTripAtScale() throws {
        let doc = SubtitleDocument(format: .srt, cues: sortedCues(syntheticCues(count: 20000)))
        var json = ""
        measure("serializeGlyph(20000)", budget: 4.0) { json = (try? serializeGlyph(doc)) ?? "" }
        #expect(!json.isEmpty)
        var decoded: SubtitleDocument?
        measure("parseGlyph(20000)", budget: 4.0) { decoded = try? parseGlyph(json) }
        #expect(decoded?.cues.count == 20000)
    }

    // ── multi-language translation tracks (new this session — unexercised
    // by the above, which only ever touch the legacy single `translation`
    // field) ────────────────────────────────────────────────────────────────

    @Test("5,000 cues × 3 languages: translationText/setTranslationText round-trip")
    func multiLanguageAccessorsAtScale() {
        let languages = ["ko", "ja", "en"]
        var cues = sortedCues(syntheticCues(count: 5000))
        measure("setTranslationText × 5000 × 3 languages", budget: 0.5) {
            for i in cues.indices {
                for (idx, lang) in languages.enumerated() {
                    cues[i].setTranslationText("\(lang)-\(i)", at: idx, languages: languages)
                }
            }
        }
        var total = 0
        measure("translationText × 5000 × 3 languages", budget: 0.5) {
            for cue in cues {
                for idx in languages.indices {
                    if cue.translationText(at: idx, languages: languages) != nil { total += 1 }
                }
            }
        }
        #expect(total == 5000 * languages.count)
    }

    @Test("Glossary check against 5,000 cues with 200 language-tagged terms")
    func glossaryCheckAtScale() {
        var cues = sortedCues(syntheticCues(count: 5000))
        for i in cues.indices where i % 10 == 0 {
            cues[i].translation = "term\(i % 200) translated"
        }
        let doc = SubtitleDocument(format: .srt, cues: cues)
        let entries = (0..<200).map { GlossaryEntry(source: "term\($0)", target: "term\($0) translated", language: "ko") }
        measure("glossaryIssues(5000 cues, 200 entries)", budget: 1.0) {
            _ = glossaryIssues(in: doc, entries: entries)
        }
    }
}
