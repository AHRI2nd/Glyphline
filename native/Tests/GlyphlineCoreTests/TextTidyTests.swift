import Testing
@testable import GlyphlineCore

@Suite("Text tidy rules")
struct TextTidyTests {
    // ── spacing ─────────────────────────────────────────────────────────────

    @Test("runs of spaces collapse and lines are trimmed")
    func spacing() {
        #expect(tidySpacing("hello   world") == "hello world")
        #expect(tidySpacing("  padded  ") == "padded")
        #expect(tidySpacing("a\n   b  ") == "a\nb")
    }

    @Test("spaces just inside brackets and before punctuation are removed")
    func spacingEdges() {
        #expect(tidySpacing("( hi )") == "(hi)")
        #expect(tidySpacing("「 こんにちは 」") == "「こんにちは」")
        #expect(tidySpacing("wait , what ?") == "wait, what?")
    }

    @Test("spacing leaves already-clean text alone")
    func spacingIdempotent() {
        let clean = "Nothing to fix here.\nSecond line."
        #expect(tidySpacing(clean) == clean)
        #expect(tidySpacing(tidySpacing(clean)) == tidySpacing(clean))
    }

    // ── space after punctuation ─────────────────────────────────────────────

    @Test("a missing space after sentence punctuation is inserted")
    func spaceAfterPunct() {
        #expect(fixMissingSpaceAfterPunctuation("Hi.How are you") == "Hi. How are you")
        #expect(fixMissingSpaceAfterPunctuation("one,two") == "one, two")
        #expect(fixMissingSpaceAfterPunctuation("Wait!Stop") == "Wait! Stop")
    }

    @Test("decimals, ellipses and CJK punctuation are left alone")
    func spaceAfterPunctSafety() {
        #expect(fixMissingSpaceAfterPunctuation("1.5 seconds") == "1.5 seconds")
        #expect(fixMissingSpaceAfterPunctuation("wait...what") == "wait...what")
        // Japanese does not put a space after 。 — adding one would be wrong.
        #expect(fixMissingSpaceAfterPunctuation("こんにちは。元気ですか") == "こんにちは。元気ですか")
    }

    // ── dialogue dashes ─────────────────────────────────────────────────────

    @Test("line-initial dashes normalise to '- '")
    func dashes() {
        #expect(normalizeDialogueDashes("-Hello") == "- Hello")
        #expect(normalizeDialogueDashes("–  Hello") == "- Hello")
        #expect(normalizeDialogueDashes("— Hello") == "- Hello")
        #expect(normalizeDialogueDashes("-A\n-B") == "- A\n- B")
    }

    @Test("a mid-sentence dash is punctuation, not a speaker mark")
    func dashesMidLine() {
        let s = "well - maybe not"
        #expect(normalizeDialogueDashes(s) == s)
    }

    // ── OCR capital I ───────────────────────────────────────────────────────

    @Test("a capital I between lowercase letters becomes l")
    func ocrI() {
        // The artefact this fixes is lowercase L read as capital I — they are
        // the same glyph in most sans-serif faces. So the replacement is I→l.
        #expect(fixOcrCapitalI("heIlo") == "hello")
        #expect(fixOcrCapitalI("aIphabet") == "alphabet")
        #expect(fixOcrCapitalI("wiId") == "wild")
    }

    @Test("real capitals are never touched")
    func ocrISafety() {
        #expect(fixOcrCapitalI("I am here") == "I am here")
        #expect(fixOcrCapitalI("iPhone") == "iPhone")   // I not surrounded by lowercase
        #expect(fixOcrCapitalI("TIME") == "TIME")
        #expect(fixOcrCapitalI("Iceland") == "Iceland")
    }

    // ── ellipsis ────────────────────────────────────────────────────────────

    @Test("three or more dots become a single ellipsis character")
    func ellipsis() {
        #expect(normalizeEllipsis("wait...") == "wait…")
        #expect(normalizeEllipsis("hmm.....") == "hmm…")
        #expect(normalizeEllipsis("end.") == "end.")
        #expect(normalizeEllipsis("a..b") == "a..b") // two dots isn't an ellipsis
    }

    // ── document-level ──────────────────────────────────────────────────────

    @Test("tidyCues applies the chosen rules and reports only changed cues")
    func tidyCuesScope() {
        let cues = [
            Cue(id: "dirty", start: 0, end: 1, text: "hello   world , ok"),
            Cue(id: "clean", start: 1, end: 2, text: "already fine"),
        ]
        let patches = tidyCues(cues, rules: [.spacing])
        #expect(patches["dirty"] == "hello world, ok")
        #expect(patches["clean"] == nil)
    }

    @Test("no rules selected changes nothing")
    func noRules() {
        let cues = [Cue(id: "a", start: 0, end: 1, text: "hello   world")]
        #expect(tidyCues(cues, rules: []).isEmpty)
    }

    @Test("rules compose in order without fighting each other")
    func composed() {
        let cues = [Cue(id: "a", start: 0, end: 1, text: "-Hi.There   friend")]
        let patches = tidyCues(cues, rules: [.spacing, .spaceAfterPunctuation, .dialogueDashes])
        #expect(patches["a"] == "- Hi. There friend")
    }
}
