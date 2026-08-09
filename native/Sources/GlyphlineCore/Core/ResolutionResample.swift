// Rescale a script from one PlayRes to another (e.g. a 1080p timing pass
// being retargeted at a 4K deliverable) — every style's font size, outline,
// shadow and margins, plus the positional inline overrides (\pos/\move/\org)
// and the size-in-pixels overrides (\fs/\bord/\shad/\blur/\xbord/…), scaled
// to match.
//
// SCOPE: `\p` vector drawing coordinates and `\clip`/`\iclip` vector paths
// are NOT rescaled — parsing an arbitrary drawing command stream correctly
// (curves, multiple subpaths, relative-move edge cases) is a materially
// bigger job than the linear-tag substitution here, and a script that leans
// on hand-drawn shapes is already an unusual, advanced-authoring case rather
// than the common "just resize the subtitle track" need this serves. Same
// class of documented boundary as this codebase's other 90%-scope choices.

import Foundation

/// scaleX/scaleY are computed once by the caller (toWidth/fromWidth etc.) so
/// non-uniform resampling (different aspect target) is possible, though the
/// common case is uniform.
public struct ResampleScale: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(from: (w: Double, h: Double), to: (w: Double, h: Double)) {
        x = from.w > 0 ? to.w / from.w : 1
        y = from.h > 0 ? to.h / from.h : 1
    }
}

public func resampleStyle(_ style: AssStyle, scale: ResampleScale) -> AssStyle {
    var s = style
    // Font metrics and border/shadow radii read as primarily-vertical
    // quantities by convention (this is what Aegisub's own "resolution
    // resampler" does) — using scale.y keeps text proportions sane even
    // under a non-uniform (aspect-changing) resample.
    s.fontSize = style.fontSize * scale.y
    s.outline = style.outline * scale.y
    s.shadow = style.shadow * scale.y
    s.marginL = Int((Double(style.marginL) * scale.x).rounded())
    s.marginR = Int((Double(style.marginR) * scale.x).rounded())
    s.marginV = Int((Double(style.marginV) * scale.y).rounded())
    return s
}

private func scaleNumber(_ s: Substring, by factor: Double) -> String {
    guard let v = Double(s) else { return String(s) }
    let scaled = v * factor
    // Integral inputs stay integral in the output — ASS tags are commonly
    // hand-authored, and "300" scaling to "300.0" for a 1.0 factor reads as
    // the tool having rewritten something it didn't need to touch. Fractional
    // results drop trailing zeros for the same reason ("1.500" vs "1.5").
    if scaled.rounded() == scaled { return String(Int(scaled)) }
    var formatted = String(format: "%.3f", scaled)
    while formatted.hasSuffix("0") { formatted.removeLast() }
    if formatted.hasSuffix(".") { formatted.removeLast() }
    return formatted
}

private let numPattern = #"-?[0-9]*\.?[0-9]+"#

/// Rewrites every position/size override tag in a `{...}` block's INSIDE
/// text (no braces) to the target scale. Unknown/unhandled tags pass through
/// untouched — this only touches the tags it explicitly knows how to scale.
public func scaleAssTagBlock(_ block: String, scale: ResampleScale) -> String {
    var out = block

    // \pos(x,y) and \org(x,y) — both coordinates scaled independently.
    for name in ["pos", "org"] {
        let pattern = #"\\"# + name + #"\((\#(numPattern)),(\#(numPattern))\)"#
        out = replaceRegex(pattern, in: out) { m in
            "\\\(name)(\(scaleNumber(m[1], by: scale.x)),\(scaleNumber(m[2], by: scale.y)))"
        }
    }
    // \move(x1,y1,x2,y2[,t1,t2]) — only the 4 coordinates scale; optional
    // timing args (t1,t2), if present, are left exactly as captured.
    out = replaceRegex(
        #"\\move\((\#(numPattern)),(\#(numPattern)),(\#(numPattern)),(\#(numPattern))((?:,\#(numPattern)){0,2})\)"#,
        in: out
    ) { m in
        "\\move(\(scaleNumber(m[1], by: scale.x)),\(scaleNumber(m[2], by: scale.y)),"
            + "\(scaleNumber(m[3], by: scale.x)),\(scaleNumber(m[4], by: scale.y))\(m[5]))"
    }
    // Vertical-scaled size tags: font size, border, shadow, blur.
    for name in ["fs", "bord", "shad", "blur", "be"] {
        out = replaceRegex(#"\\"# + name + #"(\#(numPattern))"#, in: out) { m in
            "\\\(name)\(scaleNumber(m[1], by: scale.y))"
        }
    }
    // Axis-specific border/shadow.
    for name in ["xbord", "xshad"] {
        out = replaceRegex(#"\\"# + name + #"(\#(numPattern))"#, in: out) { m in
            "\\\(name)\(scaleNumber(m[1], by: scale.x))"
        }
    }
    for name in ["ybord", "yshad"] {
        out = replaceRegex(#"\\"# + name + #"(\#(numPattern))"#, in: out) { m in
            "\\\(name)\(scaleNumber(m[1], by: scale.y))"
        }
    }
    return out
}

/// Scales every style, every cue's inline override tags, and the document's
/// declared PlayResX/Y — the whole "retarget this script at a new
/// resolution" operation in one pass. Returns the scaled document; the
/// caller (DocumentModel) owns undo/pushHistory around this.
public func resampleDocument(_ doc: SubtitleDocument, toWidth: Double, toHeight: Double) -> SubtitleDocument {
    let (fromW, fromH) = scriptResolution(of: doc)
    let scale = ResampleScale(from: (fromW, fromH), to: (toWidth, toHeight))
    guard scale.x != 1 || scale.y != 1 else { return doc }

    var out = doc
    out.styles = doc.styles?.map { resampleStyle($0, scale: scale) }
    out.cues = doc.cues.map { cue in
        var c = cue
        guard let spans = cue.assSpans, !spans.isEmpty else { return c }
        c.assSpans = spans.map { span in
            guard let tags = span.tags else { return span }
            return AssSpan(tags: scaleAssTagBlock(tags, scale: scale), text: span.text)
        }
        return c
    }
    out.meta["assScriptInfo"] = replacingPlayRes(
        doc.meta["assScriptInfo"], width: Int(toWidth.rounded()), height: Int(toHeight.rounded()))
    return out
}

/// Rewrites (or appends, if absent) PlayResX/PlayResY lines in a preserved
/// `[Script Info]` block.
private func replacingPlayRes(_ info: String?, width: Int, height: Int) -> String {
    var lines = (info ?? "ScriptType: v4.00+").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var sawX = false, sawY = false
    for i in 0..<lines.count {
        if lines[i].lowercased().hasPrefix("playresx:") { lines[i] = "PlayResX: \(width)"; sawX = true }
        if lines[i].lowercased().hasPrefix("playresy:") { lines[i] = "PlayResY: \(height)"; sawY = true }
    }
    if !sawX { lines.append("PlayResX: \(width)") }
    if !sawY { lines.append("PlayResY: \(height)") }
    return lines.joined(separator: "\n")
}

// MARK: - regex helper

/// Replaces every match of `pattern` in `input`, handing the callback the
/// captured groups (index 0 = whole match) as Substrings of `input`.
private func replaceRegex(_ pattern: String, in input: String, _ transform: ([Substring]) -> String) -> String {
    guard let re = RegexCache.get(pattern) else { return input }
    let ns = input as NSString
    var result = ""
    var last = 0
    re.enumerateMatches(in: input, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m else { return }
        result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        var groups: [Substring] = []
        for g in 0..<m.numberOfRanges {
            let r = m.range(at: g)
            groups.append(r.location == NSNotFound ? "" : Substring(ns.substring(with: r)))
        }
        result += transform(groups)
        last = m.range.location + m.range.length
    }
    result += ns.substring(from: last)
    return result
}
