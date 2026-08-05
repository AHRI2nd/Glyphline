// Advanced SubStation Alpha (.ass / .ssa) adapter (ported from ../../src/formats/ass.ts).
//
//  - Sections: [Script Info], [V4+ Styles], [Events]. A "Format:" line declares the
//    column order; Style:/Dialogue: rows map positionally.
//  - Time: "H:MM:SS.cc". The Text column is LAST and may contain commas → split N-1.
//  - Karaoke "{\k<cs>}" maps to/from Cue.tokens.
//  - [Script Info] + unknown sections preserved in meta; unknown columns in raw.
//  - [Fonts]/[Graphics]: UU-encoded payloads kept VERBATIM (never decoded).

import Foundation

private let DEFAULT_STYLE_FORMAT = [
    "Name", "Fontname", "Fontsize", "PrimaryColour", "SecondaryColour", "OutlineColour",
    "BackColour", "Bold", "Italic", "Underline", "StrikeOut", "ScaleX", "ScaleY",
    "Spacing", "Angle", "BorderStyle", "Outline", "Shadow", "Alignment",
    "MarginL", "MarginR", "MarginV", "Encoding",
]
private let DEFAULT_EVENT_FORMAT = [
    "Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text",
]

private let sectionRegex = try! NSRegularExpression(pattern: #"^\[(.+)\]$"#)
private let embedNameRegex = try! NSRegularExpression(pattern: #"^(?:fontname|filename):\s*(.+)$"#, options: [.caseInsensitive])
private let karaokeRegex = try! NSRegularExpression(pattern: #"\{\\k(\d+)\}([^{]*)"#, options: [.caseInsensitive])

// ─── Parse ────────────────────────────────────────────────────────────────────

public func parseAss(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument.empty(.ass)
    doc.styles = []
    let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").strippingLeadingBOM().components(separatedBy: "\n")

    var section = ""
    var styleFormat = DEFAULT_STYLE_FORMAT
    var eventFormat = DEFAULT_EVENT_FORMAT
    var scriptInfo: [String] = []
    // Unknown sections are split by where they sat relative to [Events]:
    // Aegisub writes [Aegisub Project Garbage] before it and [Aegisub Extradata]
    // after it, and dumping both in one bucket at EOF moved the first one and —
    // worse — left Comment: lines stranded under a foreign section header, so a
    // second open/save dropped them entirely.
    var extraBefore: [String] = []
    var extraAfter: [String] = []
    var comments: [String] = []
    var seenEvents = false
    var inUnknownSection = false
    var fonts: [AssEmbedded] = []
    var graphics: [AssEmbedded] = []

    // The embedded file currently being read in a [Fonts]/[Graphics] section.
    var embedIsFont = true
    var embedName: String?
    var embedData: [String] = []
    func flushEmbed() {
        guard let name = embedName else { return }
        let file = AssEmbedded(name: name, data: embedData.joined(separator: "\n"))
        if embedIsFont { fonts.append(file) } else { graphics.append(file) }
        embedName = nil
        embedData = []
    }

    for line in lines {
        let trimmed = line.trimmed()

        if let g = firstMatchGroups(#"^\[(.+)\]$"#, trimmed), let name = g[1] {
            flushEmbed() // a new section ends any open embedded file
            section = name.lowercased()
            if section == "events" { seenEvents = true }
            inUnknownSection = section != "script info" && !section.contains("styles")
                && section != "events" && section != "fonts" && section != "graphics"
            if inUnknownSection {
                if seenEvents { extraAfter.append(line) } else { extraBefore.append(line) }
            }
            continue
        }

        if section == "fonts" || section == "graphics" {
            let ns = trimmed as NSString
            if let m = embedNameRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                flushEmbed()
                embedIsFont = (section == "fonts")
                embedName = ns.substring(with: m.range(at: 1)).trimmed()
                embedData = []
            } else if embedName != nil, !trimmed.isEmpty {
                embedData.append(line)
            }
            continue
        }

        if section == "script info" {
            if !trimmed.isEmpty { scriptInfo.append(line) }
            continue
        }

        if section.contains("styles") {
            if trimmed.lowercased().hasPrefix("format:") {
                styleFormat = splitCsv(String(trimmed.dropFirst("Format:".count)))
            } else if trimmed.lowercased().hasPrefix("style:") {
                doc.styles?.append(parseStyle(String(trimmed.dropFirst("Style:".count)), styleFormat))
            }
            continue
        }

        if section == "events" {
            if trimmed.lowercased().hasPrefix("format:") {
                eventFormat = splitCsv(String(trimmed.dropFirst("Format:".count)))
            } else if trimmed.lowercased().hasPrefix("dialogue:") {
                if let cue = parseDialogue(String(trimmed.dropFirst("Dialogue:".count)), eventFormat) {
                    doc.cues.append(cue)
                }
            } else if !trimmed.isEmpty {
                comments.append(line) // Comment: / other event lines — verbatim
            }
            continue
        }

        // Any other section: keep its BODY too. Previously only the header
        // survived, so Aegisub's linked audio/video paths and extradata were
        // silently dropped on every save.
        if inUnknownSection, !trimmed.isEmpty {
            if seenEvents { extraAfter.append(line) } else { extraBefore.append(line) }
        }
    }

    flushEmbed() // close any embedded file open at EOF

    if !scriptInfo.isEmpty { doc.meta["assScriptInfo"] = scriptInfo.joined(separator: "\n") }
    if !extraBefore.isEmpty { doc.meta["assExtraBefore"] = extraBefore.joined(separator: "\n") }
    if !extraAfter.isEmpty { doc.meta["assExtraAfter"] = extraAfter.joined(separator: "\n") }
    if !comments.isEmpty { doc.meta["assComments"] = comments.joined(separator: "\n") }
    if !fonts.isEmpty { doc.fonts = fonts }
    if !graphics.isEmpty { doc.graphics = graphics }
    doc.meta["assStyleFormat"] = styleFormat.joined(separator: ", ")
    doc.meta["assEventFormat"] = eventFormat.joined(separator: ", ")
    return doc
}

// ─── Serialize ────────────────────────────────────────────────────────────────

public func serializeAss(_ doc: SubtitleDocument) -> String {
    let styleFormat = doc.meta["assStyleFormat"].map { splitCsv($0) } ?? DEFAULT_STYLE_FORMAT
    let eventFormat = doc.meta["assEventFormat"].map { splitCsv($0) } ?? DEFAULT_EVENT_FORMAT
    let styles = (doc.styles?.isEmpty == false) ? doc.styles! : [defaultAssStyle()]

    var parts: [String] = []
    parts.append("[Script Info]")
    parts.append(doc.meta["assScriptInfo"] ?? "ScriptType: v4.00+")
    parts.append("")
    parts.append("[V4+ Styles]")
    parts.append("Format: \(styleFormat.joined(separator: ", "))")
    for st in styles { parts.append("Style: \(serializeStyle(st, styleFormat))") }
    parts.append("")

    // Sections that were between the styles and [Events] on the way in
    // (Aegisub Project Garbage lives here) go back in the same place.
    if let before = doc.meta["assExtraBefore"] {
        parts.append(before)
        parts.append("")
    }

    // Embedded files before [Events] (verbatim → lossless).
    emitEmbedded(&parts, "[Fonts]", "fontname", doc.fonts)
    emitEmbedded(&parts, "[Graphics]", "filename", doc.graphics)

    parts.append("[Events]")
    parts.append("Format: \(eventFormat.joined(separator: ", "))")
    parts.append(contentsOf: eventLines(doc, eventFormat))

    if let after = doc.meta["assExtraAfter"] {
        parts.append("")
        parts.append(after)
    }
    return parts.joined(separator: "\n") + "\n"
}

/// Dialogue lines plus any preserved Comment:/other event lines, merged in time
/// order. Comments MUST be emitted inside [Events] — parked at end of file they
/// landed under whatever section header came last, and re-parsing that put them
/// in an unknown section where they were dropped for good.
private func eventLines(_ doc: SubtitleDocument, _ eventFormat: [String]) -> [String] {
    let dialogue = sortedCues(doc.cues).map {
        (time: $0.start, line: "Dialogue: \(serializeDialogue($0, eventFormat))")
    }
    let comments = (doc.meta["assComments"]?.components(separatedBy: "\n") ?? [])
        .filter { !$0.trimmed().isEmpty }
        .map { (time: commentStartTime($0, eventFormat) ?? .greatestFiniteMagnitude, line: $0) }

    guard !comments.isEmpty else { return dialogue.map(\.line) }
    // Stable merge: a comment sharing a time with a dialogue line stays after
    // it, matching how a karaoke template written above its first line reads
    // back with the same relative ordering.
    return (dialogue + comments)
        .enumerated()
        .sorted { a, b in
            a.element.time != b.element.time ? a.element.time < b.element.time : a.offset < b.offset
        }
        .map(\.element.line)
}

/// Start time of a preserved event line, read positionally from the same
/// Format: row the dialogue uses. nil when it isn't an event row at all.
private func commentStartTime(_ line: String, _ format: [String]) -> Double? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    let body = String(line[line.index(after: colon)...])
    guard let startIdx = format.firstIndex(of: "Start") else { return nil }
    let fields = body.components(separatedBy: ",")
    guard startIdx < fields.count else { return nil }
    return parseAssTime(fields[startIdx].trimmed())
}

private func emitEmbedded(_ parts: inout [String], _ header: String, _ key: String, _ files: [AssEmbedded]?) {
    guard let files, !files.isEmpty else { return }
    parts.append(header)
    for f in files {
        parts.append("\(key): \(f.name)")
        if !f.data.isEmpty { parts.append(f.data) }
    }
    parts.append("")
}

/// Decoded byte size of an ASS-embedded payload, computed from the encoded length
/// without decoding (UU variant: 4 encoded chars ↦ 3 bytes). Display only.
public func embeddedByteSize(_ data: String) -> Int {
    let chars = data.filter { !$0.isWhitespace }.count
    let bytes = (chars / 4) * 3
    let rem = chars % 4
    return bytes + (rem == 3 ? 2 : rem == 2 ? 1 : 0)
}

// ─── Styles ───────────────────────────────────────────────────────────────────

private func parseStyle(_ line: String, _ format: [String]) -> AssStyle {
    let cols = splitCsv(line)
    func get(_ key: String) -> String {
        guard let i = format.firstIndex(of: key), i < cols.count else { return "" }
        return cols[i]
    }
    var rawCols: [String: String] = [:]
    for (i, key) in format.enumerated() { rawCols[key] = i < cols.count ? cols[i] : "" }

    return AssStyle(
        name: get("Name"),
        fontName: get("Fontname"),
        fontSize: Double(get("Fontsize")) ?? 0,
        primaryColour: get("PrimaryColour"),
        outlineColour: get("OutlineColour"),
        backColour: get("BackColour"),
        bold: get("Bold") == "-1",
        italic: get("Italic") == "-1",
        outline: Double(get("Outline")) ?? 0,
        shadow: Double(get("Shadow")) ?? 0,
        alignment: Int(get("Alignment")) ?? 2,
        marginL: Int(get("MarginL")) ?? 0,
        marginR: Int(get("MarginR")) ?? 0,
        marginV: Int(get("MarginV")) ?? 0,
        raw: rawCols
    )
}

private func numStr(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(d)
}

private func serializeStyle(_ st: AssStyle, _ format: [String]) -> String {
    let known: [String: String] = [
        "Name": st.name,
        "Fontname": st.fontName,
        "Fontsize": numStr(st.fontSize),
        "PrimaryColour": st.primaryColour,
        "OutlineColour": st.outlineColour,
        "BackColour": st.backColour,
        "Bold": st.bold ? "-1" : "0",
        "Italic": st.italic ? "-1" : "0",
        "Outline": numStr(st.outline),
        "Shadow": numStr(st.shadow),
        "Alignment": String(st.alignment),
        "MarginL": String(st.marginL),
        "MarginR": String(st.marginR),
        "MarginV": String(st.marginV),
    ]
    return format.map { known[$0] ?? st.raw?[$0] ?? "" }.joined(separator: ",")
}

func defaultAssStyle() -> AssStyle { AssStyle(name: "Default") }

// ─── Events ───────────────────────────────────────────────────────────────────

private func parseDialogue(_ line: String, _ format: [String]) -> Cue? {
    let cols = splitN(line, format.count)
    func get(_ key: String) -> String {
        guard let i = format.firstIndex(of: key), i < cols.count else { return "" }
        return cols[i]
    }

    guard let start = parseAssTime(get("Start")), let end = parseAssTime(get("End")) else { return nil }

    let rawText = get("Text")
    let spans = parseAssText(rawText)
    let tokens = extractKaraoke(rawText, start)

    var raw: [String: String] = [:]
    for key in ["MarginL", "MarginR", "MarginV", "Effect"] {
        let v = get(key)
        if !v.isEmpty { raw[key] = v }
    }

    return Cue(
        id: newCueId(),
        start: start,
        end: end,
        text: spansToPlain(spans),
        tokens: tokens.isEmpty ? nil : tokens,
        assSpans: spans, // every inline override tag preserved verbatim
        style: get("Style").isEmpty ? nil : get("Style"),
        layer: Int(get("Layer")) ?? 0,
        actor: get("Name").isEmpty ? nil : get("Name"),
        raw: raw.isEmpty ? nil : raw
    )
}

private func serializeDialogue(_ cue: Cue, _ format: [String]) -> String {
    let known: [String: String] = [
        "Layer": String(cue.layer ?? 0),
        "Start": formatAssTime(cue.start),
        "End": formatAssTime(cue.end),
        "Style": cue.style ?? "Default",
        "Name": cue.actor ?? "",
        "MarginL": cue.raw?["MarginL"] ?? "0",
        "MarginR": cue.raw?["MarginR"] ?? "0",
        "MarginV": cue.raw?["MarginV"] ?? "0",
        "Effect": cue.raw?["Effect"] ?? "",
        "Text": dialogueText(cue),
    ]
    return format.map { known[$0] ?? "" }.joined(separator: ",")
}

/// Text field priority:
///  1. assSpans whose plain text is unchanged → verbatim reconstruction (lossless;
///     ALL inline override tags survive exactly).
///  2. tokens (karaoke) when there are no spans → render \k tags.
///  3. Edited text → keep the opening override block (line-level \pos/\an/\fad…)
///     and append the edited text; mid-text blocks can't be re-anchored → dropped.
private func dialogueText(_ cue: Cue) -> String {
    if let spans = cue.assSpans, spansToPlain(spans) == cue.text {
        return serializeAssText(spans)
    }
    if let tokens = cue.tokens, !tokens.isEmpty {
        return renderKaraoke(tokens)
    }
    let lead = leadingBlock(cue.assSpans)
    return (lead.map { "{\($0)}" } ?? "") + plainToAssText(cue.text)
}

/// ASS uses "\N" for hard line breaks within the Text field.
private func plainToAssText(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: "\\N")
}

/// Parse "{\k50}Ka{\k30}ra" karaoke into tokens starting at the cue's start.
private func extractKaraoke(_ text: String, _ start: Double) -> [SyncToken] {
    let ns = text as NSString
    let matches = karaokeRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty { return [] }
    var tokens: [SyncToken] = []
    var cursor = start
    for m in matches {
        let durCs = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let syl = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "\\N", with: "\n")
        let end = cursor + durCs / 100
        if !syl.isEmpty { tokens.append(SyncToken(text: syl, start: cursor, end: end)) }
        cursor = end
    }
    return tokens
}

private func renderKaraoke(_ tokens: [SyncToken]) -> String {
    tokens.map { tok in
        let cs = Int(((tok.end - tok.start) * 100).rounded())
        return "{\\k\(cs)}\(tok.text.replacingOccurrences(of: "\n", with: "\\N"))"
    }.joined()
}

// ─── CSV helpers ──────────────────────────────────────────────────────────────

private func splitCsv(_ s: String) -> [String] {
    s.components(separatedBy: ",").map { $0.trimmed() }
}

/// Split into at most n fields; the final field keeps any remaining commas
/// (and is NOT trimmed — leading spaces may be intentional).
private func splitN(_ s: String, _ n: Int) -> [String] {
    var out: [String] = []
    var rest = Substring(s)
    for _ in 0..<max(0, n - 1) {
        guard let idx = rest.firstIndex(of: ",") else {
            out.append(rest.trimmed())
            rest = ""
            continue
        }
        out.append(String(rest[rest.startIndex..<idx]).trimmed())
        rest = rest[rest.index(after: idx)...]
    }
    out.append(String(rest))
    return out
}

private extension Substring {
    func trimmed() -> String { String(self).trimmingCharacters(in: .whitespacesAndNewlines) }
}
