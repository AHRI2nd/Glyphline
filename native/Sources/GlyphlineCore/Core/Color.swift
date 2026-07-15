// ASS colour helpers (ported from ../../src/utils/color.ts).
//
// ASS stores colours as "&HAABBGGRR" — alpha first, then blue/green/red (reversed
// from RGB). Alpha 00 = opaque, FF = transparent. The UI uses "#RRGGBB", so we
// convert and keep alpha separately.

import Foundation

/// "&H00FFCC00" -> "#00CCFF" (drops alpha). Falls back to white.
public func assColorToHex(_ ass: String) -> String {
    guard let g = firstMatchGroups(#"&H([0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})"#, ass), let bgr = g[2] else {
        return "#FFFFFF"
    }
    let bb = bgr.prefix(2)
    let gg = bgr.dropFirst(2).prefix(2)
    let rr = bgr.dropFirst(4).prefix(2)
    return "#\(rr)\(gg)\(bb)".uppercased()
}

/// Extract the alpha byte ("00" when absent).
public func assAlpha(_ ass: String) -> String {
    guard let g = firstMatchGroups(#"&H([0-9A-Fa-f]{2})[0-9A-Fa-f]{6}"#, ass), let a = g[1] else {
        return "00"
    }
    return a.uppercased()
}

/// "#00CCFF" + alpha -> "&HAABBGGRR".
public func hexToAssColor(_ hex: String, alpha: String = "00") -> String {
    let h = hex.replacingOccurrences(of: "#", with: "")
    let rr = h.prefix(2)
    let gg = h.dropFirst(2).prefix(2)
    let bb = h.dropFirst(4).prefix(2)
    return "&H\(alpha)\(bb)\(gg)\(rr)".uppercased()
}

// First match's capture groups (index 0 = whole match), nil for non-participating.
func firstMatchGroups(_ pattern: String, _ input: String) -> [String?]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = input as NSString
    guard let m = re.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
}
