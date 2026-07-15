// Plain text (.txt) adapter (ported from ../../src/formats/txt.ts).
//
// No timing: on parse, each non-empty line becomes a cue with sequential
// placeholder timing (DEFAULT_DUR each). On export, only cue text is written
// (timing dropped), one cue per block, blank-line separated.

import Foundation

private let TXT_DEFAULT_DUR = 2.0

public func parseTxt(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.txt)
    let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM().components(separatedBy: "\n")
    var t = 0.0
    for line in lines {
        let text = line.trimmed()
        if text.isEmpty { continue }
        doc.cues.append(Cue(id: newCueId(), start: t, end: t + TXT_DEFAULT_DUR, text: text))
        t += TXT_DEFAULT_DUR
    }
    return doc
}

public func serializeTxt(_ doc: SubtitleDocument) -> String {
    sortedCues(doc.cues).map(\.text).joined(separator: "\n\n") + "\n"
}
