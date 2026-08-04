import Testing
@testable import GlyphlineCore

@Suite("Overlap coloring")
struct OverlapColoringTests {
    private func cue(_ id: String, _ start: Double, _ end: Double) -> Cue {
        Cue(id: id, start: start, end: end, text: id)
    }

    @Test("non-overlapping cues get no slot")
    func noOverlap() {
        let cues = [cue("a", 0, 5), cue("b", 10, 15), cue("c", 20, 25)]
        let slots = overlapColorSlots(for: cues, paletteSize: 5)
        #expect(slots.isEmpty)
    }

    @Test("two overlapping cues get different slots")
    func simpleOverlap() {
        let cues = sortedCues([cue("a", 0, 5), cue("b", 2, 7)])
        let slots = overlapColorSlots(for: cues, paletteSize: 5)
        #expect(slots["a"] != nil)
        #expect(slots["b"] != nil)
        #expect(slots["a"] != slots["b"])
    }

    @Test("earlier cue is retroactively marked once a later cue overlaps it")
    func retroactiveMarking() {
        // a starts alone, looks non-overlapping until c (which starts after a
        // but before a ends) shows up.
        let cues = sortedCues([cue("a", 0, 5), cue("c", 2, 3), cue("b", 10, 15)])
        let slots = overlapColorSlots(for: cues, paletteSize: 5)
        #expect(slots["a"] != nil)
        #expect(slots["c"] != nil)
        #expect(slots["a"] != slots["c"])
        #expect(slots["b"] == nil)
    }

    @Test("colors are reused once earlier intervals close")
    func slotReuse() {
        let cues = sortedCues([
            cue("a", 0, 5), cue("b", 1, 6),   // overlap, slots 0/1
            cue("c", 10, 15), cue("d", 11, 16), // separate overlap group, later
        ])
        let slots = overlapColorSlots(for: cues, paletteSize: 5)
        #expect(Set([slots["a"], slots["b"]]).count == 2)
        #expect(Set([slots["c"], slots["d"]]).count == 2)
        // Non-overlapping groups are free to reuse the same slot numbers.
        #expect(slots["c"] == slots["a"] || slots["c"] == slots["b"])
    }

    @Test("chained but non-mutually-overlapping cues each differ from their direct neighbor")
    func chain() {
        // a-b overlap, b-c overlap, a-c do NOT overlap.
        let cues = sortedCues([cue("a", 0, 5), cue("b", 4, 9), cue("c", 8, 12)])
        let slots = overlapColorSlots(for: cues, paletteSize: 5)
        #expect(slots["a"] != slots["b"])
        #expect(slots["b"] != slots["c"])
    }

    @Test("palette size of zero returns empty map without crashing")
    func zeroPalette() {
        let cues = sortedCues([cue("a", 0, 5), cue("b", 2, 7)])
        #expect(overlapColorSlots(for: cues, paletteSize: 0).isEmpty)
    }
}
