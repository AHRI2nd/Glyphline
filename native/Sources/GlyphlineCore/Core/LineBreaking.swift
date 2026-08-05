// Subtitle line breaking: turn one over-long line into balanced lines, or
// collapse existing lines back into one.
//
// This is the fix for what the quality check already reports — "line too long"
// and "too many lines" were flagged with no way to act on them.
//
// Two things make subtitle line breaking different from ordinary word wrap:
//
//   1. BALANCE, not fill. Greedy fill leaves a long line above a stub
//      ("this is a fairly long first line" / "here."), which reads worse and
//      looks wrong on screen. Subtitlers break for even line lengths, so the
//      split point chosen here is the one that minimises the difference
//      between the resulting lines, not the last one that fits.
//
//   2. Japanese has no spaces. A space-based splitter simply cannot break
//      Japanese text, so it needs character-level breaking constrained by
//      kinsoku shori (禁則処理): a line may not START with closing punctuation
//      (。、」）!?…) and may not END with an opening bracket (「（). Ignoring
//      that produces breaks that native readers see immediately as wrong.
//
// Korean sits in between: it has spaces and prefers them, but a single
// space-less run longer than the limit still has to break somewhere, so it
// falls back to character breaking like Japanese.

import Foundation

/// How a text should be split into lines.
public enum LineBreakStyle: String, Codable, Sendable, CaseIterable {
    /// Break at spaces (English, Korean, most languages).
    case spaced
    /// Break between characters under kinsoku rules (Japanese, Chinese).
    case cjk
    /// Pick per text: CJK when it contains Han/Kana and no spaces to break on.
    case auto
}

/// Characters that may not begin a line (行頭禁則).
private let noLineStart = Set("。、，．・：；？！）〕］｝〉》」』】〙〗»ゝゞーヽヾっゃゅょッャュョ,.!?:;)]}>\"'…‥ー～")
/// Characters that may not end a line (行末禁則).
private let noLineEnd = Set("（〔［｛〈《「『【〘〖«([{<\"'")

private func containsCJK(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
        (0x3040...0x30FF).contains(scalar.value)   // kana
            || (0x4E00...0x9FFF).contains(scalar.value) // han
            || (0x3400...0x4DBF).contains(scalar.value) // han ext A
    }
}

func resolvedStyle(_ style: LineBreakStyle, for text: String) -> LineBreakStyle {
    guard style == .auto else { return style }
    return containsCJK(text) ? .cjk : .spaced
}

/// Collapses every line of `text` into one, normalising the whitespace at the
/// join. The inverse of `breakLines` and the first step inside it — rebalancing
/// starts from the unbroken text, never from wherever the previous break landed.
public func unbreakLines(_ text: String) -> String {
    text.components(separatedBy: "\n")
        .map { $0.trimmed() }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// Rebreaks `text` into at most `maxLines` lines of at most `maxLineLength`
/// characters, as evenly as possible.
///
/// Returns the text unchanged when it already fits on one line — rebreaking
/// something that's fine would churn the document for nothing.
public func breakLines(
    _ text: String,
    maxLineLength: Int,
    maxLines: Int = 2,
    style: LineBreakStyle = .auto
) -> String {
    guard maxLineLength > 0, maxLines > 0 else { return text }
    let flat = unbreakLines(text)
    guard !flat.isEmpty else { return text }
    if flat.count <= maxLineLength { return flat }

    let resolved = resolvedStyle(style, for: flat)
    // How many lines this actually needs, capped — going over the cap is a
    // quality-check problem to report, not a reason to refuse to break.
    let needed = min(maxLines, max(2, Int(ceil(Double(flat.count) / Double(maxLineLength)))))
    return splitEvenly(flat, into: needed, style: resolved).joined(separator: "\n")
}

/// Recursively halves the text at its most balanced legal break point.
private func splitEvenly(_ text: String, into parts: Int, style: LineBreakStyle) -> [String] {
    guard parts > 1, text.count > 1 else { return [text] }
    guard let cut = bestBreakIndex(text, style: style) else { return [text] }

    let head = String(text[text.startIndex..<cut]).trimmed()
    let tail = String(text[cut...]).trimmed()
    guard !head.isEmpty, !tail.isEmpty else { return [text] }

    if parts == 2 { return [head, tail] }
    // Give the remaining splits to whichever side is longer, so three lines
    // don't come out as two short ones and a long one.
    return head.count >= tail.count
        ? splitEvenly(head, into: parts - 1, style: style) + [tail]
        : [head] + splitEvenly(tail, into: parts - 1, style: style)
}

/// The legal break position closest to the middle.
private func bestBreakIndex(_ text: String, style: LineBreakStyle) -> String.Index? {
    let chars = Array(text)
    let middle = chars.count / 2

    var candidates: [Int] = []
    if style == .spaced {
        // Break AFTER a space: index i means the second line starts at i.
        for i in chars.indices where chars[i] == " " { candidates.append(i) }
    }
    if candidates.isEmpty {
        // CJK, or a spaced text with no usable space (one long token).
        for i in 1..<chars.count where isKinsokuLegal(chars, at: i) { candidates.append(i) }
    }
    guard let best = candidates.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return nil }
    return text.index(text.startIndex, offsetBy: best)
}

/// Whether a line may break immediately before `index`.
private func isKinsokuLegal(_ chars: [Character], at index: Int) -> Bool {
    guard index > 0, index < chars.count else { return false }
    if noLineStart.contains(chars[index]) { return false }  // would start a line
    if noLineEnd.contains(chars[index - 1]) { return false } // would end a line
    return true
}

/// Rebreaks every cue that exceeds the limits. Returns the new text per cue id,
/// only for cues that actually changed — callers turn that into one undo entry.
public func rebreakCues(
    _ cues: [Cue],
    maxLineLength: Int,
    maxLines: Int,
    style: LineBreakStyle = .auto
) -> [String: String] {
    var out: [String: String] = [:]
    for cue in cues {
        let next = breakLines(cue.text, maxLineLength: maxLineLength, maxLines: maxLines, style: style)
        if next != cue.text { out[cue.id] = next }
    }
    return out
}

/// Collapses every cue to a single line. Only cues that had a break change.
public func unbreakCues(_ cues: [Cue]) -> [String: String] {
    var out: [String: String] = [:]
    for cue in cues where cue.text.contains("\n") {
        let next = unbreakLines(cue.text)
        if next != cue.text { out[cue.id] = next }
    }
    return out
}
