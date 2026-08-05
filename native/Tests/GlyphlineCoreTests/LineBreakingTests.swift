import Testing
@testable import GlyphlineCore

@Suite("Line breaking")
struct LineBreakingTests {
    private func lines(_ s: String) -> [String] { s.components(separatedBy: "\n") }

    // ── unbreak ─────────────────────────────────────────────────────────────

    @Test("unbreak joins lines and normalises the seam")
    func unbreak() {
        #expect(unbreakLines("hello\nworld") == "hello world")
        #expect(unbreakLines("hello  \n  world") == "hello world")
        #expect(unbreakLines("one\n\ntwo") == "one two")
        #expect(unbreakLines("single") == "single")
    }

    // ── spaced (English / Korean) ───────────────────────────────────────────

    @Test("text that already fits is returned unchanged")
    func noChangeWhenShort() {
        let s = "Short enough"
        #expect(breakLines(s, maxLineLength: 42) == s)
    }

    @Test("a long line is split into two balanced lines, not greedily filled")
    func balanced() {
        // 47 chars — a greedy fill at 42 would leave a 5-char orphan line.
        let s = "The quick brown fox jumps over the lazy dog now"
        let out = lines(breakLines(s, maxLineLength: 42))
        #expect(out.count == 2)
        let diff = abs(out[0].count - out[1].count)
        #expect(diff <= 6, "unbalanced: \(out.map(\.count))")
    }

    @Test("breaks land on spaces, never mid-word, for spaced text")
    func breaksOnSpaces() {
        let s = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
        for line in lines(breakLines(s, maxLineLength: 28, style: .spaced)) {
            #expect(!line.hasPrefix(" ") && !line.hasSuffix(" "))
            // Every produced line must be whole words from the original.
            for word in line.split(separator: " ") {
                #expect(s.contains(word), "word '\(word)' was cut apart")
            }
        }
    }

    @Test("rebreaking is idempotent")
    func idempotent() {
        let s = "The quick brown fox jumps over the lazy dog and keeps running"
        let once = breakLines(s, maxLineLength: 32)
        #expect(breakLines(once, maxLineLength: 32) == once)
    }

    @Test("existing breaks are rebalanced, not preserved")
    func rebalances() {
        // Deliberately lopsided input; the result must not keep that split.
        let bad = "The quick brown fox jumps over the lazy\ndog"
        let out = lines(breakLines(bad, maxLineLength: 42))
        #expect(out.count == 2)
        #expect(abs(out[0].count - out[1].count) < 30)
    }

    @Test("maxLines caps the number of lines")
    func capped() {
        let s = String(repeating: "word ", count: 60).trimmed()
        #expect(lines(breakLines(s, maxLineLength: 20, maxLines: 2)).count == 2)
        #expect(lines(breakLines(s, maxLineLength: 20, maxLines: 3)).count == 3)
    }

    // ── CJK / kinsoku ───────────────────────────────────────────────────────

    @Test("Japanese breaks between characters even with no spaces")
    func japaneseBreaks() {
        let s = "今日はとてもいい天気ですから公園へ散歩に行きましょう"
        let out = lines(breakLines(s, maxLineLength: 14))
        #expect(out.count == 2)
        #expect(out.joined() == s, "characters were lost or reordered")
    }

    @Test("a line never starts with closing punctuation (行頭禁則)")
    func kinsokuLineStart() {
        // The natural midpoint falls right before 」, which must not lead a line.
        let s = "彼はこう言った「明日は絶対に来ると約束するよ」だから待とう"
        for line in lines(breakLines(s, maxLineLength: 15)) {
            guard let first = line.first else { continue }
            #expect(!"。、」』）！？・".contains(first), "line began with '\(first)': \(line)")
        }
    }

    @Test("a line never ends with an opening bracket (行末禁則)")
    func kinsokuLineEnd() {
        let s = "そこで彼女は静かに言いました「本当にありがとうございました」"
        for line in lines(breakLines(s, maxLineLength: 15)) {
            guard let last = line.last else { continue }
            #expect(!"「『（【".contains(last), "line ended with '\(last)': \(line)")
        }
    }

    @Test("auto style picks CJK for Japanese and spaces for English")
    func autoDetect() {
        #expect(resolvedStyle(.auto, for: "今日はいい天気") == .cjk)
        #expect(resolvedStyle(.auto, for: "plain english text") == .spaced)
        #expect(resolvedStyle(.spaced, for: "今日はいい天気") == .spaced) // explicit wins
    }

    @Test("Korean uses spaces when it has them")
    func korean() {
        let s = "오늘은 날씨가 아주 좋으니까 공원으로 산책을 나가 봅시다"
        let out = lines(breakLines(s, maxLineLength: 18))
        #expect(out.count >= 2)
        // Space-based, so no line should begin or end mid-token.
        for line in out { #expect(line == line.trimmed()) }
    }

    @Test("a single space-less token longer than the limit still breaks")
    func longToken() {
        let s = String(repeating: "A", count: 60)
        let out = lines(breakLines(s, maxLineLength: 20))
        #expect(out.count >= 2)
        #expect(out.joined() == s)
    }

    // ── document-level helpers ──────────────────────────────────────────────

    @Test("rebreakCues reports only the cues it actually changed")
    func rebreakOnlyChanged() {
        let cues = [
            Cue(id: "short", start: 0, end: 1, text: "fine"),
            Cue(id: "long", start: 1, end: 2, text: "The quick brown fox jumps over the lazy dog now"),
        ]
        let patches = rebreakCues(cues, maxLineLength: 42, maxLines: 2)
        #expect(patches["short"] == nil)
        #expect(patches["long"]?.contains("\n") == true)
    }

    @Test("unbreakCues only touches cues that had a break")
    func unbreakOnlyChanged() {
        let cues = [
            Cue(id: "flat", start: 0, end: 1, text: "one line"),
            Cue(id: "split", start: 1, end: 2, text: "two\nlines"),
        ]
        let patches = unbreakCues(cues)
        #expect(patches["flat"] == nil)
        #expect(patches["split"] == "two lines")
    }

    @Test("degenerate limits are refused rather than mangling the text")
    func degenerate() {
        let s = "some text here"
        #expect(breakLines(s, maxLineLength: 0) == s)
        #expect(breakLines(s, maxLineLength: 10, maxLines: 0) == s)
        #expect(breakLines("", maxLineLength: 10) == "")
    }
}
