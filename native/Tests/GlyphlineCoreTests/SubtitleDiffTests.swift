import Testing
@testable import GlyphlineCore

@Suite("Subtitle compare / join / split")
struct SubtitleDiffTests {
    private func cue(_ id: String, _ start: Double, _ end: Double, _ text: String) -> Cue {
        Cue(id: id, start: start, end: end, text: text)
    }
    private func doc(_ cues: [Cue]) -> SubtitleDocument {
        SubtitleDocument(format: .srt, cues: cues)
    }

    // ── compare ─────────────────────────────────────────────────────────────

    @Test("identical documents produce no findings")
    func identical() {
        let d = doc([cue("a", 0, 2, "one"), cue("b", 3, 5, "two")])
        #expect(diffDocuments(d, d).isEmpty)
    }

    @Test("a text edit at the same time reads as textChanged")
    func textEdit() {
        let a = doc([cue("a", 0, 2, "hello")])
        let b = doc([cue("x", 0, 2, "hello there")])
        let entries = diffDocuments(a, b)
        #expect(entries.count == 1)
        #expect(entries[0].kind == .textChanged)
        #expect(entries[0].left?.text == "hello")
        #expect(entries[0].right?.text == "hello there")
    }

    @Test("same text moved in time reads as retimed, which a text diff can't see")
    func retime() {
        let a = doc([cue("a", 0, 2, "hello")])
        let b = doc([cue("x", 0.5, 2.5, "hello")])
        let entries = diffDocuments(a, b)
        #expect(entries.count == 1)
        #expect(entries[0].kind == .retimed)
    }

    @Test("both changed reads as changed")
    func bothChanged() {
        let a = doc([cue("a", 0, 2, "hello")])
        let b = doc([cue("x", 0.5, 2.5, "goodbye")])
        #expect(diffDocuments(a, b)[0].kind == .changed)
    }

    @Test("insertions and deletions are reported on the right side")
    func addRemove() {
        let a = doc([cue("a", 0, 2, "keep"), cue("b", 10, 12, "gone")])
        let b = doc([cue("x", 0, 2, "keep"), cue("y", 20, 22, "new")])
        let s = summarize(diffDocuments(a, b))
        #expect(s.removed == 1 && s.added == 1)
        #expect(s.textChanged == 0 && s.retimed == 0)
    }

    @Test("an inserted cue doesn't cascade every later cue into a change")
    func noCascade() {
        // Index-based pairing would mark all three following cues as changed.
        let a = doc([cue("a", 0, 1, "A"), cue("b", 2, 3, "B"), cue("c", 4, 5, "C")])
        let b = doc([cue("x", 0, 1, "A"), cue("new", 1.2, 1.8, "NEW"),
                     cue("y", 2, 3, "B"), cue("z", 4, 5, "C")])
        let s = summarize(diffDocuments(a, b))
        #expect(s.added == 1)
        #expect(s.total == 1, "expected only the insertion, got \(s)")
    }

    @Test("sub-epsilon timing drift is not reported as a retime")
    func epsilon() {
        let a = doc([cue("a", 1.000, 3.000, "same")])
        let b = doc([cue("x", 1.010, 3.010, "same")])
        #expect(diffDocuments(a, b).isEmpty)
    }

    @Test("findings come back in time order")
    func ordered() {
        let a = doc([cue("a", 10, 11, "late"), cue("b", 1, 2, "early")])
        let b = doc([cue("x", 10, 11, "late edited"), cue("y", 1, 2, "early edited")])
        let entries = diffDocuments(a, b)
        #expect(entries.map(\.time) == entries.map(\.time).sorted())
    }

    @Test("comparing against an empty document reports every cue as removed")
    func emptyOther() {
        let a = doc([cue("a", 0, 1, "x"), cue("b", 2, 3, "y")])
        #expect(summarize(diffDocuments(a, doc([]))).removed == 2)
        #expect(summarize(diffDocuments(doc([]), a)).added == 2)
    }

    // ── join ────────────────────────────────────────────────────────────────

    @Test("append shifts the incoming cues and keeps everything sorted")
    func append() {
        let a = doc([cue("a", 0, 2, "part1")])
        let b = doc([cue("b", 0, 2, "part2")])
        let joined = appendDocument(a, b, offset: 10)
        #expect(joined.cues.count == 2)
        #expect(joined.cues[1].start == 10 && joined.cues[1].end == 12)
        #expect(joined.cues.map(\.start) == joined.cues.map(\.start).sorted())
    }

    @Test("appended cues get fresh ids so two files can't collide")
    func appendReIds() {
        let a = doc([cue("dup", 0, 2, "first")])
        let b = doc([cue("dup", 0, 2, "second")])
        let joined = appendDocument(a, b, offset: 10)
        #expect(Set(joined.cues.map(\.id)).count == 2, "duplicate ids survived the join")
    }

    @Test("appendOffsetAfter lands past the last cue")
    func offsetHelper() {
        let a = doc([cue("a", 0, 5, "x")])
        #expect(appendOffsetAfter(a, gap: 1) == 6)
        #expect(appendOffsetAfter(doc([]), gap: 1) == 1)
    }

    // ── split ───────────────────────────────────────────────────────────────

    @Test("split partitions by start time and rebases the second half")
    func split() {
        let d = doc([cue("a", 0, 2, "one"), cue("b", 10, 12, "two"), cue("c", 14, 16, "three")])
        let (first, second) = splitDocument(d, at: 10)
        #expect(first.cues.map(\.text) == ["one"])
        #expect(second.cues.map(\.text) == ["two", "three"])
        #expect(second.cues[0].start == 0)   // rebased
        #expect(second.cues[1].start == 4)   // gap preserved
    }

    @Test("rebasing can be turned off")
    func splitNoRebase() {
        let d = doc([cue("a", 0, 2, "one"), cue("b", 10, 12, "two")])
        let (_, second) = splitDocument(d, at: 10, rebaseSecond: false)
        #expect(second.cues[0].start == 10)
    }

    @Test("a cue straddling the split point stays whole in the first half")
    func straddling() {
        let d = doc([cue("a", 8, 12, "straddles")])
        let (first, second) = splitDocument(d, at: 10)
        #expect(first.cues.count == 1)
        #expect(second.cues.isEmpty)
    }

    @Test("splitting outside the range leaves one side empty")
    func splitEdges() {
        let d = doc([cue("a", 5, 6, "x")])
        #expect(splitDocument(d, at: 0).first.cues.isEmpty)
        #expect(splitDocument(d, at: 100).second.cues.isEmpty)
    }
}
