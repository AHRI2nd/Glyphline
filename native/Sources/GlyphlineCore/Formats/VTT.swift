// WebVTT (.vtt) adapter (ported from ../../src/formats/vtt.ts).
//
//  - Header + NOTE/STYLE/REGION blocks preserved verbatim in meta.vttPreamble.
//  - Cue identifier + settings preserved in cue.raw.
//  - Inline timestamps "<00:00:02.000>" map to/from Cue.tokens (karaoke).

import Foundation

private let inlineTSRegex = try! NSRegularExpression(pattern: #"<(\d{1,2}:)?\d{1,2}:\d{1,2}\.\d{1,3}>"#)

public func parseVtt(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.vtt)
    let text = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM()
    let blocks = regexSplit(#"\n\s*\n"#, text)
    var preamble: [String] = []

    for (bi, rawBlock) in blocks.enumerated() {
        let block = rawBlock.trimmed()
        if block.isEmpty { continue }
        if bi == 0 && block.hasPrefix("WEBVTT") { preamble.append(block); continue }
        if regexTest(#"^(NOTE|STYLE|REGION)\b"#, block) { preamble.append(block); continue }

        var lines = block.components(separatedBy: "\n")
        var identifier: String?
        if let first = lines.first, !first.contains("-->") {
            identifier = first.trimmed()
            lines.removeFirst()
        }
        guard let firstLine = lines.first, firstLine.contains("-->") else { continue }
        let timeLine = lines.removeFirst()

        guard let arrow = timeLine.range(of: "-->") else { continue }
        let startStr = String(timeLine[timeLine.startIndex..<arrow.lowerBound]).trimmed()
        let rest = String(timeLine[arrow.upperBound...]).trimmed()
        var restParts = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let endStr = restParts.isEmpty ? "" : restParts.removeFirst()
        let settings = restParts.joined(separator: " ")

        guard let start = parseClockTime(startStr), let end = parseClockTime(endStr) else { continue }

        let rawText = lines.joined(separator: "\n")
        let tokens = extractVttTokens(rawText, start, end)
        var rawFields: [String: String] = [:]
        if let identifier, !identifier.isEmpty { rawFields["identifier"] = identifier }
        if !settings.isEmpty { rawFields["settings"] = settings }

        doc.cues.append(Cue(
            id: newCueId(),
            start: start,
            end: end,
            text: stripInlineTimestamps(rawText).trimmed(),
            tokens: tokens.isEmpty ? nil : tokens,
            raw: rawFields.isEmpty ? nil : rawFields
        ))
    }

    if !preamble.isEmpty { doc.meta["vttPreamble"] = preamble.joined(separator: "\n\n") }
    return doc
}

public func serializeVtt(_ doc: SubtitleDocument) -> String {
    let header = doc.meta["vttPreamble"] ?? "WEBVTT"
    let parts = sortedCues(doc.cues).map { cue -> String in
        let id = cue.raw?["identifier"].map { "\($0)\n" } ?? ""
        let settings = cue.raw?["settings"].map { " \($0)" } ?? ""
        let body = (cue.tokens?.isEmpty == false) ? renderVttTokens(cue) : cue.text
        return "\(id)\(formatVttTime(cue.start)) --> \(formatVttTime(cue.end))\(settings)\n\(body)"
    }
    return ([header] + parts).joined(separator: "\n\n") + "\n"
}

private func stripInlineTimestamps(_ text: String) -> String {
    let ns = text as NSString
    return inlineTSRegex.stringByReplacingMatches(
        in: text, range: NSRange(location: 0, length: ns.length), withTemplate: ""
    )
}

private func extractVttTokens(_ text: String, _ start: Double, _ end: Double) -> [SyncToken] {
    let ns = text as NSString
    let matches = inlineTSRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty { return [] }
    var tokens: [SyncToken] = []
    var cursor = 0
    var segStart = start
    for m in matches {
        let word = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)).trimmed()
        let tsStr = ns.substring(with: m.range)
        let ts = parseClockTime(String(tsStr.dropFirst().dropLast())) // strip < >
        if !word.isEmpty, let ts {
            tokens.append(SyncToken(text: word, start: segStart, end: ts))
            segStart = ts
        } else if let ts {
            segStart = ts
        }
        cursor = m.range.location + m.range.length
    }
    let tail = ns.substring(from: cursor).trimmed()
    if !tail.isEmpty { tokens.append(SyncToken(text: tail, start: segStart, end: end)) }
    return tokens
}

private func renderVttTokens(_ cue: Cue) -> String {
    guard let toks = cue.tokens else { return cue.text }
    var out = ""
    for (i, tok) in toks.enumerated() {
        if i > 0 { out += "<\(formatVttTime(tok.start))>" }
        out += (i > 0 ? " " : "") + tok.text
    }
    return out
}
