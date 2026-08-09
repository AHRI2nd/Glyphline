// House-style term glossary, independent of any one open document — see
// AppSettings.sharedGlossary for why this exists alongside the per-project
// glossary TranslationCheckPanel already edits: a series' character and
// place names don't change episode to episode, but the per-document
// glossary does (it lives in `.glyph`), so entering them again for every
// new file was the gap this closes. TranslationCheckPanel merges this list
// into its check automatically; this window is just the standing editor.

import SwiftUI
import GlyphlineCore

let SHARED_GLOSSARY_WINDOW_ID = "sharedGlossary"

struct SharedGlossaryWindow: View {
    let settings: AppSettings
    @State private var newSource = ""
    @State private var newTarget = ""
    @State private var newNote = ""

    var body: some View {
        VStack(spacing: 0) {
            if settings.sharedGlossary.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "character.book.closed").font(.system(size: 22)).foregroundStyle(GlyphColor.quiet)
                    Text(t("sharedGlossaryEmpty")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(settings.sharedGlossary) { entry in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.source).font(GlyphFont.body(12)).lineLimit(1)
                                Text("→").font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                                Text(entry.target).font(GlyphFont.body(12)).lineLimit(1)
                            }
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(t("tcRemoveTerm")) { settings.removeSharedGlossaryEntry(source: entry.source) }
                            .controlSize(.small)
                    }
                    .listRowBackground(GlyphColor.bg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider().overlay(GlyphColor.border)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField(t("tcSourceTerm"), text: $newSource)
                        .textFieldStyle(.roundedBorder).font(GlyphFont.body(12))
                    TextField(t("tcTargetTerm"), text: $newTarget)
                        .textFieldStyle(.roundedBorder).font(GlyphFont.body(12))
                }
                HStack(spacing: 8) {
                    TextField(t("sharedGlossaryNote"), text: $newNote)
                        .textFieldStyle(.roundedBorder).font(GlyphFont.body(12))
                    Button(t("tcAddTerm")) { addTerm() }
                        .controlSize(.small)
                        .disabled(newSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || newTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(GlyphColor.surface)
        }
        .frame(minWidth: 420, minHeight: 300)
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
    }

    private func addTerm() {
        settings.upsertSharedGlossaryEntry(source: newSource, target: newTarget, note: newNote)
        newSource = ""; newTarget = ""; newNote = ""
    }
}
