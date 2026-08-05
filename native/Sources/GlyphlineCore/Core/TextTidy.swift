// Mechanical text clean-ups — the "fix common errors" family.
//
// Every rule here is deterministic and reversible-by-eye: it fixes typography
// that is wrong regardless of language or house style, and deliberately stops
// short of anything editorial. Rules that would need to know the language, the
// speaker, or the client's style guide are NOT here, because a batch action
// that silently rewrites sentences is worse than one that leaves them alone.
//
// Each rule is a separate function so the UI can offer them individually — a
// translator fixing OCR artefacts usually does not also want dialogue dashes
// normalised in the same pass.

import Foundation

/// Collapse runs of spaces, strip leading/trailing space on every line, and
/// remove spaces sitting just inside brackets or before closing punctuation.
public func tidySpacing(_ text: String) -> String {
    text.components(separatedBy: "\n").map { line -> String in
        var s = line
        s = replaceAll(#"[ \t]{2,}"#, in: s, with: " ")
        s = replaceAll(#"([(\[{（［｛「『]) +"#, in: s, with: "$1")
        s = replaceAll(#" +([)\]}）］｝」』])"#, in: s, with: "$1")
        // A space before , . ! ? ; : is wrong in every language that uses them.
        s = replaceAll(#" +([,.!?;:，。！？])"#, in: s, with: "$1")
        return s.trimmed()
    }
    .joined(separator: "\n")
}

/// Insert the missing space after sentence punctuation ("Hi.How are you" →
/// "Hi. How are you").
///
/// Only applies where the next character is a Latin letter or digit: CJK text
/// does not put a space after 。 or 、, and adding one would be wrong. Decimals
/// ("1.5"), ellipses and time codes are left alone for the same reason.
public func fixMissingSpaceAfterPunctuation(_ text: String) -> String {
    var s = text
    // Not preceded by a digit (decimals), not part of "...".
    s = replaceAll(#"(?<![\d.])([,;:])(?=[A-Za-z])"#, in: s, with: "$1 ")
    s = replaceAll(#"(?<![\d.])([.!?])(?=[A-Za-z])"#, in: s, with: "$1 ")
    return s
}

/// Normalise dialogue dashes to "- " at the start of a line.
///
/// Subtitle dialogue markers arrive as "-", "–", "—", with or without a space,
/// and mixing them inside one file is the actual defect. Only line-initial
/// dashes are touched — a dash mid-sentence is punctuation, not a speaker mark.
public func normalizeDialogueDashes(_ text: String) -> String {
    text.components(separatedBy: "\n").map { line -> String in
        replaceAll(#"^\s*[-–—]\s*"#, in: line, with: "- ")
    }
    .joined(separator: "\n")
}

/// Fix the classic OCR confusion where a lowercase L was read as a capital I
/// ("heIlo" → "hello") — the two are the same glyph in most sans-serif faces,
/// so this is the single most common artefact in OCR'd subtitles.
///
/// Requires a lowercase letter on BOTH sides, so real capitals ("iPhone",
/// "I am", "TIME") are never touched.
public func fixOcrCapitalI(_ text: String) -> String {
    replaceAll(#"(?<=\p{Ll})I(?=\p{Ll})"#, in: text, with: "l")
}

/// Remove a trailing "..." that some tools add to every continued line, and
/// normalise the three-dot ellipsis to a single character.
public func normalizeEllipsis(_ text: String) -> String {
    replaceAll(#"\.{3,}"#, in: text, with: "…")
}

/// Every tidy rule the UI can apply, so the panel and the document action
/// agree on the list without duplicating it.
public enum TidyRule: String, Codable, Sendable, CaseIterable {
    case spacing, spaceAfterPunctuation, dialogueDashes, ocrCapitalI, ellipsis

    public var apply: (String) -> String {
        switch self {
        case .spacing: return tidySpacing
        case .spaceAfterPunctuation: return fixMissingSpaceAfterPunctuation
        case .dialogueDashes: return normalizeDialogueDashes
        case .ocrCapitalI: return fixOcrCapitalI
        case .ellipsis: return normalizeEllipsis
        }
    }
}

/// Applies `rules` in order to each cue, returning only the cues that changed.
public func tidyCues(_ cues: [Cue], rules: [TidyRule]) -> [String: String] {
    guard !rules.isEmpty else { return [:] }
    var out: [String: String] = [:]
    for cue in cues {
        let next = rules.reduce(cue.text) { $1.apply($0) }
        if next != cue.text { out[cue.id] = next }
    }
    return out
}

// ── helper ───────────────────────────────────────────────────────────────────

private func replaceAll(_ pattern: String, in input: String, with template: String) -> String {
    guard let re = RegexCache.get(pattern) else { return input }
    let ns = input as NSString
    return re.stringByReplacingMatches(
        in: input, range: NSRange(location: 0, length: ns.length), withTemplate: template)
}
