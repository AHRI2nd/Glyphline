// SubRip (.srt) adapter (ported from ../../src/formats/srt.ts).
//
//  - Time: "HH:MM:SS,mmm --> HH:MM:SS,mmm" (tolerate '.' on input, emit ',').
//  - Leading numeric index line dropped on parse, regenerated (1-based) on export.
//  - Multi-line text preserved as "\n". Tokens have no SRT form → dropped on export.

import Foundation

public func parseSrt(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.srt)
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM()
    for block in regexSplit(#"\n\s*\n"#, normalized) {
        var lines = block.components(separatedBy: "\n")
        // Drop a leading numeric index line if present.
        if let first = lines.first, regexTest(#"^\d+$"#, first.trimmed()) { lines.removeFirst() }
        guard !lines.isEmpty else { continue }
        let timeLine = lines.removeFirst()
        guard timeLine.contains("-->") else { continue }
        let parts = timeLine.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseClockTime(parts[0].trimmed()),
              let end = parseClockTime(parts[1].trimmed()) else { continue }
        let text = lines.joined(separator: "\n").trimmed()
        doc.cues.append(Cue(id: newCueId(), start: start, end: end, text: text))
    }
    return doc
}

public func serializeSrt(_ doc: SubtitleDocument) -> String {
    let cues = sortedCues(doc.cues)
    let blocks = cues.enumerated().map { i, cue in
        "\(i + 1)\n\(formatSrtTime(cue.start)) --> \(formatSrtTime(cue.end))\n\(cue.text)"
    }
    return blocks.joined(separator: "\n\n") + "\n"
}
