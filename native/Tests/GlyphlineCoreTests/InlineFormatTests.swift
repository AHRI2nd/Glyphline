import Testing
@testable import GlyphlineCore

@Suite("Inline formatting")
struct InlineFormatTests {
    @Test("wraps a selection in HTML tags")
    func wrapsHTML() {
        let r = toggleInlineStyle(.italic, in: "hello world", selection: 6..<11, markup: .html)
        #expect(r.text == "hello <i>world</i>")
        // Selection still covers "world", now shifted past the opening tag.
        #expect(String(Array(r.text)[r.selection.lowerBound..<r.selection.upperBound]) == "world")
    }

    @Test("wraps a selection in ASS override tags")
    func wrapsASS() {
        let r = toggleInlineStyle(.bold, in: "hello world", selection: 0..<5, markup: .ass)
        #expect(r.text == "{\\b1}hello{\\b0} world")
    }

    @Test("empty selection formats the whole cue, both lines")
    func emptySelectionWrapsAll() {
        let r = toggleInlineStyle(.italic, in: "line one\nline two", selection: 3..<3, markup: .html)
        #expect(r.text == "<i>line one\nline two</i>")
    }

    @Test("unwraps when the tags are inside the selection")
    func unwrapsInside() {
        let text = "hello <i>world</i>"
        let r = toggleInlineStyle(.italic, in: text, selection: 6..<18, markup: .html)
        #expect(r.text == "hello world")
        #expect(String(Array(r.text)[r.selection.lowerBound..<r.selection.upperBound]) == "world")
    }

    @Test("unwraps when the tags sit just outside the selection")
    func unwrapsOutside() {
        let text = "hello <i>world</i>"
        let r = toggleInlineStyle(.italic, in: text, selection: 9..<14, markup: .html)
        #expect(r.text == "hello world")
        #expect(String(Array(r.text)[r.selection.lowerBound..<r.selection.upperBound]) == "world")
    }

    @Test("apply then remove is a round trip")
    func roundTrip() {
        for markup in [InlineMarkup.html, .ass] {
            for style in InlineStyle.allCases {
                let original = "some text here"
                let on = toggleInlineStyle(style, in: original, selection: 5..<9, markup: markup)
                #expect(on.text != original)
                let off = toggleInlineStyle(style, in: on.text, selection: on.selection, markup: markup)
                #expect(off.text == original)
                #expect(off.selection == 5..<9)
            }
        }
    }

    @Test("plain-text formats are left untouched")
    func noMarkup() {
        #expect(InlineMarkup.forFormat(.txt) == InlineMarkup.none)
        #expect(InlineMarkup.forFormat(.lrc) == InlineMarkup.none)
        #expect(InlineMarkup.forFormat(.sbv) == InlineMarkup.none)
        let r = toggleInlineStyle(.italic, in: "plain", selection: 0..<5, markup: .none)
        #expect(r.text == "plain")
    }

    @Test("markup dialect follows the document format")
    func dialectPerFormat() {
        #expect(InlineMarkup.forFormat(.srt) == .html)
        #expect(InlineMarkup.forFormat(.vtt) == .html)
        #expect(InlineMarkup.forFormat(.smi) == .html)
        #expect(InlineMarkup.forFormat(.ttml) == .html)
        #expect(InlineMarkup.forFormat(.ass) == .ass)
    }

    @Test("out-of-range selections are clamped, not crashed")
    func clampsRange() {
        let r = toggleInlineStyle(.italic, in: "abc", selection: 1..<99, markup: .html)
        #expect(r.text == "a<i>bc</i>")
    }

    @Test("selection with multibyte characters keeps its content")
    func multibyte() {
        let r = toggleInlineStyle(.italic, in: "안녕 세계", selection: 3..<5, markup: .html)
        #expect(r.text == "안녕 <i>세계</i>")
    }
}
