import Testing
@testable import GlyphlineCore

@Suite("Sync tokens (karaoke timing)")
struct SyncTokenTests {
    private func cue(_ text: String, _ start: Double = 0, _ end: Double = 4) -> Cue {
        Cue(id: "c", start: start, end: end, text: text)
    }

    // ── splitting ───────────────────────────────────────────────────────────

    @Test("Latin text splits per word")
    func latinSplit() {
        let units = syllableSplit("hello big world")
        #expect(units.count == 3)
        #expect(units.joined() == "hello big world")
    }

    @Test("Japanese splits per character, since karaoke is timed that way")
    func japaneseSplit() {
        let units = syllableSplit("さくら")
        #expect(units == ["さ", "く", "ら"])
    }

    @Test("Korean splits per syllable block")
    func koreanSplit() {
        #expect(syllableSplit("사랑") == ["사", "랑"])
    }

    @Test("mixed scripts split at the boundary between them")
    func mixedSplit() {
        let units = syllableSplit("Hello さくら")
        #expect(units.joined() == "Hello さくら")
        #expect(units.contains("さ"))
    }

    @Test("splitting always reproduces the original text")
    func splitLossless() {
        for text in ["hello world", "さくらさくら", "Mixed テキスト here", "one"] {
            #expect(syllableSplit(text).joined() == text, "lost text for: \(text)")
        }
    }

    @Test("empty text yields no tokens")
    func emptySplit() {
        #expect(syllableSplit("").isEmpty)
    }

    // ── even distribution ───────────────────────────────────────────────────

    @Test("even tokens are contiguous and span the cue exactly")
    func evenTokens() {
        let c = cue("hello big world", 1, 5)
        let tokens = makeEvenTokens(for: c)
        #expect(tokens.count == 3)
        #expect(tokensAreValid(tokens, for: c))
        #expect(tokens.map(\.text).joined() == c.text)
    }

    @Test("a zero-length or empty cue produces no tokens rather than bad ones")
    func degenerateCue() {
        #expect(makeEvenTokens(for: cue("text", 2, 2)).isEmpty)
        #expect(makeEvenTokens(for: cue("", 0, 4)).isEmpty)
    }

    // ── boundary editing ────────────────────────────────────────────────────

    @Test("moving a boundary adjusts exactly the two neighbours")
    func moveBoundary() {
        let c = cue("a b c", 0, 3)
        let tokens = makeEvenTokens(for: c)
        let moved = moveTokenBoundary(tokens, index: 0, to: 1.5)
        #expect(moved[0].end == 1.5)
        #expect(moved[1].start == 1.5)
        #expect(moved[2] == tokens[2], "an untouched token changed")
        #expect(tokensAreValid(moved, for: c))
    }

    @Test("a boundary can't be dragged past its neighbours")
    func boundaryClamped() {
        let c = cue("a b c", 0, 3)
        let tokens = makeEvenTokens(for: c)
        // Way before the first token's start.
        let tooEarly = moveTokenBoundary(tokens, index: 0, to: -100)
        #expect(tooEarly[0].end > tooEarly[0].start)
        #expect(tokensAreValid(tooEarly, for: c))
        // Way past the second token's end.
        let tooLate = moveTokenBoundary(tokens, index: 0, to: 100)
        #expect(tooLate[1].end > tooLate[1].start)
        #expect(tokensAreValid(tooLate, for: c))
    }

    @Test("an out-of-range boundary index is a no-op")
    func boundaryOutOfRange() {
        let tokens = makeEvenTokens(for: cue("a b", 0, 2))
        #expect(moveTokenBoundary(tokens, index: 5, to: 1) == tokens)
        #expect(moveTokenBoundary(tokens, index: 1, to: 1) == tokens) // no token after the last
    }

    // ── rescaling ───────────────────────────────────────────────────────────

    @Test("rescaling re-anchors tokens onto the cue's new span")
    func rescale() {
        let original = cue("a b c", 0, 3)
        let tokens = makeEvenTokens(for: original)
        let retimed = cue("a b c", 10, 16) // moved and twice as long
        let scaled = rescaleTokens(tokens, to: retimed)
        #expect(tokensAreValid(scaled, for: retimed))
        // Proportions survive: each token still takes a third.
        for token in scaled { #expect(abs((token.end - token.start) - 2) < 0.001) }
    }

    @Test("rescaling a degenerate list leaves it alone")
    func rescaleDegenerate() {
        #expect(rescaleTokens([], to: cue("x")).isEmpty)
        let flat = [SyncToken(text: "x", start: 1, end: 1)]
        #expect(rescaleTokens(flat, to: cue("x", 0, 4)) == flat)
    }

    // ── validation ──────────────────────────────────────────────────────────

    @Test("validation rejects gaps, overlaps and wrong spans")
    func validation() {
        let c = cue("a b", 0, 2)
        #expect(tokensAreValid(makeEvenTokens(for: c), for: c))
        // Gap between tokens.
        #expect(!tokensAreValid([
            SyncToken(text: "a", start: 0, end: 0.5),
            SyncToken(text: "b", start: 1.5, end: 2),
        ], for: c))
        // Doesn't reach the cue's end.
        #expect(!tokensAreValid([
            SyncToken(text: "a", start: 0, end: 0.5),
            SyncToken(text: "b", start: 0.5, end: 1),
        ], for: c))
        #expect(!tokensAreValid([], for: c))
    }
}
