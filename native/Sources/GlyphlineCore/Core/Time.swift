// Timecode parsing/formatting (ported from ../../src/utils/time.ts).
// Internal time is always float seconds.

import Foundation

/// Clamp to non-negative and round to millisecond precision.
public func clampTime(_ s: Double) -> Double {
    max(0, (s * 1000).rounded() / 1000)
}

private func pad(_ n: Int, _ width: Int = 2) -> String {
    let s = String(n)
    return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
}

/// SRT: `HH:MM:SS,mmm` (comma separator).
public func formatSrtTime(_ seconds: Double) -> String {
    let ms = Int((seconds * 1000).rounded())
    let h = ms / 3_600_000
    let m = (ms % 3_600_000) / 60_000
    let s = (ms % 60_000) / 1000
    let milli = ms % 1000
    return "\(pad(h)):\(pad(m)):\(pad(s)),\(pad(milli, 3))"
}

/// VTT: `HH:MM:SS.mmm` (dot separator).
public func formatVttTime(_ seconds: Double) -> String {
    formatSrtTime(seconds).replacingOccurrences(of: ",", with: ".")
}

/// ASS: `H:MM:SS.cc` (centiseconds).
public func formatAssTime(_ seconds: Double) -> String {
    let cs = Int((seconds * 100).rounded())
    let h = cs / 360_000
    let m = (cs % 360_000) / 6000
    let s = (cs % 6000) / 100
    let centi = cs % 100
    return "\(h):\(pad(m)):\(pad(s)).\(pad(centi))"
}

// Regex helper: index-addressable capture groups (nil for non-participating).
private func regexGroups(_ pattern: String, _ input: String) -> [String?]? {
    guard let re = RegexCache.get(pattern) else { return nil }
    let ns = input as NSString
    guard let m = re.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
}

private func fracMillis(_ frac: String) -> Double {
    Double(String((frac + "000").prefix(3))) ?? 0
}

/// Parse SRT/VTT-style `HH:MM:SS,mmm` / `MM:SS.mmm` (accepts ',' or '.').
public func parseClockTime(_ str: String) -> Double? {
    let t = str.trimmingCharacters(in: .whitespaces)
    guard let g = regexGroups(#"^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})$"#, t) else { return nil }
    let h = Double(g[1] ?? "0") ?? 0
    let mm = Double(g[2] ?? "0") ?? 0
    let ss = Double(g[3] ?? "0") ?? 0
    return h * 3600 + mm * 60 + ss + fracMillis(g[4] ?? "0") / 1000
}

/// Parse ASS `H:MM:SS.cc` (centiseconds).
public func parseAssTime(_ str: String) -> Double? {
    let t = str.trimmingCharacters(in: .whitespaces)
    guard let g = regexGroups(#"^(\d+):(\d{1,2}):(\d{1,2})\.(\d{1,2})$"#, t) else { return nil }
    let h = Double(g[1] ?? "0") ?? 0
    let mm = Double(g[2] ?? "0") ?? 0
    let ss = Double(g[3] ?? "0") ?? 0
    let centi = Double(String(((g[4] ?? "0") + "00").prefix(2))) ?? 0
    return h * 3600 + mm * 60 + ss + centi / 100
}

/// Lenient inline-edit parser for the cue table.
/// Accepts `1:23.45`, `01:23.456`, `00:01:23,456`, `83.4`, `83`.
public func parseTimestampInput(_ input: String) -> Double? {
    let t = input.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return nil }
    if regexGroups(#"^\d+(\.\d+)?$"#, t) != nil { return Double(t) }
    guard let g = regexGroups(#"^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$"#, t) else { return nil }
    let h = Double(g[1] ?? "0") ?? 0
    let mm = Double(g[2] ?? "0") ?? 0
    let ss = Double(g[3] ?? "0") ?? 0
    let millis = g[4].map(fracMillis) ?? 0
    return h * 3600 + mm * 60 + ss + millis / 1000
}

/// Compact display for the cue table: `MM:SS.mmm` (or `H:MM:SS.mmm` past an hour).
public func formatDisplayTime(_ seconds: Double) -> String {
    let full = formatVttTime(seconds)
    return full.hasPrefix("00:") ? String(full.dropFirst(3)) : full
}
