// Multiple open files as tabs, over a SINGLE long-lived DocumentModel.
//
// Deliberately NOT one DocumentModel instance per tab: every Coordinator in
// this codebase (CueGridCoordinator, WaveformScrollView's, MPVVideoView's)
// was built assuming ONE stable document identity for the app's lifetime,
// several capturing it in `[weak document]` closures set up once in
// AppState.startUp(). Giving every tab its own instance would mean rewiring
// all of that to react to identity changes — real work, and real risk to the
// single-document experience this whole session has been built and tested
// against. Instead, a tab is a SNAPSHOT (the SubtitleDocument + path/dirty
// state); switching tabs loads a snapshot into the one shared DocumentModel
// via the existing `loadParsed`, so every Coordinator keeps working exactly
// as before — only its content changes under it, same as opening a file
// already did.
//
// Trade-off, stated plainly: undo/redo history is NOT preserved across a tab
// switch (`loadParsed` clears it, same as opening any file today). Given the
// alternative was rewiring every media/grid Coordinator's identity handling,
// this is the deliberate scope line for a first cut, not an oversight.

import AppKit
import GlyphlineCore

struct DocumentTab: Identifiable, Equatable {
    let id = UUID()
    var path: String?
    var fileName: String?
    var snapshot: SubtitleDocument
    var isDirty: Bool
    /// The video/audio paired with this subtitle project, if any — each tab
    /// is a separate project, and a project's video is part of what "this
    /// tab" means. Without tracking this, switching tabs would swap the
    /// subtitles while silently leaving whatever video the PREVIOUS tab had
    /// open, timing the new tab's cues against the wrong picture.
    var mediaPath: String?

    static func == (a: DocumentTab, b: DocumentTab) -> Bool { a.id == b.id }
}

extension AppState {
    /// Freezes the currently active document's live state into its tab slot
    /// — called right before switching away, so the tab can be restored
    /// later exactly as it was left.
    func snapshotActiveTab() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        tabs[idx].snapshot = document.doc
        tabs[idx].path = document.filePath
        tabs[idx].fileName = document.fileName
        tabs[idx].isDirty = document.isDirty
        tabs[idx].mediaPath = media.mediaPath
    }

    func switchToTab(_ id: UUID) {
        guard id != activeTabId, let target = tabs.first(where: { $0.id == id }) else { return }
        snapshotActiveTab()
        activeTabId = id
        document.loadParsed(target.snapshot, filePath: target.path, fileName: target.fileName)
        document.restoreDirtyFlag(target.isDirty)
        media.clearLoop() // a loop bound to the previous tab's cue id means nothing here
        // Swap the video to match — or close it, if this tab never had one —
        // rather than leaving the outgoing tab's video attached to the new
        // subtitles. A no-op when both tabs share (or both lack) a video, so
        // this doesn't re-decode/reload anything on every switch.
        if target.mediaPath != media.mediaPath {
            if let path = target.mediaPath {
                media.loadMedia(path)
            } else {
                media.closeMedia()
            }
        }
    }

    /// A blank, untouched tab — what "New" and the very first launch use.
    @discardableResult
    func openNewTab() -> UUID {
        snapshotActiveTab()
        let tab = DocumentTab(path: nil, fileName: nil, snapshot: .empty(.srt), isDirty: false, mediaPath: nil)
        tabs.append(tab)
        activeTabId = tab.id
        document.loadParsed(tab.snapshot, filePath: nil, fileName: nil)
        // A genuinely new tab starts with no video either — otherwise it'd
        // silently inherit whatever the tab it was opened from had loaded.
        media.closeMedia()
        return tab.id
    }

    /// File ▸ New: reuses a blank tab, otherwise opens a fresh one — same
    /// reuse-vs-new heuristic as opening a file.
    func newDocumentTab() {
        if activeTabIsBlank {
            document.newDocument()
        } else {
            openNewTab()
        }
    }

    /// True when the active tab has never been given content worth
    /// preserving — File ▸ Open reuses a tab in this state instead of always
    /// accumulating a new one, matching how most editors treat an empty tab.
    var activeTabIsBlank: Bool {
        document.filePath == nil && !document.isDirty && document.doc.cues.isEmpty
    }

    /// Closes a tab. Refuses to close the last one (there's always exactly
    /// one document open). If it's dirty, defers to CloseConfirmPanel — the
    /// same sheet the quit flow uses, with a real Save option, instead of a
    /// bare discard-or-cancel alert.
    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let isDirty = id == activeTabId ? document.isDirty : tabs[idx].isDirty
        if isDirty {
            activePanel = .closeConfirm(tabToClose: id)
            return
        }
        forceCloseTab(id)
    }

    /// The actual removal, with no dirty check — called directly for a
    /// clean tab, or once CloseConfirmPanel has resolved a dirty one.
    func forceCloseTab(_ id: UUID) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if id == activeTabId {
            let neighborIndex = idx > 0 ? idx - 1 : idx + 1
            switchToTab(tabs[neighborIndex].id)
        }
        tabs.removeAll { $0.id == id }
    }

    /// Every tab that currently holds unsaved changes — the active one read
    /// live from `document`, inactive ones from their frozen snapshot flag.
    /// Used to widen the quit-time guard beyond just the active document.
    var anyTabDirty: Bool {
        tabs.contains { $0.id == activeTabId ? document.isDirty : $0.isDirty }
    }

    /// Saves every dirty tab in place, switching through them one at a time
    /// (only the active DocumentModel can actually be written) and returning
    /// to whichever tab was active when this was called. Returns false if
    /// any tab's save was cancelled (e.g. a Save As dialog dismissed without
    /// choosing a location) — callers driving a quit/close flow should not
    /// proceed past that, the same contract as `saveDocument()` for a single
    /// tab.
    @discardableResult
    func saveAllTabs() -> Bool {
        let originalTab = activeTabId
        var allSucceeded = true
        for tab in tabs {
            let isDirty = tab.id == activeTabId ? document.isDirty : tab.isDirty
            guard isDirty else { continue }
            if tab.id != activeTabId { switchToTab(tab.id) }
            if !saveDocument() { allSucceeded = false }
        }
        if activeTabId != originalTab { switchToTab(originalTab) }
        return allSucceeded
    }
}
