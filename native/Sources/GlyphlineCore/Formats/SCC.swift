// Scenarist_SCC (CEA-608 "line 21" closed captions) — the plain-text hex
// interchange format most US broadcast/OTT delivery pipelines expect for
// captions. NOT the same thing as MCC (SMPTE 2052, a CEA-708/DTVCC container
// that also happens to use hex-per-line text): MCC wraps a materially
// different packet structure (708 service blocks, not 608 byte pairs) and is
// deliberately out of scope here — same class of documented boundary as
// FrameTime.swift's NDF-only limitation, not an oversight.
//
// Every control-code byte value, the character table, and the PAC row table
// below were NOT reconstructed from memory: they were cross-checked against
// pycaption (an independent, widely-used open-source implementation) and
// verified end-to-end by round-tripping a real file through ffmpeg's
// (also-independent) `eia_608` decoder before this file was written — see the
// task notes for the exact commands. Two implementations agreeing on both the
// byte encoding AND the decoded text is a materially stronger correctness
// signal than a single hand-derived implementation would be, which matters
// here: a wrong control-code byte wouldn't fail loudly, it would silently
// produce a file that shows the wrong captions (or none) in a real decoder.
//
// Model: POP-ON captioning (by far the dominant convention for delivery
// captions — the alternative, roll-up, is a live-broadcast technique this app
// has no reason to emit). One "event" = ERASE the off-screen buffer, load new
// text into it row by row via Preamble Address Codes, ERASE the on-screen
// buffer, then SWAP (the newly-loaded text becomes visible). A cue's start is
// the timecode of that swap; its end is the timecode of the next erase.

import Foundation

// MARK: - CEA-608 Basic North American Character Set (non-ASCII substitutions)

private let sccBasicCharTable: [UInt8: Character] = [
    0x2A: "á", 0x5C: "é", 0x5E: "í", 0x5F: "ó", 0x60: "ú",
    0x7B: "ç", 0x7C: "÷", 0x7D: "Ñ", 0x7E: "ñ",
]
private let sccBasicCharReverse: [Character: UInt8] =
    Dictionary(uniqueKeysWithValues: sccBasicCharTable.map { ($1, $0) })

// MARK: - Parity

/// CEA-608's odd-parity bit: the high bit is set so the byte's total 1-bit
/// count is odd. A generic, computed rule — not a lookup table — so nothing
/// here depends on remembering individual encoded byte values right.
func sccParity(_ raw: UInt8) -> UInt8 {
    let v = raw & 0x7F
    return v.nonzeroBitCount.isMultiple(of: 2) ? v | 0x80 : v
}
func sccStripParity(_ b: UInt8) -> UInt8 { b & 0x7F }

// MARK: - Control codes (raw, pre-parity)

private let SCC_RCL: (UInt8, UInt8) = (0x14, 0x20) // Resume Caption Loading (selects pop-on mode)
private let SCC_ENM: (UInt8, UInt8) = (0x14, 0x2E) // Erase Non-displayed Memory
private let SCC_EDM: (UInt8, UInt8) = (0x14, 0x2C) // Erase Displayed Memory
private let SCC_EOC: (UInt8, UInt8) = (0x14, 0x2F) // End Of Caption (swap memories)

private func isControlPair(_ a: UInt8, _ b: UInt8) -> Bool { a >= 0x10 && a <= 0x17 }
private func isPACPair(_ a: UInt8, _ b: UInt8) -> Bool { isControlPair(a, b) && b >= 0x40 }

// MARK: - PAC (Preamble Address Code), rows 1-15, no indent/color/italics —
// the byte values already include the parity bit (verified source table).
private let pacHighByRow: [UInt8] = [
    0, 0x91, 0x91, 0x92, 0x92, 0x15, 0x15, 0x16, 0x16, 0x97, 0x97, 0x10, 0x13, 0x13, 0x94, 0x94,
]
private let pacLowByRow: [UInt8] = [
    0, 0xD0, 0x70, 0xD0, 0x70, 0xD0, 0x70, 0xD0, 0x70, 0xD0, 0x70, 0xD0, 0xD0, 0x70, 0xD0, 0x70,
]

private let SCC_FPS = 29.97002997002997 // the universal broadcast rate for line-21 captions

// MARK: - Parse

public func parseScc(_ raw: String) -> SubtitleDocument {
    var doc = SubtitleDocument(format: .scc)
    doc.frameRate = SCC_FPS

    var cues: [Cue] = []
    var currentLine = ""
    var pendingLines: [String] = []
    /// Index (in `cues`) of the most recently opened, still-unclosed cue —
    /// closed by the next EDM. nil once closed or before any cue opens.
    var openCueIndex: Int?

    for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard let tabIdx = line.firstIndex(of: "\t") else { continue } // header / stray blank line
        let tcStr = String(line[..<tabIdx])
        let payload = String(line[line.index(after: tabIdx)...])
        guard let tc = parseFrameTimecode(tcStr, fps: SCC_FPS) ?? parseDropFrameTimecode(tcStr, fps: SCC_FPS)
        else { continue }

        let words = payload.split(separator: " ").compactMap { UInt16($0, radix: 16) }
        var i = 0
        while i < words.count {
            let b1 = sccStripParity(UInt8(words[i] >> 8))
            let b2 = sccStripParity(UInt8(words[i] & 0xFF))
            // Control codes and PACs are conventionally transmitted twice in a
            // row for reliability; treat an immediate repeat as one event.
            if i + 1 < words.count, words[i + 1] == words[i] { i += 1 }

            if isControlPair(b1, b2) {
                if (b1, b2) == SCC_ENM {
                    currentLine = ""; pendingLines = []
                } else if (b1, b2) == SCC_EOC {
                    if !currentLine.isEmpty { pendingLines.append(currentLine) }
                    if !pendingLines.isEmpty {
                        cues.append(Cue(id: newCueId(), start: tc, end: tc, text: pendingLines.joined(separator: "\n")))
                        openCueIndex = cues.count - 1
                    }
                    currentLine = ""; pendingLines = []
                } else if (b1, b2) == SCC_EDM {
                    if let idx = openCueIndex, cues[idx].end <= cues[idx].start {
                        cues[idx].end = tc
                    }
                    openCueIndex = nil
                } else if (b1, b2) == SCC_RCL {
                    // pop-on mode confirmed; nothing to do
                } else if isPACPair(b1, b2), !currentLine.isEmpty {
                    pendingLines.append(currentLine)
                    currentLine = ""
                }
                // Any other control/PAC code (tab offsets, mid-row style,
                // roll-up commands, …) is outside this adapter's scope —
                // skipped, not guessed at.
                i += 1
                continue
            }
            if b1 >= 0x20 { currentLine.append(sccBasicCharTable[b1] ?? Character(UnicodeScalar(b1))) }
            if b2 >= 0x20 { currentLine.append(sccBasicCharTable[b2] ?? Character(UnicodeScalar(b2))) }
            i += 1
        }
    }

    // A caption still open at EOF (file truncated, or the source never sent a
    // trailing erase) keeps whatever end its sentinel currently holds
    // (== start), which downstream code reads as "essentially zero-length"
    // rather than crashing — degraded, not corrupt.
    doc.cues = cues
    return doc
}

// MARK: - Serialize

public func serializeScc(_ doc: SubtitleDocument) -> String {
    let fps = doc.frameRate ?? SCC_FPS
    let dropFrame = doc.timecodeDropFrame && isDropFrameCandidate(fps: fps)
    func tcLabel(_ seconds: Double) -> String {
        dropFrame ? formatDropFrameTimecode(seconds, fps: fps) : formatFrameTimecode(seconds, fps: fps)
    }
    func doubledHex(_ pair: (UInt8, UInt8)) -> String {
        String(format: "%02x%02x", sccParity(pair.0), sccParity(pair.1))
    }

    let cues = sortedCues(doc.cues)
    var out = "Scenarist_SCC V1.0\n\n"

    for (i, cue) in cues.enumerated() {
        var words: [String] = [doubledHex(SCC_ENM), doubledHex(SCC_ENM), doubledHex(SCC_RCL), doubledHex(SCC_RCL)]

        let textLines = cue.text.isEmpty ? [] : cue.text.split(separator: "\n", omittingEmptySubsequences: false)
        // Bottom-anchored: the LAST line sits on row 15, earlier lines climb
        // upward — the standard pop-on stacking convention.
        let startRow = max(1, 15 - textLines.count + 1)
        for (li, textLine) in textLines.enumerated() {
            let row = min(15, startRow + li)
            let pacHex = String(format: "%02x%02x", pacHighByRow[row], pacLowByRow[row])
            words.append(pacHex); words.append(pacHex)

            var bytes = textLine.map { sccBasicCharReverse[$0] ?? ($0.asciiValue ?? UInt8(ascii: " ")) }
            if bytes.count.isOdd { bytes.append(0) }
            var j = 0
            while j < bytes.count {
                words.append(String(format: "%02x%02x", sccParity(bytes[j]), sccParity(bytes[j + 1])))
                j += 2
            }
        }
        words.append(doubledHex(SCC_EDM)); words.append(doubledHex(SCC_EDM))
        words.append(doubledHex(SCC_EOC)); words.append(doubledHex(SCC_EOC))
        out += "\(tcLabel(cue.start))\t\(words.joined(separator: " "))\n\n"

        // A standalone erase turns the caption off at its end time. Skipped
        // when the next cue starts at (or before) that instant — its own
        // ENM/RCL/…/EDM/EOC block already erases at that timecode, so a
        // second erase there would be a redundant, zero-effect duplicate.
        let nextStart = i + 1 < cues.count ? cues[i + 1].start : nil
        if nextStart == nil || nextStart! > cue.end + 1e-6 {
            out += "\(tcLabel(cue.end))\t\(doubledHex(SCC_EDM)) \(doubledHex(SCC_EDM))\n\n"
        }
    }
    return out
}

private extension Int {
    var isOdd: Bool { !isMultiple(of: 2) }
}
