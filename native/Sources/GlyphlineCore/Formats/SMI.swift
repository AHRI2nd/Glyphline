// SAMI (.smi) adapter (ported from ../../src/formats/smi.ts).
//
//  - HTML-like, tags are CASE-INSENSITIVE.
//  - START TIME ONLY (ms): a cue's END comes from the NEXT <SYNC>. A blank cue
//    (&nbsp;/empty <P>) means "subtitle off" — a boundary, not a cue.
//  - Multi-language via <P Class=KRCC|ENCC|…>; we edit the dominant class and keep
//    <HEAD>/<STYLE> + the class list in meta for round-trip.
//  - <br> ↔ "\n"; HTML entities decoded/encoded.
//  - Lossy export: only \b \i \u \s \c \fn \fs survive as HTML; everything else is
//    dropped and reported via smiExportLoss so the UI can warn.

import Foundation

private let SMI_DEFAULT_TAIL = 3.0 // seconds when a final cue has no boundary
private let syncRegex = try! NSRegularExpression(
    pattern: #"<sync\b[^>]*\bstart\s*=\s*["']?(\d+)["']?[^>]*>"#, options: [.caseInsensitive])
private let classRegex = try! NSRegularExpression(
    pattern: #"<p\b[^>]*\bclass\s*=\s*["']?([a-z0-9_-]+)["']?"#, options: [.caseInsensitive])
private let headRegex = try! NSRegularExpression(
    pattern: #"<head\b[^>]*>([\s\S]*?)</head>"#, options: [.caseInsensitive])

private struct RawSync {
    var startMs: Int
    var className: String?
    var text: String // decoded plain text ("" for a blank/off marker)
}

public func parseSmi(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.smi)
    let src = raw.replacingOccurrences(of: "\r\n", with: "\n")
    let ns = src as NSString
    let full = NSRange(location: 0, length: ns.length)

    // Preserve <HEAD> verbatim.
    if let h = headRegex.firstMatch(in: src, range: full) {
        doc.meta["smiHead"] = ns.substring(with: h.range(at: 1)).trimmed()
    }

    // Every <SYNC …> with the offset where its inner content starts.
    let syncMatches = syncRegex.matches(in: src, range: full)
    var syncs: [RawSync] = []
    for (i, m) in syncMatches.enumerated() {
        let innerStart = m.range.location + m.range.length
        let innerEnd: Int
        if i + 1 < syncMatches.count {
            // Back up to the '<' that opens the next <SYNC>.
            let nextInner = syncMatches[i + 1].range.location
            innerEnd = max(innerStart, nextInner)
        } else {
            innerEnd = ns.length
        }
        let inner = ns.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart))
        let innerNS = inner as NSString
        var className: String?
        if let c = classRegex.firstMatch(in: inner, range: NSRange(location: 0, length: innerNS.length)) {
            className = innerNS.substring(with: c.range(at: 1))
        }
        syncs.append(RawSync(
            startMs: Int(ns.substring(with: m.range(at: 1))) ?? 0,
            className: className,
            text: smiInnerToText(inner)
        ))
    }

    // Dominant language class (most non-blank entries).
    var classCounts: [String: Int] = [:]
    for s in syncs where !s.text.isEmpty {
        classCounts[s.className ?? "", default: 0] += 1
    }
    var mainClass: String?
    var best = -1
    for (cls, count) in classCounts where count > best {
        best = count
        mainClass = cls.isEmpty ? nil : cls
    }
    if let mainClass { doc.meta["smiMainClass"] = mainClass }

    var seen = Set<String>()
    let allClasses = syncs.compactMap(\.className).filter { seen.insert($0).inserted }
    if !allClasses.isEmpty { doc.meta["smiClasses"] = allClasses.joined(separator: ",") }

    // Cues from the main-class stream; blanks are boundaries, not cues.
    let stream = syncs.filter { $0.className == mainClass || $0.className == nil }
    for (i, cur) in stream.enumerated() {
        if cur.text.isEmpty { continue }
        let start = Double(cur.startMs) / 1000
        let end = i + 1 < stream.count ? Double(stream[i + 1].startMs) / 1000 : start + SMI_DEFAULT_TAIL
        doc.cues.append(Cue(id: newCueId(), start: start, end: end, text: cur.text))
    }
    return doc
}

public func serializeSmi(_ doc: SubtitleDocument) -> String {
    let cls = doc.meta["smiMainClass"] ?? "UNKNOWNCC"
    let head = doc.meta["smiHead"] ?? """
    <TITLE>Glyphline</TITLE>
    <STYLE TYPE="text/css"><!--
    P { font-family: sans-serif; color: white; }
    .\(cls) { Name: Track; lang: ko-KR; }
    --></STYLE>
    """

    var body: [String] = []
    let cues = doc.cues.sorted { $0.start < $1.start }
    for (i, cue) in cues.enumerated() {
        let startMs = Int((cue.start * 1000).rounded())
        let inner = (cue.assSpans?.isEmpty == false)
            ? spansToSmiHtml(cue.assSpans!).html
            : textToSmi(cue.text)
        body.append("<SYNC Start=\(startMs)><P Class=\(cls)>\(inner)")
        // Off marker at this cue's end unless the next cue starts there.
        let endMs = Int((cue.end * 1000).rounded())
        let nextStartMs = i + 1 < cues.count ? Int((cues[i + 1].start * 1000).rounded()) : nil
        if nextStartMs == nil || nextStartMs! > endMs {
            body.append("<SYNC Start=\(endMs)><P Class=\(cls)>&nbsp;")
        }
    }

    return "<SAMI>\n<HEAD>\n\(head)\n</HEAD>\n<BODY>\n\(body.joined(separator: "\n"))\n</BODY>\n</SAMI>\n"
}

private func replaceAll(_ pattern: String, _ input: String, _ template: String) -> String {
    guard let re = RegexCache.get(pattern, options: [.caseInsensitive]) else { return input }
    let ns = input as NSString
    return re.stringByReplacingMatches(
        in: input, range: NSRange(location: 0, length: ns.length), withTemplate: template)
}

private func smiInnerToText(_ inner: String) -> String {
    var t = inner
    t = replaceAll(#"</?(sync|body|sami)\b[^>]*>"#, t, "")
    t = replaceAll(#"<p\b[^>]*>"#, t, "")
    t = replaceAll(#"</p>"#, t, "")
    t = replaceAll(#"<br\s*/?>"#, t, "\n")
    t = replaceAll(#"<[^>]+>"#, t, "") // strip remaining tags
    return decodeEntities(t).trimmed()
}

private func textToSmi(_ text: String) -> String {
    encodeEntities(text).replacingOccurrences(of: "\n", with: "<br>")
}

// ─── ASS spans → SMI HTML (lossy) ─────────────────────────────────────────────

private struct SmiFormatState {
    var b = false, i = false, u = false, s = false
    var color: String?
    var face: String?
    var size: String?
    var drawing = false
}

/// Convert ASS spans to SMI HTML. Representable formatting becomes HTML; the rest
/// (position, animation, karaoke, clip, drawing…) is dropped and recorded.
public func spansToSmiHtml(_ spans: [AssSpan]) -> (html: String, dropped: Set<LossCategory>) {
    var state = SmiFormatState()
    var dropped = Set<LossCategory>()
    var html = ""

    for span in spans {
        if let tags = span.tags { applySmiTags(tags, &state, &dropped) }
        if state.drawing { continue } // drawing coordinates are not text
        let txt = encodeEntities(span.text)
            .replacingOccurrences(of: "\\N", with: "<br>")
            .replacingOccurrences(of: "\\h", with: "&nbsp;")
        if txt.isEmpty { continue }
        html += wrapSmiRun(txt, state)
    }
    return (html, dropped)
}

private func applySmiTags(_ block: String, _ state: inout SmiFormatState, _ dropped: inout Set<LossCategory>) {
    for tag in decodeTags(block) {
        let arg = tag.arg
        switch tag.name {
        case "b": state.b = arg != "0" && !arg.isEmpty
        case "i": state.i = arg != "0" && !arg.isEmpty
        case "u": state.u = arg != "0" && !arg.isEmpty
        case "s": state.s = arg != "0" && !arg.isEmpty
        case "c", "1c": state.color = assColorToHex(arg)
        case "fn": state.face = arg.isEmpty ? nil : arg
        case "fs": state.size = arg.isEmpty ? nil : arg
        case "p":
            state.drawing = (Int(arg) ?? 0) > 0
            if state.drawing { dropped.insert(.drawing) } // the vector shape is lost
        case "pbo":
            break // baseline offset for drawing — ignore quietly
        case "r":
            state = SmiFormatState() // reset formatting
        default:
            if !tag.known || !SMI_REPRESENTABLE.contains(tag.name) {
                dropped.insert(categorizeTag(tag.name))
            }
        }
    }
}

private func wrapSmiRun(_ txt: String, _ s: SmiFormatState) -> String {
    var open: [String] = []
    var close: [String] = []
    var fontAttrs: [String] = []
    if let c = s.color { fontAttrs.append("color=\"\(c)\"") }
    if let f = s.face { fontAttrs.append("face=\"\(f)\"") }
    if let z = s.size { fontAttrs.append("size=\"\(z)\"") }
    if !fontAttrs.isEmpty {
        open.append("<font \(fontAttrs.joined(separator: " "))>")
        close.insert("</font>", at: 0)
    }
    for (flag, tag) in [(s.b, "b"), (s.i, "i"), (s.u, "u"), (s.s, "s")] where flag {
        open.append("<\(tag)>")
        close.insert("</\(tag)>", at: 0)
    }
    return open.joined() + txt + close.joined()
}

/// Categories of ASS information that would be lost exporting this doc to SMI.
public func smiExportLoss(_ doc: SubtitleDocument) -> [LossCategory] {
    var all = Set<LossCategory>()
    for cue in doc.cues {
        guard let spans = cue.assSpans, !spans.isEmpty else { continue }
        all.formUnion(spansToSmiHtml(spans).dropped)
    }
    return Array(all)
}

private func decodeEntities(_ s: String) -> String {
    var t = s
    t = replaceAll(#"&nbsp;"#, t, " ")
    t = replaceAll(#"&lt;"#, t, "<")
    t = replaceAll(#"&gt;"#, t, ">")
    t = replaceAll(#"&quot;"#, t, "\"")
    t = t.replacingOccurrences(of: "&#39;", with: "'")
    t = replaceAll(#"&amp;"#, t, "&")
    return t
}

private func encodeEntities(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
