import Testing
@testable import GlyphlineCore

@Suite("Export scope")
struct ExportScopeTests {
    private func doc() -> SubtitleDocument {
        var d = SubtitleDocument()
        d.cues = [
            Cue(id: "a", start: 1, end: 3, text: "one"),
            Cue(id: "b", start: 5, end: 7, text: "two"),
            Cue(id: "c", start: 9, end: 11, text: "three"),
        ]
        return d
    }

    @Test("all keeps everything unchanged")
    func all() {
        let out = subsetDocument(doc(), scope: .all)
        #expect(out.cues.map(\.id) == ["a", "b", "c"])
        #expect(out.cues[0].start == 1)
    }

    @Test("selected keeps only the chosen ids, in document order")
    func selected() {
        let out = subsetDocument(doc(), scope: .selected(["c", "a"]))
        #expect(out.cues.map(\.id) == ["a", "c"])
    }

    @Test("time range includes cues that overlap the boundary, uncut")
    func timeRangeOverlap() {
        // 2–6 clips into cue a (1–3) and cue b (5–7) but contains neither.
        let out = subsetDocument(doc(), scope: .timeRange(start: 2, end: 6))
        #expect(out.cues.map(\.id) == ["a", "b"])
        #expect(out.cues[0].start == 1 && out.cues[0].end == 3)
    }

    @Test("a cue merely touching the boundary is not included")
    func touchingBoundary() {
        let out = subsetDocument(doc(), scope: .timeRange(start: 3, end: 5))
        #expect(out.cues.isEmpty)
    }

    @Test("reversed range is normalised")
    func reversedRange() {
        let out = subsetDocument(doc(), scope: .timeRange(start: 6, end: 2))
        #expect(out.cues.map(\.id) == ["a", "b"])
    }

    @Test("rebase shifts the excerpt so it starts at zero")
    func rebase() {
        let out = subsetDocument(doc(), scope: .timeRange(start: 4, end: 12), rebaseToZero: true)
        #expect(out.cues.map(\.start) == [0, 4])
        #expect(out.cues.map(\.end) == [2, 6])
    }

    @Test("rebase moves word-level tokens with their cue")
    func rebaseTokens() {
        var d = doc()
        d.cues[1].tokens = [SyncToken(text: "two", start: 5, end: 7, confidence: 0.5)]
        let out = subsetDocument(d, scope: .selected(["b"]), rebaseToZero: true)
        #expect(out.cues[0].tokens?.first?.start == 0)
        #expect(out.cues[0].tokens?.first?.end == 2)
        #expect(out.cues[0].tokens?.first?.confidence == 0.5)
    }

    @Test("rebase on an empty result is a no-op, not a crash")
    func rebaseEmpty() {
        let out = subsetDocument(doc(), scope: .selected([]), rebaseToZero: true)
        #expect(out.cues.isEmpty)
    }

    @Test("document metadata survives narrowing")
    func keepsMetadata() {
        var d = doc()
        d.format = .ass
        let out = subsetDocument(d, scope: .selected(["a"]))
        #expect(out.format == .ass)
    }
}
