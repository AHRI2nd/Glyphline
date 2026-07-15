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

    var body: some View {
        if document.doc.cues.isEmpty {
            PanePlaceholder(message: "\(t("noCues")) — \(t("emptyHint"))")
        } else {
            CueGridView(document: document, media: media, settings: settings, onEditTags: onEditTags)
        }
    }
}
