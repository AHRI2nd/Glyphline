// TTML / DFXP adapter (.ttml, .dfxp, .xml) — the delivery standard for
// Netflix, Apple, and broadcast timed text (W3C TTML1, SMPTE-TT profile).
//
// Scope, stated plainly: this handles the TIMED TEXT — cue timings, text with
// line breaks, and the region/style ATTRIBUTES carried per-paragraph. It does
// not attempt TTML's full styling cascade (<styling>/<layout> definitions,
// inheritance, computed values). Those are preserved verbatim in `meta` and
// re-emitted unchanged, so a file round-trips without losing them even though
// the editor doesn't interpret them.
//
// Why hand-rolled rather than XMLParser: subtitle TTML is a narrow, flat
// subset (a <div> of <p> elements) and the round-trip requirement is about
// preserving what we DIDN'T parse — which is far easier to do by capturing raw
// substrings than by rebuilding a full DOM we'd then have to re-serialize
// faithfully. NSXMLParser would also force a delegate-based streaming shape for
// no benefit at this size.

import Foundation

private let ttmlTimeRegex = try! NSRegularExpression(
    pattern: #"^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$"#)
private let ttmlTicksRegex = try! NSRegularExpression(pattern: #"^([\d.]+)(h|m|s|ms|f|t)$"#)

/// TTML time expressions come in two shapes: clock time (`00:00:01.500`) and
/// offset time (`1.5s`, `25f`). Both appear in real deliverables.
func parseTtmlTime(_ raw: String, frameRate: Double?) -> Double? {
    let s = raw.trimmed()
    guard !s.isEmpty else { return nil }
    let ns = s as NSString
    if let m = ttmlTimeRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        let h = Double(group(1)) ?? 0
        let mm = Double(group(2)) ?? 0
        let ss = Double(group(3)) ?? 0
        let frac = group(4)
        let millis = frac.isEmpty ? 0 : (Double(String((frac + "000").prefix(3))) ?? 0)
        return h * 3600 + mm * 60 + ss + millis / 1000
    }
    if let m = ttmlTicksRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
        let value = Double(ns.substring(with: m.range(at: 1))) ?? 0
        switch ns.substring(with: m.range(at: 2)) {
        case "h": return value * 3600
        case "m": return value * 60
        case "s": return value
        case "ms": return value / 1000
        case "f": return frameRate.map { value / $0 } ?? nil
        default: return nil // "t" (ticks) needs a tickRate we don't track
        }
    }
    return nil
}

/// Always emits clock time — the form every consumer accepts.
func formatTtmlTime(_ seconds: Double) -> String {
    let ms = Int((max(0, seconds) * 1000).rounded())
    let h = ms / 3_600_000, m = (ms % 3_600_000) / 60_000
    let s = (ms % 60_000) / 1000, milli = ms % 1000
    func p(_ n: Int, _ w: Int = 2) -> String {
        let str = String(n)
        return str.count >= w ? str : String(repeating: "0", count: w - str.count) + str
    }
    return "\(p(h)):\(p(m)):\(p(s)).\(p(milli, 3))"
}

func decodeXmlEntities(_ s: String) -> String {
    var out = s
    // & LAST on decode so "&amp;lt;" doesn't collapse into "<".
    for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
        out = out.replacingOccurrences(of: entity, with: char)
    }
    return out.replacingOccurrences(of: "&amp;", with: "&")
}

func encodeXmlEntities(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "&", with: "&amp;") // & FIRST on encode
    for (char, entity) in [("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;")] {
        out = out.replacingOccurrences(of: char, with: entity)
    }
    return out
}

/// `<br/>` → newline, other tags stripped, entities decoded.
func ttmlInnerToText(_ inner: String) -> String {
    var t = inner
    t = replaceAllTtml(#"<br\s*/?>"#, t, "\n")
    t = replaceAllTtml(#"<[^>]+>"#, t, "")
    return decodeXmlEntities(t)
        .components(separatedBy: "\n")
        .map { $0.trimmed() }
        .joined(separator: "\n")
        .trimmed()
}

private func replaceAllTtml(_ pattern: String, _ input: String, _ template: String) -> String {
    guard let re = RegexCache.get(pattern, options: [.caseInsensitive]) else { return input }
    let ns = input as NSString
    return re.stringByReplacingMatches(
        in: input, range: NSRange(location: 0, length: ns.length), withTemplate: template)
}

/// Attribute value from a start tag, or nil.
func ttmlAttribute(_ name: String, in tag: String) -> String? {
    guard let re = RegexCache.get(#"(?:^|\s)(?:[\w-]+:)?"# + name + #"\s*=\s*"([^"]*)""#,
                                  options: [.caseInsensitive]) else { return nil }
    let ns = tag as NSString
    guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return ns.substring(with: m.range(at: 1))
}

private let pRegex = try! NSRegularExpression(
    pattern: #"<p\b([^>]*)>(.*?)</p\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
private let headRegex = try! NSRegularExpression(
    pattern: #"<head\b[^>]*>.*?</head\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])

public func parseTtml(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.ttml)
    let text = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM()
    let ns = text as NSString
    let whole = NSRange(location: 0, length: ns.length)

    // frameRate matters for offset times written in frames ("25f").
    if let ttTag = firstMatchGroups(#"(<tt\b[^>]*>)"#, text)?[1],
       let fps = ttmlAttribute("frameRate", in: ttTag).flatMap(Double.init) {
        doc.frameRate = fps
    }
    // <head> holds <styling>/<layout>; kept whole so the editor can re-emit
    // definitions it deliberately doesn't interpret.
    if let m = headRegex.firstMatch(in: text, range: whole) {
        doc.meta["ttmlHead"] = ns.substring(with: m.range)
    }
    if let ttTag = firstMatchGroups(#"(<tt\b[^>]*>)"#, text)?[1] {
        doc.meta["ttmlRoot"] = ttTag
    }

    for m in pRegex.matches(in: text, range: whole) {
        let attrs = ns.substring(with: m.range(at: 1))
        let inner = ns.substring(with: m.range(at: 2))
        guard let begin = ttmlAttribute("begin", in: attrs).flatMap({ parseTtmlTime($0, frameRate: doc.frameRate) })
        else { continue }

        let end: Double
        if let e = ttmlAttribute("end", in: attrs).flatMap({ parseTtmlTime($0, frameRate: doc.frameRate) }) {
            end = e
        } else if let d = ttmlAttribute("dur", in: attrs).flatMap({ parseTtmlTime($0, frameRate: doc.frameRate) }) {
            end = begin + d // dur is the documented alternative to end
        } else {
            continue
        }

        var cue = Cue(id: newCueId(), start: begin, end: end, text: ttmlInnerToText(inner))
        // Presentation attributes we don't model get carried per-cue so they
        // survive a round trip instead of silently vanishing.
        var raw: [String: String] = [:]
        for key in ["region", "style", "agent"] {
            if let v = ttmlAttribute(key, in: attrs) { raw[key] = v }
        }
        if let id = ttmlAttribute("id", in: attrs) { raw["xmlId"] = id }
        if !raw.isEmpty { cue.raw = raw }
        doc.cues.append(cue)
    }
    return doc
}

public func serializeTtml(_ doc: SubtitleDocument) -> String {
    let root = doc.meta["ttmlRoot"]
        ?? #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:tts="http://www.w3.org/ns/ttml#styling" xml:lang="">"#
    let head = doc.meta["ttmlHead"] ?? "<head/>"

    var body = ""
    for cue in sortedCues(doc.cues) {
        var attrs = #" begin="\#(formatTtmlTime(cue.start))" end="\#(formatTtmlTime(cue.end))""#
        if let id = cue.raw?["xmlId"] { attrs += #" xml:id="\#(encodeXmlEntities(id))""# }
        for key in ["region", "style", "agent"] {
            if let v = cue.raw?[key] { attrs += #" \#(key)="\#(encodeXmlEntities(v))""# }
        }
        let inner = cue.text
            .components(separatedBy: "\n")
            .map(encodeXmlEntities)
            .joined(separator: "<br/>")
        body += "      <p\(attrs)>\(inner)</p>\n"
    }

    return """
    <?xml version="1.0" encoding="utf-8"?>
    \(root)
      \(head)
      <body>
        <div>
    \(body)    </div>
      </body>
    </tt>
    """ + "\n"
}
