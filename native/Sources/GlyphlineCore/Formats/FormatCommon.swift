// Shared format-adapter helpers (ported from ../../src/formats/srt.ts sortedCues
// + small utilities used across adapters).

import Foundation

/// Cues in time order (start, then end) — external formats emit in this order.
public func sortedCues(_ cues: [Cue]) -> [Cue] {
    cues.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
}

/// Compiled-regex cache keyed by pattern string. `regexSplit`/`regexTest`/
/// `regexGroups`/`firstMatchGroups` all take a pattern as a parameter and get
/// called once per cue (sometimes twice — parseClockTime alone runs per cue
/// for start AND end) while parsing SRT/VTT/SBV/ASS — compiling an
/// NSRegularExpression fresh on every call turned out to dominate parse time
/// entirely: profiling a 5,000-cue SRT file found ~99µs per cue in this exact
/// spot (494ms of a 500ms total), while the actual matching work against a
/// short per-cue string is negligible. Every other regex-using file in this
/// module already avoids this by holding its pattern as a `private let`
/// module constant, compiled once — this does the same thing for the
/// handful of helpers whose pattern varies by call site.
enum RegexCache {
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func get(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        // Keyed on pattern+options together — a bare pattern-string key would
        // silently hand back a case-sensitive regex to a caller that asked
        // for case-insensitive (or vice versa) if the same pattern string
        // were ever reused with different options elsewhere.
        let key = options.isEmpty ? pattern : "\(pattern)#\(options.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = compiled[key] { return existing }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        compiled[key] = re
        return re
    }
}

/// Split `input` on a regex separator (like JS `String.split(regex)`).
func regexSplit(_ pattern: String, _ input: String) -> [String] {
    guard let re = RegexCache.get(pattern) else { return [input] }
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
    guard let re = RegexCache.get(pattern) else { return false }
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
