// YouTube SubViewer (.sbv) adapter (ported from ../../src/formats/sbv.ts).
//
// Blocks separated by blank lines. First line is "start,end" with H:MM:SS.mmm
// clock times (comma-separated, no arrow); the rest is the text.

import Foundation

public func parseSbv(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.sbv)
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM()
    for block in regexSplit(#"\n\s*\n"#, normalized) {
        var lines = block.components(separatedBy: "\n")
        guard !lines.isEmpty else { continue }
        let timeLine = lines.removeFirst().trimmed()
        guard let comma = timeLine.firstIndex(of: ",") else { continue }
        let startStr = String(timeLine[timeLine.startIndex..<comma]).trimmed()
        let endStr = String(timeLine[timeLine.index(after: comma)...]).trimmed()
        guard let start = parseClockTime(startStr), let end = parseClockTime(endStr) else { continue }
        doc.cues.append(Cue(id: newCueId(), start: start, end: end, text: lines.joined(separator: "\n").trimmed()))
    }
    return doc
}

public func serializeSbv(_ doc: SubtitleDocument) -> String {
    let blocks = sortedCues(doc.cues).map { cue in
        "\(formatVttTime(cue.start)),\(formatVttTime(cue.end))\n\(cue.text)"
    }
    return blocks.joined(separator: "\n\n") + "\n"
}
