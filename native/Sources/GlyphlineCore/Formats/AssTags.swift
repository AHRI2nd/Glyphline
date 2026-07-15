// ASS inline override-tag handling (ported from ../../src/formats/assTags.ts).
//
// A Dialogue Text field interleaves override blocks "{...}" with literal text.
// We model it as spans (optional tags + the text run that follows), which lets us
// round-trip EVERY tag — known or not — byte-for-byte, while still exposing a
// structured decode for editing/inspection.

import Foundation

/// Standard ASS/SSA override tag names, longest-first so "\alpha" wins over "\a".
let KNOWN_TAGS: [String] = [
    // font
    "fn", "fs", "fscx", "fscy", "fsp", "fe",
    // rotation / shear
    "frx", "fry", "frz", "fr", "fax", "fay",
    // weight / decoration
    "b", "i", "u", "s",
    // border / shadow / blur
    "xbord", "ybord", "bord", "xshad", "yshad", "shad", "be", "blur",
    // colours / alpha
    "1c", "2c", "3c", "4c", "c", "1a", "2a", "3a", "4a", "alpha",
    // alignment / wrap
    "an", "a", "q",
    // karaoke
    "kf", "ko", "kt", "k", "K",
    // position / movement / origin
    "pos", "move", "org",
    // fade
    "fade", "fad",
    // animation / clip
    "t", "iclip", "clip",
    // drawing
    "pbo", "p",
    // reset
    "r",
].sorted { $0.count > $1.count }

let KNOWN_SET = Set(KNOWN_TAGS)

public struct DecodedTag: Equatable, Sendable {
    public var name: String   // e.g. "pos", "b", "1c"
    public var arg: String    // raw argument, e.g. "(100,200)", "1", "&H00FF00&"
    public var known: Bool

    public init(name: String, arg: String, known: Bool) {
        self.name = name
        self.arg = arg
        self.known = known
    }
}

private let blockRegex = try! NSRegularExpression(pattern: #"\{([^}]*)\}"#)
private let drawingRegex = try! NSRegularExpression(pattern: #"\\p(\d+)"#)

/// Split a Dialogue Text field into override/text spans (lossless).
public func parseAssText(_ raw: String) -> [AssSpan] {
    let ns = raw as NSString
    let matches = blockRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty { return [AssSpan(text: raw)] }

    var spans: [AssSpan] = []
    // Literal text before the first override block.
    let firstIdx = matches[0].range.location
    if firstIdx > 0 { spans.append(AssSpan(text: ns.substring(to: firstIdx))) }

    for (i, m) in matches.enumerated() {
        let tags = ns.substring(with: m.range(at: 1))
        let textStart = m.range.location + m.range.length
        let textEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
        let text = ns.substring(with: NSRange(location: textStart, length: textEnd - textStart))
        spans.append(AssSpan(tags: tags, text: text))
    }
    return spans
}

/// Reconstruct the exact Dialogue Text field from spans.
public func serializeAssText(_ spans: [AssSpan]) -> String {
    spans.map { ($0.tags.map { "{\($0)}" } ?? "") + $0.text }.joined()
}

/// True while a span list is inside a vector-drawing region (\p1..\p0).
/// "\pos"/"\pbo" do NOT match (the pattern requires digits).
private func drawingAfter(_ tags: String?, _ current: Bool) -> Bool {
    guard let tags else { return current }
    let ns = tags as NSString
    let ms = drawingRegex.matches(in: tags, range: NSRange(location: 0, length: ns.length))
    guard let last = ms.last else { return current }
    return (Int(ns.substring(with: last.range(at: 1))) ?? 0) > 0
}

/// Editable plain text: drop override blocks and vector-drawing coordinates,
/// normalize hard breaks (\N) and hard spaces (\h).
public func spansToPlain(_ spans: [AssSpan]) -> String {
    var drawing = false
    var out = ""
    for s in spans {
        drawing = drawingAfter(s.tags, drawing)
        if drawing { continue } // skip drawing-command text
        out += s.text
    }
    return out
        .replacingOccurrences(of: "\\N", with: "\n")
        .replacingOccurrences(of: "\\h", with: " ")
}

// ─── Tag categorization (for lossy-export warnings) ───────────────────────────

/// Tags SMI can represent as HTML formatting (handled, not dropped).
public let SMI_REPRESENTABLE: Set<String> = ["b", "i", "u", "s", "c", "1c", "fn", "fs", "r", "p", "pbo"]

public enum LossCategory: String, Codable, Sendable, CaseIterable {
    case position, karaoke, animation, transform, borderShadow, drawing, clip, color, other
}

/// Map an override tag name to a loss category for user-facing warnings.
public func categorizeTag(_ name: String) -> LossCategory {
    if ["pos", "move", "org", "an", "a", "q"].contains(name) { return .position }
    if ["k", "kf", "ko", "kt", "K"].contains(name) { return .karaoke }
    if ["t", "fad", "fade"].contains(name) { return .animation }
    if ["frx", "fry", "frz", "fax", "fay", "fscx", "fscy", "fsp"].contains(name) { return .transform }
    if ["bord", "xbord", "ybord", "shad", "xshad", "yshad", "be", "blur"].contains(name) { return .borderShadow }
    if ["p", "pbo"].contains(name) { return .drawing }
    if ["clip", "iclip"].contains(name) { return .clip }
    if ["2c", "3c", "4c", "alpha", "1a", "2a", "3a", "4a"].contains(name) { return .color }
    return .other
}

/// The opening override block (line-level tags like \pos/\an/\fad), if any.
public func leadingBlock(_ spans: [AssSpan]?) -> String? {
    guard let tags = spans?.first?.tags, !tags.isEmpty else { return nil }
    return tags
}

/// Decode one override block into structured tags. Preserves order and unknown
/// tags (known=false). For UI/inspection — the lossless round-trip reuses the raw
/// block verbatim instead.
public func decodeTags(_ block: String) -> [DecodedTag] {
    let chars = Array(block)
    var out: [DecodedTag] = []
    var i = 0

    while i < chars.count {
        guard chars[i] == "\\" else { i += 1; continue }
        i += 1 // consume backslash

        // Longest-known-prefix match, else read leading letters as an unknown name.
        var name: String?
        for k in KNOWN_TAGS {
            let kc = Array(k)
            if i + kc.count <= chars.count, Array(chars[i..<(i + kc.count)]) == kc {
                name = k
                break
            }
        }
        if name == nil {
            var j = i
            while j < chars.count, chars[j].isLetter { j += 1 }
            name = String(chars[i..<j])
        }
        let nm = name ?? ""

        var j = i + nm.count
        var arg = ""
        if j < chars.count, chars[j] == "(" {
            // Parenthesized arg with nesting (e.g. \t(\frz360), \clip(...)).
            var depth = 0
            var k = j
            while k < chars.count {
                if chars[k] == "(" {
                    depth += 1
                    k += 1
                } else if chars[k] == ")" {
                    depth -= 1
                    k += 1
                    if depth == 0 { break }
                } else {
                    k += 1
                }
            }
            arg = String(chars[j..<k])
            j = k
        } else {
            var k = j
            while k < chars.count, chars[k] != "\\" { k += 1 }
            arg = String(chars[j..<k])
            j = k
        }

        out.append(DecodedTag(name: nm, arg: arg, known: KNOWN_SET.contains(nm)))
        i = j
    }
    return out
}

/// Does this span list carry any override tags? (for UI indicators)
public func hasOverrideTags(_ spans: [AssSpan]?) -> Bool {
    spans?.contains { ($0.tags?.isEmpty == false) } ?? false
}
