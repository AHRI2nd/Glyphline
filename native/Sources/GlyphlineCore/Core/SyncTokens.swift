// Word/syllable-level timing (SyncToken) editing helpers.
//
// The model and the ASS/VTT adapters already carry tokens losslessly; what was
// missing was any way to CREATE or ADJUST them. These are the pure operations
// behind that editor.
//
// Invariants every operation here maintains, because a token list that breaks
// them serialises to karaoke tags that render wrong rather than failing loudly:
//   • tokens are contiguous — each one starts exactly where the last ended,
//     which is what ASS \k durations encode (they have no gaps to express);
//   • they span the cue exactly, from cue.start to cue.end;
//   • concatenating their text reproduces the cue's text.

import Foundation

/// Splits `text` into the units a karaoke line is timed in.
///
/// Latin scripts split on whitespace (one token per word). CJK has no spaces
/// and is sung per character, so it splits per character — matching how
/// karaoke is actually timed in Japanese, not how a word tokenizer would.
/// Whitespace is attached to the preceding token so the concatenation
/// invariant holds.
public func syllableSplit(_ text: String) -> [String] {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
    guard !flat.isEmpty else { return [] }

    var units: [String] = []
    var current = ""
    for ch in flat {
        if ch.isWhitespace {
            current.append(ch)
            if !current.trimmed().isEmpty { units.append(current); current = "" }
            continue
        }
        if isCJKChar(ch) {
            if !current.isEmpty { units.append(current); current = "" }
            units.append(String(ch))
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { units.append(current) }
    return units.filter { !$0.isEmpty }
}

private func isCJKChar(_ ch: Character) -> Bool {
    guard let scalar = ch.unicodeScalars.first else { return false }
    return (0x3040...0x30FF).contains(scalar.value)
        || (0x4E00...0x9FFF).contains(scalar.value)
        || (0x3400...0x4DBF).contains(scalar.value)
        || (0xAC00...0xD7AF).contains(scalar.value) // hangul syllables
}

/// Builds evenly spaced tokens spanning the cue — the starting point a user
/// then drags into place, which is far quicker than typing every boundary.
public func makeEvenTokens(for cue: Cue) -> [SyncToken] {
    let units = syllableSplit(cue.text)
    guard !units.isEmpty, cue.end > cue.start else { return [] }
    let step = (cue.end - cue.start) / Double(units.count)
    return units.enumerated().map { i, unit in
        SyncToken(text: unit,
                  start: cue.start + step * Double(i),
                  end: cue.start + step * Double(i + 1))
    }
}

/// Moves the boundary between token `index` and `index + 1` to `time`,
/// clamped so neither neighbour collapses below `minDuration`.
///
/// Editing a boundary rather than a token's start/end independently is what
/// keeps the list contiguous — there is no way to express a gap in \k anyway,
/// so offering one would just produce output that silently differs.
public func moveTokenBoundary(
    _ tokens: [SyncToken],
    index: Int,
    to time: Double,
    minDuration: Double = 0.02
) -> [SyncToken] {
    guard tokens.indices.contains(index), tokens.indices.contains(index + 1) else { return tokens }
    var out = tokens
    let lower = out[index].start + minDuration
    let upper = out[index + 1].end - minDuration
    guard lower <= upper else { return tokens }
    let clamped = min(max(time, lower), upper)
    out[index].end = clamped
    out[index + 1].start = clamped
    return out
}

/// Re-anchors tokens onto a cue's current span, keeping their relative
/// proportions. Used after the cue itself is retimed so the karaoke follows.
public func rescaleTokens(_ tokens: [SyncToken], to cue: Cue) -> [SyncToken] {
    guard let first = tokens.first, let last = tokens.last else { return tokens }
    let oldSpan = last.end - first.start
    let newSpan = cue.end - cue.start
    guard oldSpan > 0, newSpan > 0 else { return tokens }
    let scale = newSpan / oldSpan
    return tokens.map { token in
        var t = token
        t.start = cue.start + (token.start - first.start) * scale
        t.end = cue.start + (token.end - first.start) * scale
        return t
    }
}

/// True when `tokens` are contiguous and exactly span `cue`.
public func tokensAreValid(_ tokens: [SyncToken], for cue: Cue, tolerance: Double = 0.001) -> Bool {
    guard let first = tokens.first, let last = tokens.last else { return false }
    guard abs(first.start - cue.start) <= tolerance, abs(last.end - cue.end) <= tolerance else { return false }
    for (a, b) in zip(tokens, tokens.dropFirst()) where abs(a.end - b.start) > tolerance { return false }
    return tokens.allSatisfy { $0.end >= $0.start }
}
