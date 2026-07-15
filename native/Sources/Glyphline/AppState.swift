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
    case findReplace, batchCleanup, pointSync, changeSpeed, statistics, shiftTime
    case styleManager, embeddedAssets, inlineTagEditor, settings, rawEditor, help, qualityIssues, closeConfirm

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
    var lastError: String?

    private var autosave: AutosaveService!

    init() {
        self.document = DocumentModel()
        self.media = MediaModel()
        self.settings = AppSettings()
        self.autosave = AutosaveService(document: document)
    }

    /// Called once from the app's `.onAppear` — starts the autosave timer and
    /// offers recovery if a previous session left an autosave behind.
    func startUp() {
        autosave.start()
        if let pending = AutosaveService.checkPending(), !pending.glyph.isEmpty {
            recovery = pending
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

    func openSubtitlePath(_ path: String) {
        do {
            let doc = try SubtitleFileIO.open(path: path)
            document.loadParsed(doc, filePath: path, fileName: (path as NSString).lastPathComponent)
            settings.addRecentFile(path)
        } catch {
            lastError = t("errOpenSubtitle", error.localizedDescription)
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

    func performExport(format: SubFormat, source: DocumentModel.ExportSource, encodingLabel: String?) {
        let adapter = adapterForFormat(format)
        let panel = NSSavePanel()
        panel.allowedContentTypes = adapter.extensions.compactMap { UTType(filenameExtension: $0) }
        let base = (document.fileName ?? "untitled").replacingOccurrences(of: ".\(document.doc.format.rawValue)", with: "")
        let suffix = source == .translation ? ".translated" : ""
        panel.nameFieldStringValue = "\(base)\(suffix).\(adapter.extensions[0])"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = document.exportContent(format: format, source: source)
            let encoding = encodingLabel.map(TextEncoding.encoding(forLabel:)) ?? .utf8
            try content.write(toFile: url.path, atomically: true, encoding: encoding)
        } catch {
            lastError = t("errExportFailed", error.localizedDescription)
        }
    }

    // ── Recovery ─────────────────────────────────────────────────────────────────

    func restoreRecovery() {
        guard let recovery else { return }
        do {
            let doc = try parseGlyph(recovery.glyph)
            document.restoreDoc(doc, filePath: recovery.filePath, fileName: recovery.fileName)
        } catch {
            lastError = t("errRecoveryFailed", error.localizedDescription)
        }
        AutosaveService.clear()
        self.recovery = nil
    }

    func discardRecovery() {
        AutosaveService.clear()
        recovery = nil
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
