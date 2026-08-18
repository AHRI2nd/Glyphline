// IMSC1 Text Profile (.ttml) — the W3C TTML profile streaming platforms
// (Netflix and others) actually validate delivery against, as opposed to the
// loose/general TTML.swift adapter which happily round-trips whatever a file
// already had. Confirmed against the W3C `ttml-imsc1.1` recommendation
// directly (not from memory, not from a second-hand summary):
//   - required namespaces: xmlns / xmlns:ttp / xmlns:tts
//   - ttp:contentProfiles SHOULD name the IMSC1.1 text profile URI
//   - regions, if present, must use tts:origin/tts:extent, and a synchronic
//     document may have at most 4 of them
//
// This adapter only ever uses ONE region, so the ≤4 constraint is satisfied
// by construction — there's nothing to warn about the way SMI export warns
// about dropped ASS tags (see SMI.swift's smiExportLoss), so no equivalent
// warning path exists here.
//
// Import is NOT separately implemented: IMSC1 is a constrained subset of
// TTML, so the general parseTtml (TTML.swift) already reads it correctly.
// This file only adds a conformant SERIALIZER, registered as its own
// SubFormat so "export as IMSC1" is a distinct, explicit choice from
// "export as (loose) TTML".

import Foundation

public func serializeImsc1(_ doc: SubtitleDocument) -> String {
    var body = ""
    for cue in sortedCues(doc.cues) {
        let inner = cue.text
            .components(separatedBy: "\n")
            .map(encodeXmlEntities)
            .joined(separator: "<br/>")
        body += #"      <p begin="\#(formatTtmlTime(cue.start))" end="\#(formatTtmlTime(cue.end))" region="subtitleRegion">\#(inner)</p>"# + "\n"
    }

    // xml:lang left empty, matching this project's existing plain-TTML
    // fallback root (TTML.swift) — IMSC1 doesn't mandate a non-empty value
    // ("not explicitly mandated" per spec), and SubtitleDocument has no
    // field for the ORIGINAL text's language (translationLanguages tracks
    // only translations). A future version could thread the active
    // translation language through here for translated exports.
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" xmlns:tts="http://www.w3.org/ns/ttml#styling" ttp:contentProfiles="http://www.w3.org/ns/ttml/profile/imsc1.1/text" xml:lang="">
      <head>
        <layout>
          <region xml:id="subtitleRegion" tts:origin="10% 80%" tts:extent="80% 20%" tts:displayAlign="after" tts:textAlign="center"/>
        </layout>
      </head>
      <body>
        <div>
    \(body)    </div>
      </body>
    </tt>
    """ + "\n"
}
