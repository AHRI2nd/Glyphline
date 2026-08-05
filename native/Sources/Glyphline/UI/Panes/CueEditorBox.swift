// The multi-line editor for the active cue, sitting under the grid.
//
// WHY this exists: the grid edits in single-line NSTextFields with truncating
// display, so a two-line subtitle showed as "first line second li…" and there
// was no way to type a line break at all. Deciding where a subtitle breaks is
// half of subtitle work, and it can't be done in a control that won't show or
// accept the break. Both Subtitle Edit and Aegisub pair their grid with a
// dedicated edit box for exactly this reason.
//
// Per-line character counts sit under the box and turn amber past the quality
// threshold — the same number the quality check flags on, so the warning and
// the fix are in one place instead of one telling you and the other hiding it.

import SwiftUI
import GlyphlineCore

struct CueEditorBox: View {
    let document: DocumentModel
    let settings: AppSettings

    /// Local draft. The document is the source of truth, but binding a
    /// TextEditor straight to it would fight the user: every keystroke mutates
    /// the doc, which re-renders this view, which can reset the caret mid-word.
    /// So the draft is authoritative WHILE editing and re-synced only when the
    /// active cue changes.
    @State private var text = ""
    @State private var translation = ""
    @State private var editingCueId: String?
    @FocusState private var focus: Field?

    private enum Field { case text, translation }

    private var cue: Cue? {
        guard let id = document.activeCueId else { return nil }
        return document.doc.cues.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cue {
                editor(for: cue)
            } else {
                Text(t("noActiveCueShort"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .top)
        .onChange(of: document.activeCueId) { _, _ in syncFromDocument() }
        .onAppear { syncFromDocument() }
    }

    @ViewBuilder
    private func editor(for cue: Cue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextEditor(text: $text)
                    .font(GlyphFont.body(13))
                    .scrollContentBackground(.hidden)
                    .background(GlyphColor.bg)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(GlyphColor.borderStrong, lineWidth: 0.5))
                    .frame(height: 56)
                    .focused($focus, equals: .text)
                    .onChange(of: text) { _, next in commit(cue.id) { $0.text = next } }
                lineCounts(text)
            }

            if settings.showTranslation {
                VStack(alignment: .leading, spacing: 3) {
                    TextEditor(text: $translation)
                        .font(GlyphFont.body(13))
                        .scrollContentBackground(.hidden)
                        .background(GlyphColor.bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(GlyphColor.borderStrong, lineWidth: 0.5))
                        .frame(height: 56)
                        .focused($focus, equals: .translation)
                        .onChange(of: translation) { _, next in
                            commit(cue.id) { $0.translation = next.isEmpty ? nil : next }
                        }
                    lineCounts(translation)
                }
            }

            VStack(spacing: 4) {
                Button(t("autoBreakLines")) {
                    let next = breakLines(text,
                                          maxLineLength: settings.quality.maxLineLength,
                                          maxLines: settings.quality.maxLines)
                    text = next
                }
                .controlSize(.small)
                Button(t("unbreakLines")) { text = unbreakLines(text) }
                    .controlSize(.small)
            }
            .frame(width: 92)
        }
    }

    /// One count per line, amber past the threshold, plus the CPS the quality
    /// check actually measures.
    @ViewBuilder
    private func lineCounts(_ value: String) -> some View {
        let limit = settings.quality.maxLineLength
        let lines = value.components(separatedBy: "\n")
        HStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\(line.count)")
                    .font(GlyphFont.data(10))
                    .foregroundStyle(line.count > limit ? GlyphColor.amber : GlyphColor.quiet)
            }
            if lines.count > settings.quality.maxLines {
                Text(t("tooManyLines")).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.amber)
            }
            Spacer()
            if let cue, cueDuration(cue) > 0 {
                let rate = cps(cue)
                Text(String(format: "%.0f cps", rate))
                    .font(GlyphFont.data(10))
                    .foregroundStyle(rate > settings.quality.maxCps ? GlyphColor.amber : GlyphColor.quiet)
            }
        }
    }

    // ── document sync ────────────────────────────────────────────────────────

    private func syncFromDocument() {
        // Close out whatever gesture the previous cue's edits belonged to before
        // adopting a new one, so its undo entry doesn't absorb the next cue too.
        if editingCueId != nil { document.endInteractive(); editingCueId = nil }
        text = cue?.text ?? ""
        translation = cue?.translation ?? ""
    }

    /// Typing is one continuous gesture per cue: the first keystroke opens an
    /// interactive bracket so a sentence lands as ONE undo step rather than one
    /// per character. It closes when the active cue changes (above).
    private func commit(_ id: String, _ edit: @escaping CueEdit) {
        if editingCueId != id {
            if editingCueId != nil { document.endInteractive() }
            document.beginInteractive()
            editingCueId = id
        }
        document.updateCue(id, edit)
    }
}
