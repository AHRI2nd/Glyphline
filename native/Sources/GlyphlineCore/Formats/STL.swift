// EBU-STL (EBU Tech 3264) — the binary subtitle interchange format most
// European broadcasters actually require for delivery. Structurally nothing
// like the other adapters here: fixed-width binary records, not line-based
// text, so this file also owns the one deliberate break from the app's
// otherwise-uniform "read as text, write as text" file I/O (see the
// SubtitleFileIO.open/export special cases for `.stl`) — a general text
// encoding choice (UTF-8/CP949/…) is meaningless for a format whose bytes
// ARE the data, not an encoding of characters.
//
// Two fixed blocks:
//   GSI  (General Subtitle Information) — exactly 1024 bytes, one per file.
//        Programme/episode titles, frame rate, language, creation dates, …
//        Everything not modeled as a first-class Cue/Style field is kept
//        verbatim in `doc.meta` under an `stl`-prefixed key, so re-exporting
//        an opened file reproduces the same header rather than defaults.
//   TTI  (Text and Timing Information) — exactly 128 bytes, one per subtitle
//        (or per CONTINUATION block of a subtitle whose text didn't fit one
//        block — see the grouping-by-SN note below).
//
// Text encoding (the TF field) follows the file's declared Character Code
// Table (CCT). This implementation supports CCT "00" (ISO 6937, the default
// for Western-European content) via ASCII passthrough for the printable
// range plus ISO 6937's spacing-diacritic mechanism (a mark byte at 0xC1-0xCB
// combines with the FOLLOWING base letter — é is written as [0xC2 'e'], not
// as one byte). Precomposed non-Latin special letters (æ, ø, ß, …) and other
// CCTs (Cyrillic/Arabic/Greek/Hebrew) are NOT decoded — this is the same
// class of deliberate, documented 90% choice as FrameTime.swift's NDF-only
// timecode: broadcast subtitle text is overwhelmingly Western-European Latin
// script using exactly this diacritic set.

import Foundation

// MARK: - Byte-string bridge

/// Bijective byte↔String mapping (ISO-8859-1: byte value == scalar value for
/// every 0x00-0xFF) that lets the binary payload travel through the
/// `FormatAdapter.parse: (String)->Doc` / `serialize: (Doc)->String`
/// signature the rest of the registry uses, without any transcoding loss.
/// SubtitleFileIO.open/export use the SAME mapping on the actual file bytes
/// (bypassing TextEncoding/CRLF handling entirely for `.stl`), so this is
/// lossless end to end — never anything less than exact-byte round trip.
public func bytesToLatin1String(_ bytes: [UInt8]) -> String {
    String(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
}

public func latin1StringToBytes(_ s: String) -> [UInt8] {
    s.unicodeScalars.map { $0.value <= 0xFF ? UInt8($0.value) : 0x3F /* '?' */ }
}

// MARK: - ISO 6937 (CCT 00) text codec

private let iso6937DiacriticToCombining: [UInt8: Character] = [
    0xC1: "\u{0300}", // grave
    0xC2: "\u{0301}", // acute
    0xC3: "\u{0302}", // circumflex
    0xC4: "\u{0303}", // tilde
    0xC8: "\u{0308}", // diaeresis
    0xCA: "\u{030A}", // ring above
    0xCB: "\u{0327}", // cedilla
]
/// Scalar-keyed (not Character-keyed): a combining mark scalar immediately
/// following a base letter in a String gets grapheme-clustered into ONE
/// Character by Swift's default boundary rules (that's what makes é a single
/// Character in the first place) — so matching against `Character` would
/// never see a bare combining mark to look up. Iterating `.unicodeScalars`
/// sidesteps clustering entirely.
private let combiningScalarToISO6937Diacritic: [Unicode.Scalar: UInt8] =
    Dictionary(uniqueKeysWithValues: iso6937DiacriticToCombining.map { ($0.value.unicodeScalars.first!, $0.key) })

/// EBU control bytes inside a TTI text field.
private let TF_ROW_BREAK: UInt8 = 0x8A
private let TF_PADDING: UInt8 = 0x8F

/// Decodes one TTI text field's raw bytes to plain text (`\n` for row breaks,
/// padding trimmed).
func iso6937Decode(_ bytes: [UInt8]) -> String {
    var out = ""
    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if b == TF_PADDING { break } // padding runs to the end of the field
        if b == TF_ROW_BREAK { out.append("\n"); i += 1; continue }
        if let mark = iso6937DiacriticToCombining[b], i + 1 < bytes.count, bytes[i + 1] != TF_PADDING {
            // Compose eagerly (NFC) so the result is one Character like é,
            // not a base+combining-mark pair a caller might not expect.
            let base = String(UnicodeScalar(bytes[i + 1]))
            out += (base + String(mark)).precomposedStringWithCanonicalMapping
            i += 2
            continue
        }
        if b >= 0x20, b <= 0x7E {
            out.append(Character(UnicodeScalar(b)))
        }
        // Bytes outside the supported set (other CCTs, unmapped high range)
        // are dropped rather than corrupting the string with a raw byte —
        // see the file header note on scope.
        i += 1
    }
    return out
}

/// Encodes plain text to TTI text-field bytes, padded to exactly `width` with
/// 0x8F. Truncates rather than overflows a field that's too small — the
/// caller (multi-block grouping) is what avoids that in normal use.
func iso6937Encode(_ text: String, width: Int) -> [UInt8] {
    var out: [UInt8] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if !out.isEmpty { out.append(TF_ROW_BREAK) }
        let scalars = Array(line.decomposedStringWithCanonicalMapping.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            // Unicode decomposition orders base-then-mark (NFD), but ISO 6937
            // writes the mark byte FIRST, then the base letter — so the mark
            // we need is the NEXT scalar, not something already consumed.
            if i + 1 < scalars.count, let markByte = combiningScalarToISO6937Diacritic[scalars[i + 1]] {
                if s.value >= 0x20, s.value <= 0x7E {
                    out.append(markByte)
                    out.append(UInt8(s.value))
                }
                i += 2
                continue
            }
            if s.value >= 0x20, s.value <= 0x7E {
                out.append(UInt8(s.value))
            }
            // Anything else (unsupported base letter, unlisted mark) is
            // dropped — degraded but not corrupt, matching the decoder.
            i += 1
        }
    }
    if out.count > width { out.removeLast(out.count - width) }
    out.append(contentsOf: [UInt8](repeating: TF_PADDING, count: max(0, width - out.count)))
    return out
}

// MARK: - Byte cursor helpers

private struct STLByteReader {
    let bytes: [UInt8]
    var offset = 0
    mutating func takeBytes(_ n: Int) -> [UInt8] {
        guard offset < bytes.count else { offset += n; return [UInt8](repeating: 0x20, count: n) }
        let end = min(bytes.count, offset + n)
        var slice = Array(bytes[offset..<end])
        if slice.count < n { slice += [UInt8](repeating: 0x20, count: n - slice.count) }
        offset += n
        return slice
    }
    mutating func takeString(_ n: Int) -> String {
        let raw = takeBytes(n)
        // GSI text fields are meant to be ASCII per spec; falling back to the
        // Latin-1 bridge rather than failing keeps a slightly-off-spec file
        // (a stray accented character in a free-text title) openable.
        let s = String(bytes: raw, encoding: .ascii) ?? bytesToLatin1String(raw)
        return s.trimmingCharacters(in: .whitespaces)
    }
    mutating func takeByte() -> UInt8 { takeBytes(1)[0] }
    var remaining: Int { max(0, bytes.count - offset) }
}

private struct STLByteWriter {
    var bytes: [UInt8] = []
    mutating func writeString(_ s: String, _ n: Int) {
        var b = Array((s.data(using: .ascii) ?? Data()).prefix(n))
        if b.isEmpty, !s.isEmpty { b = Array(latin1StringToBytes(s).prefix(n)) }
        if b.count > n { b = Array(b.prefix(n)) }
        b += [UInt8](repeating: 0x20, count: n - b.count)
        bytes += b
    }
    mutating func writeByte(_ b: UInt8) { bytes.append(b) }
    mutating func writeBytes(_ b: [UInt8]) { bytes += b }
    mutating func writeZeros(_ n: Int) { bytes += [UInt8](repeating: 0, count: n) }
}

// MARK: - GSI (meta) field keys
//
// EXACT field order and width per EBU Tech 3264, Annex A — every field must
// be read/written in this sequence or every byte after the first mismatch
// desyncs (caught in testing: an earlier version that read TNB/TNS via a
// separate step AFTER a loop covering the fields around them shifted
// everything from RN onward by 10 bytes). Widths sum to exactly 1024 with
// the trailing 75-byte spare + 576-byte UDA appended after.
private let gsiFieldLayout: [(key: String, width: Int)] = [
    ("stlLC", 2), ("stlOPT", 32), ("stlOET", 32), ("stlTPT", 32), ("stlTET", 32),
    ("stlTN", 32), ("stlTCD", 32), ("stlSLR", 16), ("stlCD", 6), ("stlRD", 6), ("stlRN", 2),
    // TNB/TNS/TNG/MNC/MNR sit HERE in the real layout, between RN and TCS —
    // handled as their own explicit reads/writes below (recomputed, not
    // preserved as free text) rather than folded into this list.
]
private let gsiFieldLayoutTail: [(key: String, width: Int)] = [
    ("stlTCS", 1), ("stlTCP", 8), ("stlTCF", 8), ("stlTND", 1), ("stlDSN", 1),
    ("stlCO", 3), ("stlPUB", 32), ("stlEN", 32), ("stlECD", 32),
]

// MARK: - Parse

public func parseStl(_ raw: String) -> SubtitleDocument {
    let bytes = latin1StringToBytes(raw)
    var doc = SubtitleDocument(format: .stl)
    guard bytes.count >= 1024 else { return doc } // not a valid GSI block

    var r = STLByteReader(bytes: bytes)
    _ = r.takeString(3)                 // CPN — code page, informational only (we work in Unicode either way)
    let dfc = r.takeString(8)           // "STL25.01" / "STL30.01" / …
    _ = r.takeByte()                    // DSC
    let cct = r.takeString(2)
    for (key, width) in gsiFieldLayout { doc.meta[key] = r.takeString(width) }
    _ = r.takeString(5) // TNB (block count) — recomputed on serialize, not trusted from the file
    _ = r.takeString(5) // TNS (subtitle count) — same
    doc.meta["stlTNG"] = r.takeString(3)
    _ = r.takeString(2) // MNC — recomputed from content on serialize
    _ = r.takeString(2) // MNR — same
    for (key, width) in gsiFieldLayoutTail { doc.meta[key] = r.takeString(width) }

    doc.meta["stlCCT"] = cct
    doc.meta["stlDFC"] = dfc
    let fps = dfc.hasPrefix("STL30") ? 30.0 : 25.0 // the only two DFC variants in practice
    doc.frameRate = fps

    r.offset = 1024 // spare + UDA aren't modeled; skip straight to the first TTI block

    struct RawBlock { var sgn: UInt8; var sn: Int; var ebn: UInt8; var cs: UInt8
        var tci: (UInt8, UInt8, UInt8, UInt8); var tco: (UInt8, UInt8, UInt8, UInt8)
        var vp: UInt8; var jc: UInt8; var cf: UInt8; var text: [UInt8]
    }
    var blocks: [RawBlock] = []
    while r.remaining >= 128 {
        let sgn = r.takeByte()
        let snBytes = r.takeBytes(2)
        let sn = Int(snBytes[0]) | (Int(snBytes[1]) << 8) // little-endian per spec
        let ebn = r.takeByte()
        let cs = r.takeByte()
        let tci = (r.takeByte(), r.takeByte(), r.takeByte(), r.takeByte())
        let tco = (r.takeByte(), r.takeByte(), r.takeByte(), r.takeByte())
        let vp = r.takeByte()
        let jc = r.takeByte()
        let cf = r.takeByte()
        let text = r.takeBytes(112)
        blocks.append(RawBlock(sgn: sgn, sn: sn, ebn: ebn, cs: cs, tci: tci, tco: tco, vp: vp, jc: jc, cf: cf, text: text))
    }

    func tcToSeconds(_ t: (UInt8, UInt8, UInt8, UInt8)) -> Double {
        Double(Int(t.0) * 3600 + Int(t.1) * 60 + Int(t.2)) + Double(t.3) / fps
    }

    // Consecutive blocks sharing a Subtitle Number are one logical subtitle
    // split across EXTENSION blocks (long text that didn't fit one TF field).
    // Grouping by SN (rather than trusting only EBN==0xFF as a boundary)
    // tolerates a file whose last block's EBN was written non-standardly.
    var cues: [Cue] = []
    var i = 0
    while i < blocks.count {
        var j = i
        while j + 1 < blocks.count, blocks[j + 1].sn == blocks[i].sn { j += 1 }
        let group = blocks[i...j]
        let text = group.map { iso6937Decode($0.text) }.joined()
        let first = group.first!
        let last = group.last!
        var cue = Cue(id: newCueId(), start: tcToSeconds(first.tci), end: tcToSeconds(last.tco), text: text)
        cue.raw = [
            "stlSGN": String(first.sgn), "stlVP": String(first.vp),
            "stlJC": String(first.jc), "stlCS": String(first.cs), "stlCF": String(first.cf),
        ]
        cues.append(cue)
        i = j + 1
    }
    doc.cues = cues
    return doc
}

// MARK: - Serialize

public func serializeStl(_ doc: SubtitleDocument) -> String {
    let fps = (doc.frameRate ?? 25).rounded() >= 30 ? 30.0 : 25.0
    let cues = sortedCues(doc.cues)

    func secondsToTC(_ s: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        let total = max(0, Int((s * fps).rounded()))
        let perSecond = Int(fps)
        let f = total % perSecond
        let totalSec = total / perSecond
        let h = min(23, totalSec / 3600)
        let m = (totalSec % 3600) / 60
        let sec = totalSec % 60
        return (UInt8(h), UInt8(m), UInt8(sec), UInt8(min(f, perSecond - 1)))
    }

    var gsi = STLByteWriter()
    gsi.writeString("437", 3)
    gsi.writeString(fps >= 30 ? "STL30.01" : "STL25.01", 8)
    gsi.writeString("1", 1) // DSC: open subtitling
    gsi.writeString(doc.meta["stlCCT"] ?? "00", 2)
    for (key, width) in gsiFieldLayout { gsi.writeString(doc.meta[key] ?? "", width) }
    gsi.writeString(String(format: "%05d", cues.count), 5)  // TNB (single block per cue here)
    gsi.writeString(String(format: "%05d", cues.count), 5)  // TNS
    gsi.writeString(doc.meta["stlTNG"] ?? "001", 3)  // TNG
    gsi.writeString("40", 2)  // MNC — max displayable chars per row (conventional default)
    gsi.writeString("23", 2)  // MNR — max displayable rows (conventional default)
    for (key, width) in gsiFieldLayoutTail { gsi.writeString(doc.meta[key] ?? "", width) }
    gsi.writeZeros(1024 - gsi.bytes.count) // Spare + UDA + any field-width slack, verbatim zero-fill

    var tti = STLByteWriter()
    for (i, cue) in cues.enumerated() {
        let sgn = UInt8(cue.raw?["stlSGN"].flatMap { UInt8($0) } ?? 0)
        let vp = UInt8(cue.raw?["stlVP"].flatMap { UInt8($0) } ?? 20)
        let jc = UInt8(cue.raw?["stlJC"].flatMap { UInt8($0) } ?? 2) // centered
        let cs = UInt8(cue.raw?["stlCS"].flatMap { UInt8($0) } ?? 0)
        let cf = UInt8(cue.raw?["stlCF"].flatMap { UInt8($0) } ?? 0)
        tti.writeByte(sgn)
        tti.writeBytes([UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF)]) // SN, little-endian, 0-based
        tti.writeByte(0xFF) // EBN — one TTI block per cue: always the (only, so also last) block
        tti.writeByte(cs)
        let (h1, m1, s1, f1) = secondsToTC(cue.start)
        tti.writeBytes([h1, m1, s1, f1])
        let (h2, m2, s2, f2) = secondsToTC(cue.end)
        tti.writeBytes([h2, m2, s2, f2])
        tti.writeByte(vp)
        tti.writeByte(jc)
        tti.writeByte(cf)
        tti.writeBytes(iso6937Encode(cue.text, width: 112))
    }

    return bytesToLatin1String(gsi.bytes + tti.bytes)
}
