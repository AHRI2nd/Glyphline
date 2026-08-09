// User-defined find/replace rule sets — a house style TextTidy's fixed rules
// can't express (a translator's own "always write 'OK' not 'Okay'", a client's
// banned-word list, a project's specific romanization). TidyRule stays fixed
// and language-agnostic; this is the escape hatch for everything else,
// applied as an explicit, reviewable batch rather than edited by hand
// per-cue.

import Foundation

public struct CustomRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var pattern: String
    public var replacement: String
    public var caseInsensitive: Bool
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        pattern: String,
        replacement: String,
        caseInsensitive: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.caseInsensitive = caseInsensitive
        self.enabled = enabled
    }
}

/// Applies every enabled rule, in order, to `text`. An invalid pattern is
/// skipped rather than thrown — one bad regex in a saved set shouldn't block
/// every other rule in it, and there's no per-cue place to surface a compile
/// error anyway.
public func applyCustomRules(_ text: String, rules: [CustomRule]) -> String {
    var out = text
    for rule in rules where rule.enabled {
        guard !rule.pattern.isEmpty else { continue }
        let options: NSRegularExpression.Options = rule.caseInsensitive ? [.caseInsensitive] : []
        guard let re = RegexCache.get(rule.pattern, options: options) else { continue }
        let ns = out as NSString
        out = re.stringByReplacingMatches(
            in: out, range: NSRange(location: 0, length: ns.length), withTemplate: rule.replacement)
    }
    return out
}

/// Applies `rules` to every cue, returning only the cues that changed —
/// matches TextTidy's tidyCues shape so the panel/DocumentModel action can
/// reuse the same "only touch what actually changed" pattern.
public func applyCustomRules(toCues cues: [Cue], rules: [CustomRule]) -> [String: String] {
    guard rules.contains(where: \.enabled) else { return [:] }
    var out: [String: String] = [:]
    for cue in cues {
        let next = applyCustomRules(cue.text, rules: rules)
        if next != cue.text { out[cue.id] = next }
    }
    return out
}

/// True when `pattern` fails to compile — lets the UI flag a bad rule inline
/// instead of it silently doing nothing when applied.
public func isValidRulePattern(_ pattern: String) -> Bool {
    (try? NSRegularExpression(pattern: pattern)) != nil
}
