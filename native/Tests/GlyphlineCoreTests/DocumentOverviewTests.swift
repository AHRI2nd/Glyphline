import Testing
@testable import GlyphlineCore

@Suite("Document overview / actors")
struct DocumentOverviewTests {
    private func cue(_ id: String, _ s: Double, _ e: Double, actor: String? = nil, translation: String? = nil) -> Cue {
        Cue(id: id, start: s, end: e, text: id, translation: translation, actor: actor)
    }
    private func doc(_ cues: [Cue]) -> SubtitleDocument { SubtitleDocument(format: .srt, cues: cues) }

    @Test("an empty document produces an empty overview rather than crashing")
    func empty() {
        let o = buildOverview(doc([]))
        #expect(o.buckets.isEmpty && o.gaps.isEmpty)
        #expect(o.span == 0)
        #expect(o.translationProgress == nil)
    }

    @Test("the strip spans the media, not just the subtitled part")
    func spansMedia() {
        // Subtitles stop at 60s but the film runs 600s — that's the case worth
        // seeing, so the span must follow the media.
        let o = buildOverview(doc([cue("a", 0, 60)]), duration: 600)
        #expect(o.span == 600)
    }

    @Test("gaps longer than the threshold are reported with exact bounds")
    func gaps() {
        let o = buildOverview(doc([cue("a", 0, 10), cue("b", 100, 110)]), minGap: 30)
        #expect(o.gaps.count == 1)
        #expect(o.gaps[0].start == 10 && o.gaps[0].end == 100)
        #expect(o.gaps[0].duration == 90)
    }

    @Test("short gaps are ignored")
    func shortGapIgnored() {
        let o = buildOverview(doc([cue("a", 0, 10), cue("b", 20, 30)]), minGap: 30)
        #expect(o.gaps.isEmpty)
    }

    @Test("a trailing gap before the end of the media is reported")
    func trailingGap() {
        let o = buildOverview(doc([cue("a", 0, 10)]), duration: 600, minGap: 30)
        #expect(o.gaps.contains { $0.start == 10 && $0.end == 600 })
    }

    @Test("overlapping cues don't produce a phantom gap between them")
    func overlapNoGap() {
        // Cursor must advance by max(end), not the last cue's end.
        let o = buildOverview(doc([cue("a", 0, 100), cue("b", 10, 20)]), minGap: 30)
        #expect(o.gaps.isEmpty)
    }

    @Test("coverage is bounded and counts land in the right buckets")
    func buckets() {
        let o = buildOverview(doc([cue("a", 0, 50)]), duration: 100, bucketCount: 10)
        #expect(o.buckets.count == 10)
        for b in o.buckets { #expect(b.coverage >= 0 && b.coverage <= 1) }
        // First half covered, second half empty.
        #expect(o.buckets[0].coverage > 0.9)
        #expect(o.buckets[9].coverage == 0)
    }

    @Test("translation progress counts translated cues, nil when unused")
    func translation() {
        let none = buildOverview(doc([cue("a", 0, 1), cue("b", 2, 3)]))
        #expect(none.translationProgress == nil)

        let half = buildOverview(doc([
            cue("a", 0, 1, translation: "번역"),
            cue("b", 2, 3),
        ]))
        #expect(half.translatedCues == 1)
        #expect(half.translationProgress == 0.5)
        // Whitespace isn't a translation.
        let blank = buildOverview(doc([cue("a", 0, 1, translation: "   ")]))
        #expect(blank.translationProgress == nil)
    }

    // ── actors ──────────────────────────────────────────────────────────────

    @Test("actors are counted and ordered by line count")
    func actors() {
        let list = actorSummaries(doc([
            cue("a", 0, 1, actor: "철수"), cue("b", 2, 3, actor: "영희"),
            cue("c", 4, 5, actor: "철수"), cue("d", 6, 7, actor: "철수"),
        ]))
        #expect(list.count == 2)
        #expect(list[0].name == "철수" && list[0].lineCount == 3)
        #expect(list[1].name == "영희")
    }

    @Test("near-identical names stay separate so the typo is visible")
    func actorsNotMerged() {
        let list = actorSummaries(doc([
            cue("a", 0, 1, actor: "철수"),
            cue("b", 2, 3, actor: "철 수"),
        ]))
        #expect(list.count == 2, "names were merged, hiding the inconsistency")
    }

    @Test("cues with no actor are skipped, and the first cue is recorded")
    func actorsScope() {
        let list = actorSummaries(doc([
            cue("a", 5, 6, actor: "   "),
            cue("b", 1, 2, actor: "철수"),
            cue("c", 9, 10, actor: "철수"),
        ]))
        #expect(list.count == 1)
        #expect(list[0].firstCueId == "b")   // earliest in time, not document order
        #expect(list[0].firstStart == 1)
    }
}
