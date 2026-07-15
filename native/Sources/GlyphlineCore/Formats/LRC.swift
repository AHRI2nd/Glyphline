// LRC (.lrc) lyrics adapter (ported from ../../src/formats/lrc.ts).
//
// Each lyric line is "[mm:ss.xx] text". A cue's end = the next line's start; the
// last line gets a default tail. Metadata tags ([ar:], [ti:], …) are ignored.
// Multi-line text joins with spaces on export (LRC lines are single-line).

import Foundation

private let LRC_LAST_TAIL = 4.0
private let lrcTagRegex = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

public func parseLrc(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.lrc)
    var rows: [(start: Double, text: String)] = []
    for line in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        let ns = line as NSString
        let matches = lrcTagRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { continue } // metadata / blank
        var tags: [Double] = []
        for m in matches {
            let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
            let fracRange = m.range(at: 3)
            let frac = fracRange.location == NSNotFound
                ? 0.0
                : (Double(String((ns.substring(with: fracRange) + "00").prefix(2))) ?? 0) / 100
            tags.append(mm * 60 + ss + frac)
        }
        let text = lrcTagRegex.stringByReplacingMatches(
            in: line, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        ).trimmed()
        for start in tags { rows.append((start, text)) }
    }
    rows.sort { $0.start < $1.start }
    for (i, row) in rows.enumerated() {
        let end = i + 1 < rows.count ? rows[i + 1].start : row.start + LRC_LAST_TAIL
        doc.cues.append(Cue(id: newCueId(), start: row.start, end: end, text: row.text))
    }
    return doc
}

private func lrcTime(_ seconds: Double) -> String {
    let s = max(0, seconds)
    let mm = Int(s / 60)
    let ss = Int(s.truncatingRemainder(dividingBy: 60))
    var cc = Int(((s - s.rounded(.down)) * 100).rounded())
    if cc >= 100 { cc = 99 }
    func p(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return "[\(p(mm)):\(p(ss)).\(p(cc))]"
}

public func serializeLrc(_ doc: SubtitleDocument) -> String {
    let lines = sortedCues(doc.cues).map { cue in
        lrcTime(cue.start) + cue.text.replacingOccurrences(of: "\n", with: " ")
    }
    return lines.joined(separator: "\n") + "\n"
}
