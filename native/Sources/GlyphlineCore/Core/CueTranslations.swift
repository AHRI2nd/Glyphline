// Uniform read/write across a cue's translation "slots" — index 0 is always
// the plain `translation` field (today's single-language behavior, and every
// existing call site that never touches multi-language tracks), index 1+
// comes from `translations[languages[index]]`. Every UI surface that used to
// read `cue.translation` directly (grid, editor box, find/replace, spell
// check, term consistency) should go through these instead, so adding a
// second language is purely additive — nothing about index-0 behavior
// changes when `languages` is empty/single-element.

public extension Cue {
    /// `languages` is `doc.translationLanguages ?? []`. Returns nil if
    /// `index` is out of range for `languages` (except index 0, which is
    /// always valid since it doesn't depend on `languages` at all).
    func translationText(at index: Int, languages: [String]) -> String? {
        guard index >= 0 else { return nil }
        if index == 0 { return translation }
        guard languages.indices.contains(index) else { return nil }
        return translations?[languages[index]]
    }

    /// Empty string normalizes to nil, matching how every existing
    /// translation-editing call site already treats "cleared the field".
    mutating func setTranslationText(_ text: String?, at index: Int, languages: [String]) {
        let normalized = (text?.isEmpty ?? true) ? nil : text
        guard index >= 0 else { return }
        if index == 0 { translation = normalized; return }
        guard languages.indices.contains(index) else { return }
        let code = languages[index]
        if normalized == nil {
            translations?[code] = nil
        } else {
            if translations == nil { translations = [:] }
            translations?[code] = normalized
        }
    }
}
