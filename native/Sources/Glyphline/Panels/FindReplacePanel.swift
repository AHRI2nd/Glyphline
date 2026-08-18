// Find & Replace over cue text and translation (ported from
// ../../../src/components/Modals/FindReplaceModal.tsx). Matches are listed per
// cue+field; navigation moves the active cue. "Replace all" is a single undo step.

import SwiftUI
import GlyphlineCore

private enum MatchField { case text, translation }
/// `range` is the specific occurrence within that cue+field — without it,
/// "Replace" (as opposed to "Replace All") had no way to know WHICH
/// occurrence to touch when a field contained the query more than once, and
/// silently replaced all of them, indistinguishable from "Replace All".
private struct Match { let cueId: String; let field: MatchField; let range: NSRange }

struct FindReplacePanel: View {
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var useRegex = false
    @State private var cursor = 0

    private var regex: NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        let pattern = useRegex ? query : NSRegularExpression.escapedPattern(for: query)
        return try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
    }
    private var invalidRegex: Bool { !query.isEmpty && regex == nil }

    /// Which translation "slot" is currently active — everything here reads/
    /// writes through it instead of `cue.translation` directly, so find &
    /// replace works on whichever language the grid/editor box is showing.
    private var translationIndex: Int { document.activeTranslationLanguageIndex }
    private var translationLanguages: [String] { document.doc.translationLanguages ?? [] }

    /// Every occurrence, not just one per cue+field — the counter and ←/→
    /// navigation step through individual matches, so they need to actually
    /// exist as individual entries.
    private func matches(_ re: NSRegularExpression) -> [Match] {
        var out: [Match] = []
        for cue in sortedCues(document.doc.cues) {
            let textNs = cue.text as NSString
            for m in re.matches(in: cue.text, range: NSRange(location: 0, length: textNs.length)) {
                out.append(Match(cueId: cue.id, field: .text, range: m.range))
            }
            if let t = cue.translationText(at: translationIndex, languages: translationLanguages) {
                let tNs = t as NSString
                for m in re.matches(in: t, range: NSRange(location: 0, length: tNs.length)) {
                    out.append(Match(cueId: cue.id, field: .translation, range: m.range))
                }
            }
        }
        return out
    }

    var body: some View {
        PanelShell(title: t("findReplace"), width: 460) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(t("findPlaceholder"), text: $query)
                        .font(GlyphFont.body(12)).textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _, _ in cursor = 0 }
                    counterLabel
                }
                TextField(t("replacePlaceholder"), text: $replacement)
                    .font(GlyphFont.body(12)).textFieldStyle(.roundedBorder)

                HStack(spacing: 16) {
                    Toggle(t("matchCase"), isOn: $matchCase).toggleStyle(.checkbox)
                    Toggle(t("useRegex"), isOn: $useRegex).toggleStyle(.checkbox)
                }
                .font(GlyphFont.body(11))

                if invalidRegex {
                    Text(t("invalidRegex")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.warn)
                }
            }
        } footer: {
            let list = regex.map(matches) ?? []
            Button("← \(t("findPrev"))") { step(list, -1) }.disabled(list.isEmpty)
            Button("\(t("findNext")) →") { step(list, 1) }.disabled(list.isEmpty)
            Divider().frame(height: 16)
            Button(t("replaceOne")) { replaceCurrent(list) }.disabled(list.isEmpty)
            Button(t("replaceAll")) { replaceAll() }
                .disabled(list.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
            Spacer()
            PanelCloseButton()
        }
        .onChange(of: cursorTarget) { _, target in
            if let target { document.setActiveCue(target) }
        }
    }

    private var cursorTarget: String? {
        guard let re = regex else { return nil }
        let list = matches(re)
        guard !list.isEmpty else { return nil }
        return list[min(cursor, list.count - 1)].cueId
    }

    private var counterLabel: some View {
        Group {
            if invalidRegex {
                EmptyView()
            } else if query.isEmpty {
                EmptyView()
            } else if let re = regex {
                let list = matches(re)
                Text(list.isEmpty ? t("noMatches") : "\(min(cursor, list.count - 1) + 1) / \(list.count)")
                    .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
            }
        }
    }

    private func step(_ list: [Match], _ dir: Int) {
        guard !list.isEmpty else { return }
        cursor = ((min(cursor, list.count - 1) + dir) % list.count + list.count) % list.count
    }

    /// In regex mode, `$1`/`$&` etc. work as capture-group backreferences
    /// (matches JS `String.replace(regex, …)` semantics the original used); in
    /// plain-text mode the replacement is escaped so a literal "$" can't be
    /// misread as one.
    private var replacementTemplate: String {
        useRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
    }

    private func replaceIn(_ cue: Cue, _ field: MatchField, _ re: NSRegularExpression) -> CueEdit? {
        switch field {
        case .text:
            let ns = cue.text as NSString
            let next = re.stringByReplacingMatches(in: cue.text, range: NSRange(location: 0, length: ns.length), withTemplate: replacementTemplate)
            guard next != cue.text else { return nil }
            return { $0.text = next }
        case .translation:
            guard let t = cue.translationText(at: translationIndex, languages: translationLanguages) else { return nil }
            let ns = t as NSString
            let next = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: replacementTemplate)
            guard next != t else { return nil }
            let idx = translationIndex; let langs = translationLanguages
            return { $0.setTranslationText(next, at: idx, languages: langs) }
        }
    }

    /// Replaces ONLY the currently-selected occurrence — as opposed to
    /// replaceIn(_:_:_:) below, which replaceAll() uses and which touches
    /// every occurrence in the field at once.
    private func replaceCurrent(_ list: [Match]) {
        guard let re = regex, !list.isEmpty else { return }
        let m = list[min(cursor, list.count - 1)]
        guard let cue = document.doc.cues.first(where: { $0.id == m.cueId }) else { return }
        let source: String
        switch m.field {
        case .text: source = cue.text
        case .translation: source = cue.translationText(at: translationIndex, languages: translationLanguages) ?? ""
        }
        // Re-matching restricted to the stored range recovers the
        // NSTextCheckingResult needed for replacementString(for:) to expand
        // $1-style backreferences correctly in regex mode.
        guard let match = re.firstMatch(in: source, range: m.range) else { return }
        let replacementText = re.replacementString(for: match, in: source, offset: 0, template: replacementTemplate)
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: m.range, with: replacementText)
        let next = mutable as String
        switch m.field {
        case .text:
            document.updateCue(cue.id) { $0.text = next }
        case .translation:
            let idx = translationIndex; let langs = translationLanguages
            document.updateCue(cue.id) { $0.setTranslationText(next, at: idx, languages: langs) }
        }
    }

    private func replaceAll() {
        guard let re = regex else { return }
        var edits: [(id: String, edit: CueEdit)] = []
        for cue in document.doc.cues {
            var combined: CueEdit?
            if let e = replaceIn(cue, .text, re) {
                combined = { c in e(&c) }
            }
            if let e = replaceIn(cue, .translation, re) {
                let prev = combined
                combined = { c in prev?(&c); e(&c) }
            }
            if let combined { edits.append((cue.id, combined)) }
        }
        document.batchUpdateCues(edits)
    }
}
