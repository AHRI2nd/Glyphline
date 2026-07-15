// Shared format-adapter helpers (ported from ../../src/formats/srt.ts sortedCues
// + small utilities used across adapters).

import Foundation

/// Cues in time order (start, then end) — external formats emit in this order.
public func sortedCues(_ cues: [Cue]) -> [Cue] {
    cues.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
}

/// Split `input` on a regex separator (like JS `String.split(regex)`).
func regexSplit(_ pattern: String, _ input: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [input] }
    let ns = input as NSString
    var pieces: [String] = []
    var last = 0
    re.enumerateMatches(in: input, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m = m else { return }
        pieces.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
        last = m.range.location + m.range.length
    }
    pieces.append(ns.substring(from: last))
    return pieces
}

/// True when the whole trimmed string matches the pattern.
func regexTest(_ pattern: String, _ input: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
    let ns = input as NSString
    return re.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) != nil
}

extension String {
    /// Drop a single leading BOM (U+FEFF), matching the adapters' `replace(/^﻿/, "")`.
    func strippingLeadingBOM() -> String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
