import Testing
@testable import GlyphlineCore

@Suite("Custom rules")
struct CustomRulesTests {
    @Test("applies a simple literal replacement")
    func literalReplace() {
        let rule = CustomRule(name: "OK not Okay", pattern: "Okay", replacement: "OK")
        #expect(applyCustomRules("Okay, let's go", rules: [rule]) == "OK, let's go")
    }

    @Test("applies multiple rules in order")
    func multipleRulesInOrder() {
        let rules = [
            CustomRule(name: "a", pattern: "foo", replacement: "bar"),
            CustomRule(name: "b", pattern: "bar", replacement: "baz"),
        ]
        #expect(applyCustomRules("foo", rules: rules) == "baz")
    }

    @Test("disabled rules are skipped")
    func disabledRuleSkipped() {
        let rule = CustomRule(name: "x", pattern: "foo", replacement: "bar", enabled: false)
        #expect(applyCustomRules("foo", rules: [rule]) == "foo")
    }

    @Test("case-insensitive flag is honored")
    func caseInsensitive() {
        let rule = CustomRule(name: "x", pattern: "hello", replacement: "hi", caseInsensitive: true)
        #expect(applyCustomRules("HELLO there", rules: [rule]) == "hi there")
    }

    @Test("case-sensitive by default")
    func caseSensitiveByDefault() {
        let rule = CustomRule(name: "x", pattern: "hello", replacement: "hi")
        #expect(applyCustomRules("HELLO there", rules: [rule]) == "HELLO there")
    }

    @Test("regex capture groups work in the replacement template")
    func captureGroups() {
        let rule = CustomRule(name: "x", pattern: #"(\w+), (\w+)"#, replacement: "$2 $1")
        #expect(applyCustomRules("Doe, John", rules: [rule]) == "John Doe")
    }

    @Test("an invalid pattern is skipped, not thrown or crashed")
    func invalidPatternSkipped() {
        let rule = CustomRule(name: "x", pattern: "[unclosed", replacement: "y")
        #expect(applyCustomRules("[unclosed bracket", rules: [rule]) == "[unclosed bracket")
    }

    @Test("an empty pattern is skipped")
    func emptyPatternSkipped() {
        let rule = CustomRule(name: "x", pattern: "", replacement: "y")
        #expect(applyCustomRules("hello", rules: [rule]) == "hello")
    }

    @Test("isValidRulePattern distinguishes compilable from broken regex")
    func validityCheck() {
        #expect(isValidRulePattern(#"\d+"#))
        #expect(!isValidRulePattern("[unclosed"))
    }

    @Test("toCues variant returns only cues whose text actually changed")
    func toCuesOnlyChanged() {
        let cues = [
            Cue(id: "a", start: 0, end: 1, text: "Okay"),
            Cue(id: "b", start: 1, end: 2, text: "fine as is"),
        ]
        let rule = CustomRule(name: "x", pattern: "Okay", replacement: "OK")
        let patches = applyCustomRules(toCues: cues, rules: [rule])
        #expect(patches == ["a": "OK"])
    }

    @Test("toCues with no enabled rules is a no-op, not a wasted scan")
    func toCuesNoEnabledRules() {
        let cues = [Cue(id: "a", start: 0, end: 1, text: "Okay")]
        let rule = CustomRule(name: "x", pattern: "Okay", replacement: "OK", enabled: false)
        #expect(applyCustomRules(toCues: cues, rules: [rule]).isEmpty)
    }
}

@Suite("Custom rules: DocumentModel integration")
struct CustomRulesDocumentModelTests {
    @Test("applies rules and returns the changed count")
    func appliesAndCounts() {
        let doc = DocumentModel()
        doc.loadParsed(SubtitleDocument(cues: [
            Cue(id: "a", start: 0, end: 1, text: "Okay"),
            Cue(id: "b", start: 1, end: 2, text: "Okay too"),
        ]))
        let rule = CustomRule(name: "x", pattern: "Okay", replacement: "OK")
        let n = doc.applyCustomRules([rule])
        #expect(n == 2)
        #expect(doc.doc.cues[0].text == "OK")
        #expect(doc.doc.cues[1].text == "OK too")
    }

    @Test("a no-op application does not push a spurious undo entry")
    func noOpDoesNotPushHistory() {
        let doc = DocumentModel()
        doc.loadParsed(SubtitleDocument(cues: [Cue(id: "a", start: 0, end: 1, text: "unrelated")]))
        let canUndoBefore = doc.canUndo
        let rule = CustomRule(name: "x", pattern: "Okay", replacement: "OK")
        #expect(doc.applyCustomRules([rule]) == 0)
        #expect(doc.canUndo == canUndoBefore)
    }
}
