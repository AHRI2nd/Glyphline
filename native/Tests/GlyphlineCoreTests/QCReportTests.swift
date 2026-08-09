import Testing
@testable import GlyphlineCore

@Suite("QC report")
struct QCReportTests {
    private func docWithIssues() -> SubtitleDocument {
        var doc = SubtitleDocument()
        doc.cues = [
            Cue(id: "a", start: 1, end: 1.1, text: "too short"),      // durationTooShort
            Cue(id: "b", start: 2, end: 5, text: "fine, no issue here at all in the timing"),
            Cue(id: "c", start: 4.9, end: 6, text: "overlaps b"),      // overlapsPrev
        ]
        return doc
    }

    @Test("only cues with issues appear in the rows")
    func onlyFlaggedRows() {
        let rows = qcReportRows(docWithIssues(), thresholds: DEFAULT_THRESHOLDS)
        #expect(rows.count == 2) // a and c; b is clean
        #expect(rows.map(\.index) == [1, 3])
    }

    @Test("CSV has a header and one row per issue, comma-safe")
    func csvBasic() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 1.1, text: "has, a comma")]
        let csv = generateQCReportCSV(doc, thresholds: DEFAULT_THRESHOLDS)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "index,start,end,text,issues")
        #expect(lines[1].contains("\"has, a comma\""))
    }

    @Test("CSV escapes embedded quotes")
    func csvEscapesQuotes() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 1.1, text: "she said \"hi\"")]
        let csv = generateQCReportCSV(doc, thresholds: DEFAULT_THRESHOLDS)
        #expect(csv.contains("\"she said \"\"hi\"\"\""))
    }

    @Test("a clean document produces a header-only CSV")
    func csvNoIssuesHeaderOnly() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 5, text: "perfectly fine subtitle text here")]
        let csv = generateQCReportCSV(doc, thresholds: DEFAULT_THRESHOLDS)
        #expect(csv.trimmingCharacters(in: .whitespacesAndNewlines) == "index,start,end,text,issues")
    }

    @Test("HTML report includes the issue count and escapes text")
    func htmlBasic() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 1.1, text: "<script>alert(1)</script>")]
        let html = generateQCReportHTML(doc, thresholds: DEFAULT_THRESHOLDS)
        #expect(html.contains("1 issue of 1 cues"))
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("HTML includes font coverage section only when there are font issues")
    func htmlFontSection() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 1.1, text: "x")]
        let withFonts = generateQCReportHTML(doc, thresholds: DEFAULT_THRESHOLDS,
                                             fontIssues: [FontCoverageIssue(fontName: "Foo", missingCharacters: ["漢"])])
        #expect(withFonts.contains("Font Coverage"))
        let without = generateQCReportHTML(doc, thresholds: DEFAULT_THRESHOLDS)
        #expect(!without.contains("Font Coverage"))
    }

    @Test("scene cut crossing shows up as an issue label")
    func crossesCutLabel() {
        var doc = SubtitleDocument()
        doc.cues = [Cue(id: "a", start: 1, end: 5, text: "spans a cut")]
        let csv = generateQCReportCSV(doc, thresholds: DEFAULT_THRESHOLDS, sceneCuts: [3])
        #expect(csv.contains("crosses-cut"))
    }
}
