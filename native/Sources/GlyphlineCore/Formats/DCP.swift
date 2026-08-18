// DCP subtitle, Interop XML flavor (root element <DCSubtitle>) — the format
// handed off to a DCP mastering house for theatrical delivery. Structure
// confirmed against the original spec directly: Texas Instruments'
// "Subtitle Specification (XML File Format) for DLP Cinema Projection
// Technology" (CineCanvas, Rev C, publicly hosted), not from memory or from
// a GPL reference implementation (Subtitle Edit) — see CLAUDE.md's licensing
// note on why that source is off-limits to consult here.
//
// Export-only. A DCP Interop file also uses the .xml extension, which this
// project already routes to the general TTML adapter on open (see
// Registry.swift) — rather than fight that ambiguity with content-sniffing,
// this format simply isn't opened. Real-world usage is export-then-handoff
// to a mastering vendor anyway, not round-tripping an existing DCP file.

import Foundation

public func serializeDcp(_ doc: SubtitleDocument) -> String {
    var subtitles = ""
    for (index, cue) in sortedCues(doc.cues).enumerated() {
        let lines = cue.text.components(separatedBy: "\n")
        // Spec's VPosition is "percentage of picture height from the edge
        // specified in VAlign" (VAlign="bottom" here) — stack multiple lines
        // upward from a safe-area-ish baseline, last line of text closest to
        // the bottom, matching how subtitles are conventionally read.
        var textElements = ""
        for (lineIndex, line) in lines.reversed().enumerated() {
            let vPosition = 8.0 + Double(lineIndex) * 8.0
            textElements += #"        <Text HAlign="center" VAlign="bottom" VPosition="\#(String(format: "%.1f", vPosition))">\#(encodeXmlEntities(line))</Text>"# + "\n"
        }
        subtitles += """
              <Subtitle SpotNumber="\(index + 1)" TimeIn="\(formatTtmlTime(cue.start))" TimeOut="\(formatTtmlTime(cue.end))" FadeUpTime="20" FadeDownTime="20">
        \(textElements)      </Subtitle>

        """
    }

    // MovieTitle/Language are required by the spec but SubtitleDocument has
    // no fields for either (the filename lives one layer up, in
    // DocumentModel; the document doesn't track its ORIGINAL text's
    // language at all — only translation languages, see
    // Model/Subtitle.swift). Left as clear placeholders a mastering house
    // will fill in/verify anyway, rather than guessing at real values.
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <DCSubtitle Version="1.1">
      <SubtitleID>\(UUID().uuidString.lowercased())</SubtitleID>
      <MovieTitle>Untitled</MovieTitle>
      <ReelNumber>1</ReelNumber>
      <Language>Unspecified</Language>
      <Font Color="FFFFFFFF" Effect="border" EffectColor="FF000000">
    \(subtitles)  </Font>
    </DCSubtitle>
    """ + "\n"
}

/// Unreachable in normal use: `.xml` always resolves to the general TTML
/// adapter first (Registry.swift), and there's no "open as DCP" UI path.
/// Present only to satisfy FormatAdapter's required `parse` closure.
public func parseDcp(_ raw: String) -> SubtitleDocument {
    SubtitleDocument.empty(.dcp)
}
