// QC report export — the quality-issue list QualityIssuesPanel already shows
// on screen, but as a file a reviewer or client can read without the app
// open. Reuses evaluateCue/checkFontCoverage exactly as the panel does, so
// the report can never disagree with what the app itself flags.

import Foundation

public struct QCReportRow: Sendable {
    public var index: Int
    public var start: Double
    public var end: Double
    public var text: String
    public var quality: CueQuality
}

/// Every cue that has at least one issue, in time order — the same set
/// QualityIssuesPanel lists, computed the same way so the two never diverge.
public func qcReportRows(
    _ doc: SubtitleDocument,
    thresholds: QualityThresholds,
    sceneCuts: [Double] = []
) -> [QCReportRow] {
    let sorted = sortedCues(doc.cues)
    return sorted.enumerated().compactMap { i, cue in
        let q = evaluateCue(cue, prev: i > 0 ? sorted[i - 1] : nil, thresholds: thresholds, sceneCuts: sceneCuts)
        guard hasAnyIssue(q) else { return nil }
        return QCReportRow(index: i + 1, start: cue.start, end: cue.end,
                           text: cue.text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "",
                           quality: q)
    }
}

private func issueLabels(_ q: CueQuality) -> [String] {
    var labels: [String] = []
    if q.negativeDuration { labels.append("negative-duration") }
    if q.overlapsPrev { labels.append("overlap") }
    if q.durationTooShort { labels.append("too-short") }
    if q.durationTooLong { labels.append("too-long") }
    if q.cpsTooHigh { labels.append("cps-high") }
    if q.lineTooLong { labels.append("line-too-long") }
    if q.tooManyLines { labels.append("too-many-lines") }
    if q.crossesCut { labels.append("crosses-cut") }
    return labels
}

private func csvField(_ s: String) -> String {
    guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

public func generateQCReportCSV(
    _ doc: SubtitleDocument,
    thresholds: QualityThresholds,
    sceneCuts: [Double] = []
) -> String {
    var lines = ["index,start,end,text,issues"]
    for row in qcReportRows(doc, thresholds: thresholds, sceneCuts: sceneCuts) {
        let fields = [
            String(row.index),
            formatDisplayTime(row.start),
            formatDisplayTime(row.end),
            csvField(row.text),
            csvField(issueLabels(row.quality).joined(separator: "; ")),
        ]
        lines.append(fields.joined(separator: ","))
    }
    return lines.joined(separator: "\n") + "\n"
}

private func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

public func generateQCReportHTML(
    _ doc: SubtitleDocument,
    thresholds: QualityThresholds,
    sceneCuts: [Double] = [],
    fontIssues: [FontCoverageIssue] = [],
    title: String = "QC Report"
) -> String {
    let rows = qcReportRows(doc, thresholds: thresholds, sceneCuts: sceneCuts)
    var rowsHTML = ""
    for row in rows {
        let badges = issueLabels(row.quality).map { "<span class=\"badge\">\(htmlEscape($0))</span>" }.joined(separator: " ")
        rowsHTML += """
        <tr><td>\(row.index)</td><td>\(formatDisplayTime(row.start)) → \(formatDisplayTime(row.end))</td>\
        <td>\(htmlEscape(row.text))</td><td>\(badges)</td></tr>\n
        """
    }
    var fontHTML = ""
    if !fontIssues.isEmpty {
        let items = fontIssues.map { issue -> String in
            if let missing = issue.missingCharacters {
                return "<li>\(htmlEscape(issue.fontName)): missing \(htmlEscape(String(missing)))</li>"
            }
            return "<li>\(htmlEscape(issue.fontName)): could not be parsed</li>"
        }.joined(separator: "\n")
        fontHTML = "<h2>Font Coverage</h2><ul>\(items)</ul>"
    }
    return """
    <!doctype html><html><head><meta charset="utf-8"><title>\(htmlEscape(title))</title>
    <style>
    body{font:14px -apple-system,sans-serif;margin:2em;color:#222}
    table{border-collapse:collapse;width:100%}
    th,td{border:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}
    th{background:#f5f5f5}
    .badge{display:inline-block;background:#fde68a;color:#7c4a03;border-radius:3px;padding:1px 6px;margin:1px;font-size:11px}
    </style></head><body>
    <h1>\(htmlEscape(title))</h1>
    <p>\(rows.count) issue\(rows.count == 1 ? "" : "s") of \(doc.cues.count) cues.</p>
    \(fontHTML)
    <h2>Issues</h2>
    <table><thead><tr><th>#</th><th>Time</th><th>Text</th><th>Issues</th></tr></thead>
    <tbody>
    \(rowsHTML)
    </tbody></table>
    </body></html>
    """
}
