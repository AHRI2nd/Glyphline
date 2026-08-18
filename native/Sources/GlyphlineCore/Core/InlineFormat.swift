// Bold / italic / underline on a text selection.
//
// Subtitle formats carry emphasis as inline markup in the cue text itself, and
// the two families spell it differently: SRT/VTT/SMI/TTML use HTML-ish tags,
// ASS uses override blocks. Typing either by hand is error-prone (`{\i1}` is
// easy to get backwards) and it's the one bit of formatting subtitles actually
// use often, so it gets buttons — and the buttons have to emit the right dialect
// for the document being edited.
//
// Plain-text formats (TXT/LRC/SBV) have no markup at all; `.none` says so, and
// the UI disables the buttons rather than writing tags that would be delivered
// literally as "<i>".

public enum InlineStyle: String, Sendable, CaseIterable {
    case bold, italic, underline
}

public enum InlineMarkup: Sendable, Equatable {
    case html
    case ass
    case none

    public static func forFormat(_ format: SubFormat) -> InlineMarkup {
        switch format {
        case .srt, .vtt, .smi, .ttml, .imsc1: return .html
        case .ass: return .ass
        case .sbv, .lrc, .txt, .stl, .scc, .dcp: return .none
        }
    }

    /// The opening/closing token pair for a style, or nil when this markup
    /// can't express emphasis.
    func tokens(for style: InlineStyle) -> (open: String, close: String)? {
        let letter: String
        switch style {
        case .bold: letter = "b"
        case .italic: letter = "i"
        case .underline: letter = "u"
        }
        switch self {
        case .html: return ("<\(letter)>", "</\(letter)>")
        case .ass: return ("{\\\(letter)1}", "{\\\(letter)0}")
        case .none: return nil
        }
    }
}

public struct InlineEditResult: Equatable, Sendable {
    public var text: String
    /// Character offsets of the still-selected run in the NEW text, so the
    /// caret lands on the same words the user had highlighted rather than
    /// jumping to the start.
    public var selection: Range<Int>

    public init(text: String, selection: Range<Int>) {
        self.text = text
        self.selection = selection
    }
}

/// Wraps the selection in `style`'s tokens, or unwraps it if it's already
/// wrapped — one button that both applies and removes, like every other editor.
///
/// An empty selection acts on the whole cue text: that's the common case
/// ("this whole line is a thought spoken aside") and matches Subtitle Edit.
public func toggleInlineStyle(
    _ style: InlineStyle,
    in text: String,
    selection: Range<Int>,
    markup: InlineMarkup
) -> InlineEditResult {
    guard let (open, close) = markup.tokens(for: style) else {
        return InlineEditResult(text: text, selection: selection)
    }
    let chars = Array(text)
    let lower = min(max(selection.lowerBound, 0), chars.count)
    let upper = min(max(selection.upperBound, lower), chars.count)
    // Empty selection → the whole cue.
    let (start, end) = lower == upper ? (0, chars.count) : (lower, upper)

    let before = String(chars[0..<start])
    let inner = String(chars[start..<end])
    let after = String(chars[end...])
    let openLen = open.count
    let closeLen = close.count

    // Already wrapped inside the selection: "<i>text</i>" highlighted whole.
    if inner.hasPrefix(open), inner.hasSuffix(close), inner.count >= openLen + closeLen {
        let stripped = String(Array(inner)[openLen..<(inner.count - closeLen)])
        return InlineEditResult(text: before + stripped + after,
                                selection: start..<(start + stripped.count))
    }
    // Already wrapped around the selection: "<i>" and "</i>" sit just outside.
    if before.hasSuffix(open), after.hasPrefix(close) {
        let trimmedBefore = String(Array(before)[0..<(before.count - openLen)])
        let trimmedAfter = String(Array(after)[closeLen...])
        return InlineEditResult(text: trimmedBefore + inner + trimmedAfter,
                                selection: (start - openLen)..<(end - openLen))
    }
    return InlineEditResult(text: before + open + inner + close + after,
                            selection: (start + openLen)..<(end + openLen))
}
