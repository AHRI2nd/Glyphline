// App-wide state root. Holds the single DocumentModel (from GlyphlineCore) that
// every pane reads/edits, plus file I/O, autosave/recovery, and export-warning
// orchestration (ported from ../../../src/App.tsx).

import Observation
import AppKit
import UniformTypeIdentifiers
import GlyphlineCore

/// Which M5 panel sheet is currently presented (mutually exclusive — matches the
/// Tauri app's one-modal-at-a-time UX). `nil` = none.
enum ActivePanel: Identifiable {
    case batchCleanup, pointSync, changeSpeed, shiftTime
    case styleManager, embeddedAssets, settings, rawEditor, help, closeConfirm
    case compareFiles, exportRange, autoSpot, batchConvert, customRules, resampleResolution, burnIn, deliveryPipeline

    var id: Self { self }
}

/// A lossy export (currently only ASS→SMI) pending the user's loss-warning
/// confirmation (ported from ExportWarningModal.tsx).
struct PendingExport: Identifiable {
    let id = UUID()
    let format: SubFormat
    let source: DocumentModel.ExportSource
    let encodingLabel: String?
    let categories: [LossCategory]
}

@MainActor
@Observable
final class AppState {
    let document: DocumentModel
    let media: MediaModel
    let settings: AppSettings
    var activePanel: ActivePanel?
    var pendingExport: PendingExport?
    var recovery: AutosaveData?
    /// Snapshots older than `recovery`, offered as alternatives in the sheet.
    var olderRecoveries: [AutosaveData] = []
    var lastError: String?

    /// Open files as tabs over the one shared `document` — see
    /// DocumentTabs.swift for why this isn't one DocumentModel per tab.
    /// Always has at least one entry; the active one mirrors `document` live.
    var tabs: [DocumentTab]
    var activeTabId: UUID

    /// True while the video lives in its own OS window instead of the dock —
    /// for a second-monitor layout (video on one screen, grid/waveform on the
    /// other), which the single-window dock can't offer on its own. Session-
    /// only (not persisted): restoring it blind on next launch, before the
    /// window has actually been (re)opened, would leave the dock's video slot
    /// permanently showing the "detached" placeholder with no way back.
    var videoDetached = false

    /// Long-running background operations (burn-in encode, batch convert, …)
    /// that outlive the panel that started them — see BackgroundJobs.swift.
    /// Newest first; kept after completion until cleared so a job started
    /// from a panel the user already closed still has somewhere to report.
    var backgroundJobs: [BackgroundJob] = []

    /// Shared with every window (including any torn-off panel's own window)
    /// so a cross-window drag can drive the same zone-preview overlay an
    /// in-dock drag uses — see DockTearOff.swift.
    let dockDragState = DockDragState()
    /// Captured once each relevant view appears — lets a torn-off panel's
    /// window hit-test its drag against the main dock without SwiftUI
    /// coordinate spaces, which don't span separate windows. Weak: SwiftUI
    /// owns these views' lifetime, not us.
    weak var mainWindow: NSWindow?
    weak var dockRootView: NSView?

    private var autosave: AutosaveService!

    init() {
        self.document = DocumentModel()
        self.media = MediaModel()
        self.settings = AppSettings()
        self.autosave = AutosaveService(document: document)
        let firstTab = DocumentTab(path: nil, fileName: nil, snapshot: .empty(.srt), isDirty: false)
        self.tabs = [firstTab]
        self.activeTabId = firstTab.id
    }

    /// Called once from the app's `.onAppear` — starts the autosave timer and
    /// offers recovery if a previous session left an autosave behind.
    func startUp() {
        // Loop playback resolves its bounds live from the document, so retiming
        // a cue while it loops actually changes what you hear. AppState is the
        // one place that owns both models.
        media.loopBoundsProvider = { [weak document] id in
            guard let cue = document?.doc.cues.first(where: { $0.id == id }) else { return nil }
            return (cue.start, cue.end)
        }
        autosave.start()
        let snapshots = AutosaveService.pendingSnapshots().filter { !$0.glyph.isEmpty }
        if let newest = snapshots.first {
            recovery = newest
            olderRecoveries = Array(snapshots.dropFirst())
        }
        if settings.autoCheckUpdate {
            Task { [weak self] in
                guard let version = await UpdateCheck.checkForUpdate() else { return }
                self?.settings.availableUpdateVersion = version
            }
        }
    }

    // ── Subtitle file I/O ────────────────────────────────────────────────────────

    func openSubtitlePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = openExtensions().compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openSubtitlePath(url.path)
    }

    /// Re-opens the current file forcing an encoding — the recovery path when
    /// auto-detection produced mojibake, which previously had no way out.
    func reopenWithEncoding(_ label: String) {
        guard let path = document.filePath else { return }
        openSubtitlePath(path, forcingEncoding: label)
    }

    func openSubtitlePath(_ path: String, forcingEncoding label: String? = nil) {
        do {
            let parsed = try SubtitleFileIO.open(path: path, forcingEncoding: label)
            // A blank tab gets reused (the common "just opened the app,
            // File ▸ Open" case); reloading the SAME path in place handles
            // reopenWithEncoding's "no, it's actually CP949" retry. Anything
            // else opens alongside what's already there, as a new tab,
            // rather than silently discarding unsaved work the way this
            // action used to.
            if !activeTabIsBlank, document.filePath != path {
                openNewTab()
            }
            document.loadParsed(parsed, filePath: path, fileName: (path as NSString).lastPathComponent)
            settings.addRecentFile(path)
        } catch {
            lastError = t("errOpenSubtitle", readableError(error))
        }
    }

    /// ⌘S: save to the existing path if there is one, else prompt (Save As).
    /// Returns true on success (or user cancel of a no-op case), false if the
    /// user cancelled a needed Save-As dialog (caller should not proceed).
    @discardableResult
    func saveDocument() -> Bool {
        if let path = document.filePath, path.hasSuffix(".\(NATIVE_EXT)") {
            return writeGlyph(to: path)
        }
        return saveDocumentAs()
    }

    @discardableResult
    func saveDocumentAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: NATIVE_EXT)].compactMap { $0 }
        let base = (document.fileName ?? "untitled").replacingOccurrences(of: ".\(NATIVE_EXT)", with: "")
        panel.nameFieldStringValue = "\(base).\(NATIVE_EXT)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeGlyph(to: url.path)
    }

    private func writeGlyph(to path: String) -> Bool {
        do {
            try SubtitleFileIO.saveGlyph(document.doc, to: path)
            document.markSaved(path: path, name: (path as NSString).lastPathComponent)
            settings.addRecentFile(path)
            AutosaveService.clear()
            return true
        } catch {
            lastError = t("errSaveFailed", error.localizedDescription)
            return false
        }
    }

    // ── Export ───────────────────────────────────────────────────────────────────

    /// Warns first if exporting to SMI would drop ASS override tags.
    func exportDocument(format: SubFormat, source: DocumentModel.ExportSource = .text, encodingLabel: String? = nil) {
        if format == .smi, source == .text {
            let loss = smiExportLoss(document.doc)
            if !loss.isEmpty {
                pendingExport = PendingExport(format: format, source: source, encodingLabel: encodingLabel, categories: loss)
                return
            }
        }
        performExport(format: format, source: source, encodingLabel: encodingLabel)
    }

    func performExport(
        format: SubFormat,
        source: DocumentModel.ExportSource,
        encodingLabel: String?,
        scope: ExportScope = .all,
        rebaseToZero: Bool = false
    ) {
        let adapter = adapterForFormat(format)
        let panel = NSSavePanel()
        panel.allowedContentTypes = adapter.extensions.compactMap { UTType(filenameExtension: $0) }
        let base = (document.fileName ?? "untitled").replacingOccurrences(of: ".\(document.doc.format.rawValue)", with: "")
        let suffix = source == .translation ? ".translated" : ""
        panel.nameFieldStringValue = "\(base)\(suffix).\(adapter.extensions[0])"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = document.exportContent(format: format, source: source,
                                                 scope: scope, rebaseToZero: rebaseToZero)
            if format == .stl {
                // Binary format — raw bytes via the Latin-1 bridge, no text
                // encoding/CRLF/BOM options apply (see SubtitleFileIO.export).
                try Data(latin1StringToBytes(content)).write(to: url, options: .atomic)
            } else if format == .scc {
                // Plain ASCII hex text, but a fixed literal header real
                // decoders match byte-for-byte — the general encoding/BOM
                // settings (UTF-16 would interleave null bytes and corrupt
                // it outright; a BOM would break the header check) must not
                // apply here, same reasoning as STL just without needing the
                // Latin-1 bridge.
                try content.write(to: url, atomically: true, encoding: .utf8)
            } else {
                // An explicit per-format choice (the CP949 SMI entry) wins over
                // the general setting; otherwise the delivery preferences apply.
                var options = settings.textOutputOptions
                if let encodingLabel { options.encodingLabel = encodingLabel }
                try SubtitleFileIO.writeText(content, to: url.path, options: options)
            }
        } catch {
            lastError = t("errExportFailed", readableError(error))
        }
    }

    // ── Recovery ─────────────────────────────────────────────────────────────────

    func restoreRecovery(_ chosen: AutosaveData? = nil) {
        guard let recovery = chosen ?? recovery else { return }
        do {
            let doc = try parseGlyph(recovery.glyph)
            document.restoreDoc(doc, filePath: recovery.filePath, fileName: recovery.fileName)
        } catch {
            lastError = t("errRecoveryFailed", error.localizedDescription)
        }
        AutosaveService.clear()
        self.recovery = nil
        olderRecoveries = []
    }

    func discardRecovery() {
        AutosaveService.clear()
        recovery = nil
        olderRecoveries = []
    }

    // ── Media ────────────────────────────────────────────────────────────────────

    func openMediaPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = MEDIA_EXTS.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        media.loadMedia(url.path)
    }

    // ── Drag & drop ──────────────────────────────────────────────────────────────

    /// Routes a dropped file by extension to subtitle-open or media-open
    /// (ported from App.tsx's onDragDropEvent).
    func handleDroppedFile(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        if openExtensions().contains(ext) {
            openSubtitlePath(path)
        } else if MEDIA_EXTS.contains(ext) {
            media.loadMedia(path)
        }
    }
}

/// `localizedDescription` on a plain Swift error yields NSError's generic
/// "operation couldn't be completed (Domain error 0.)" — useless for the one
/// case the user can actually act on. Translate that case; pass the rest through.
@MainActor
func readableError(_ error: Error) -> String {
    if case FileIOError.encodingMismatch(let label) = error {
        return t("errEncodingMismatch", TextEncoding.displayName(forLabel: label))
    }
    return error.localizedDescription
}
