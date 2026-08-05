// Cue list pane — hosts the real NSTableView grid (CueGridView, M3). Kept as a
// thin wrapper so PaneChrome's header/empty-state framing stays consistent with
// the other docked panes.

import SwiftUI
import GlyphlineCore

struct CuePane: View {
    let document: DocumentModel
    let media: MediaModel
    let settings: AppSettings
    var onEditTags: ((Cue) -> Void)?
    var onOpenSubtitle: () -> Void

    var body: some View {
        if document.doc.cues.isEmpty {
            PanePlaceholder(
                icon: "text.bubble", title: t("noCues"), subtitle: t("emptyHint"),
                actions: [
                    PlaceholderAction(label: t("menuOpenSubtitle"), prominent: true, action: onOpenSubtitle),
                    PlaceholderAction(label: t("addCue")) { document.addCue() },
                ]
            )
        } else {
            VStack(spacing: 0) {
                CueGridView(document: document, media: media, settings: settings, onEditTags: onEditTags)
                if settings.showCueEditor {
                    CueEditorBox(document: document, settings: settings)
                }
            }
        }
    }
}
