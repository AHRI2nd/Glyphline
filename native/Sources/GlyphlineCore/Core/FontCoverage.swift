// Glyph coverage check ("does the delivered font actually have every
// character this file uses") — the Netflix-style check that catches a
// subtitle shipping with boxes/tofu wherever the client's font is missing a
// character the text relies on. Two independent pieces:
//
//  1. Decode the UU-encoded blob `doc.fonts` already preserves verbatim (see
//     ASS.swift's header note — until now that data was carried losslessly
//     but never actually read). This is READ-ONLY: the decoded bytes feed the
//     coverage check below and nothing else, so a subtly-wrong decode can at
//     worst produce a wrong/missing warning here, never touch what gets saved
//     or exported — the existing verbatim round-trip is untouched.
//  2. Parse just enough of the TrueType/OpenType container (SFNT table
//     directory + a `cmap` subtable) to get the SET of Unicode code points
//     the font can render, then diff that against the document's text.
//
// Scope: cmap formats 4 (BMP — the overwhelming majority of fonts and of
// subtitle text) and 12 (full Unicode, for fonts that carry supplementary-
// plane glyphs — emoji, rarer CJK). Formats 0/2/6/13/14 (legacy Mac Roman,
// high-byte Asian encodings, last-resort) are not modeled — a font whose ONLY
// cmap subtable uses one of those is reported as having no known coverage
// rather than guessed at, same "documented boundary, not silent guess"
// pattern as the rest of this codebase's format work.

import Foundation

// MARK: - UU decode (Aegisub/ASS convention)

/// Decodes an ASS `[Fonts]`/`[Graphics]` embedded payload: groups of 4
/// characters (each byte's low 6 bits + a +33 offset, no per-line length
/// prefix — the convention Aegisub/libass use, distinct from standard Unix
/// uuencode's +32-with-space-for-zero) decode to 3 bytes each.
public func decodeAssEmbedded(_ data: String) -> Data? {
    var sixBitGroups: [UInt8] = []
    sixBitGroups.reserveCapacity(data.count)
    for ch in data where !ch.isWhitespace {
        guard let ascii = ch.asciiValue, ascii >= 33, ascii <= 33 + 63 else { return nil }
        sixBitGroups.append(ascii - 33)
    }
    var out = [UInt8]()
    out.reserveCapacity(sixBitGroups.count * 3 / 4)
    var i = 0
    while i < sixBitGroups.count {
        let b0 = sixBitGroups[i]
        let b1 = i + 1 < sixBitGroups.count ? sixBitGroups[i + 1] : 0
        out.append((b0 << 2) | (b1 >> 4))
        if i + 2 < sixBitGroups.count {
            let b2 = sixBitGroups[i + 2]
            out.append(((b1 & 0xF) << 4) | (b2 >> 2))
            if i + 3 < sixBitGroups.count {
                let b3 = sixBitGroups[i + 3]
                out.append(((b2 & 0x3) << 6) | b3)
            }
        }
        i += 4
    }
    return Data(out)
}

/// Inverse of `decodeAssEmbedded` — the encode side the font collector (task
/// N) needs to actually embed a resolved system font, using the same
/// Aegisub convention: 3 bytes → 4 chars, no per-line length prefix, wrapped
/// at `lineWidth` characters per line (Aegisub itself uses 80).
public func encodeAssEmbedded(_ data: Data, lineWidth: Int = 80) -> String {
    let bytes = [UInt8](data)
    var chars: [Character] = []
    chars.reserveCapacity((bytes.count + 2) / 3 * 4)
    var i = 0
    while i < bytes.count {
        let b0 = bytes[i]
        let b1 = i + 1 < bytes.count ? bytes[i + 1] : 0
        let b2 = i + 2 < bytes.count ? bytes[i + 2] : 0
        let remaining = bytes.count - i
        var six: [UInt8] = [b0 >> 2, ((b0 & 0x3) << 4) | (b1 >> 4)]
        if remaining >= 2 { six.append(((b1 & 0xF) << 2) | (b2 >> 6)) }
        if remaining >= 3 { six.append(b2 & 0x3F) }
        chars.append(contentsOf: six.map { Character(UnicodeScalar($0 + 33)) })
        i += 3
    }
    guard lineWidth > 0 else { return String(chars) }
    var lines: [String] = []
    var idx = 0
    while idx < chars.count {
        let end = min(idx + lineWidth, chars.count)
        lines.append(String(chars[idx..<end]))
        idx = end
    }
    return lines.joined(separator: "\n")
}

// MARK: - SFNT / cmap parsing

private struct BinReader {
    let data: [UInt8]
    func u16(_ offset: Int) -> UInt16? {
        guard offset + 1 < data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    func u32(_ offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
    func tag(_ offset: Int) -> String? {
        guard offset + 3 < data.count else { return nil }
        return String(bytes: data[offset...offset + 3], encoding: .ascii)
    }
}

/// The set of Unicode scalar values a font's `cmap` claims to cover, or nil
/// if this isn't a parseable SFNT font / has no supported cmap subtable.
public func fontCoveredCodePoints(_ fontData: Data) -> Set<UInt32>? {
    let bytes = [UInt8](fontData)
    let r = BinReader(data: bytes)
    // Table directory: sfVersion(4) numTables(2) searchRange(2) entrySelector(2) rangeShift(2)
    guard let numTables = r.u16(4) else { return nil }
    var cmapOffset: Int?
    for i in 0..<Int(numTables) {
        let recordOffset = 12 + i * 16
        guard r.tag(recordOffset) == "cmap", let off = r.u32(recordOffset + 8) else { continue }
        cmapOffset = Int(off)
        break
    }
    guard let cmapBase = cmapOffset, let subtableCount = r.u16(cmapBase + 2) else { return nil }

    // Prefer a Unicode-covering subtable (platform 3=Windows enc 1=BMP/10=full,
    // or platform 0=Unicode) — pick format 12 over format 4 when both exist,
    // since 12 covers everything 4 does plus supplementary planes.
    var bestOffset: Int?
    var bestFormat: UInt16?
    for i in 0..<Int(subtableCount) {
        let recOff = cmapBase + 4 + i * 8
        guard let platformID = r.u16(recOff), let encodingID = r.u16(recOff + 2),
              let subOff = r.u32(recOff + 4) else { continue }
        let isUnicode = platformID == 0 || (platformID == 3 && (encodingID == 1 || encodingID == 10))
        guard isUnicode else { continue }
        let subtableOffset = cmapBase + Int(subOff)
        guard let format = r.u16(subtableOffset) else { continue }
        guard format == 4 || format == 12 else { continue }
        if bestFormat == nil || (format == 12 && bestFormat == 4) {
            bestFormat = format
            bestOffset = subtableOffset
        }
    }
    guard let offset = bestOffset, let format = bestFormat else { return nil }
    return format == 4 ? parseCmapFormat4(r, at: offset) : parseCmapFormat12(r, at: offset)
}

/// Format 4: segmented BMP coverage (endCode/startCode/idDelta/idRangeOffset
/// parallel arrays). Only the coverage RANGES are needed here, not actual
/// glyph indices, so idRangeOffset is read only to confirm a mapping exists
/// (0xFFFF end-of-table sentinel segment is skipped).
private func parseCmapFormat4(_ r: BinReader, at base: Int) -> Set<UInt32>? {
    guard let segCountX2 = r.u16(base + 6) else { return nil }
    let segCount = Int(segCountX2) / 2
    let endCodeBase = base + 14
    let startCodeBase = endCodeBase + Int(segCountX2) + 2 // +2 skips reservedPad
    var covered = Set<UInt32>()
    for seg in 0..<segCount {
        guard let end = r.u16(endCodeBase + seg * 2), let start = r.u16(startCodeBase + seg * 2) else { continue }
        guard start <= end, end != 0xFFFF || start != 0xFFFF else { continue } // skip terminator segment
        for cp in UInt32(start)...UInt32(end) { covered.insert(cp) }
    }
    return covered
}

/// Format 12: explicit (startCharCode, endCharCode, startGlyphID) groups —
/// the format fonts with supplementary-plane coverage use.
private func parseCmapFormat12(_ r: BinReader, at base: Int) -> Set<UInt32>? {
    guard let numGroups = r.u32(base + 12) else { return nil }
    var covered = Set<UInt32>()
    let groupsBase = base + 16
    for g in 0..<Int(numGroups) {
        let off = groupsBase + g * 12
        guard let start = r.u32(off), let end = r.u32(off + 4), start <= end, end - start < 100_000 else { continue }
        for cp in start...end { covered.insert(cp) }
    }
    return covered
}

// MARK: - Font collection (task N — which fonts does this script actually need)

/// Every font name this document references: each style's Fontname, plus any
/// inline `\fn<name>` override in cue tags. `\fn` with no name (`\fn` alone,
/// meaning "revert to style default") contributes nothing — there's no name
/// to look up.
public func referencedFontNames(_ doc: SubtitleDocument) -> Set<String> {
    var names = Set((doc.styles ?? []).map(\.fontName))
    let pattern = #"\\fn([^\\}]+)"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return names }
    for cue in doc.cues {
        for span in cue.assSpans ?? [] {
            guard let tags = span.tags else { continue }
            let ns = tags as NSString
            re.enumerateMatches(in: tags, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, let r = Range(m.range(at: 1), in: tags) else { return }
                let name = tags[r].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { names.insert(name) }
            }
        }
    }
    names.remove("")
    return names
}

/// Font names referenced but not already present in `doc.fonts` — what the
/// collector needs to go find on the system.
public func missingEmbeddedFonts(_ doc: SubtitleDocument) -> Set<String> {
    let embedded = Set((doc.fonts ?? []).map { ($0.name as NSString).deletingPathExtension })
    return referencedFontNames(doc).subtracting(embedded)
}

// MARK: - Document-level check

public struct FontCoverageIssue: Equatable, Sendable {
    public var fontName: String
    /// nil when the font couldn't be parsed at all (unsupported/unreadable) —
    /// distinct from "parsed fine, these characters are missing".
    public var missingCharacters: [Character]?
}

/// Which characters used anywhere in the document's cue text aren't covered
/// by ANY embedded font — a character present in at least one font isn't
/// flagged, since ASS style assignment (which font applies to which cue) is
/// looser than this check needs to be for a useful first pass.
public func checkFontCoverage(_ doc: SubtitleDocument) -> [FontCoverageIssue] {
    guard let fonts = doc.fonts, !fonts.isEmpty else { return [] }
    let usedChars = Set(doc.cues.flatMap { Array($0.text) }.filter { !$0.isWhitespace })
    guard !usedChars.isEmpty else { return [] }

    var anyParsed = false
    var unionCovered = Set<UInt32>()
    var results: [FontCoverageIssue] = []
    for font in fonts {
        guard let data = decodeAssEmbedded(font.data), let covered = fontCoveredCodePoints(data) else {
            results.append(FontCoverageIssue(fontName: font.name, missingCharacters: nil))
            continue
        }
        anyParsed = true
        unionCovered.formUnion(covered)
    }
    guard anyParsed else { return results }

    let missing = usedChars.filter { ch in
        !ch.unicodeScalars.allSatisfy { unionCovered.contains($0.value) }
    }.sorted()
    if !missing.isEmpty {
        results.append(FontCoverageIssue(fontName: fonts.map(\.name).joined(separator: ", "), missingCharacters: missing))
    }
    return results
}
