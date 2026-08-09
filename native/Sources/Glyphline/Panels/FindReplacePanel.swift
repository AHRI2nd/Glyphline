// Find & Replace over cue text and translation (ported from
// ../../../src/components/Modals/FindReplaceModal.tsx). Matches are listed per
// cue+field; navigation moves the active cue. "Replace all" is a single undo step.

import SwiftUI
import GlyphlineCore

private enum MatchField { case text, translation }
private struct Match { let cueId: String; let field: MatchField }

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

    private func matches(_ re: NSRegularExpression) -> [Match] {
        var out: [Match] = []
        for cue in sortedCues(document.doc.cues) {
            if re.firstMatch(in: cue.text, range: NSRange(cue.text.startIndex..., in: cue.text)) != nil {
                out.append(Match(cueId: cue.id, field: .text))
            }
            if let t = cue.translation, re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                out.append(Match(cueId: cue.id, field: .translation))
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
            guard let t = cue.translation else { return nil }
            let ns = t as NSString
            let next = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: replacementTemplate)
            guard next != t else { return nil }
            return { $0.translation = next.isEmpty ? nil : next }
        }
    }

    private func replaceCurrent(_ list: [Match]) {
        guard let re = regex, !list.isEmpty else { return }
        let m = list[min(cursor, list.count - 1)]
        guard let cue = document.doc.cues.first(where: { $0.id == m.cueId }),
              let edit = replaceIn(cue, m.field, re) else { return }
        document.updateCue(cue.id, edit)
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
