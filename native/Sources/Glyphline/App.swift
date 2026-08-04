// App entry point. Native menu bar via SwiftUI `.commands` (replaces appMenu.ts's
// Tauri Menu API).

import SwiftUI
import GlyphlineCore

@main
struct GlyphlineApp: App {
    @State private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .onAppear {
                    appDelegate.state = state
                    state.startUp()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(t("newFile")) { state.document.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(t("menuOpenSubtitle")) { state.openSubtitlePicker() }
                    .keyboardShortcut("o", modifiers: .command)
                recentFilesMenu
                Button(t("openMedia")) { state.openMediaPicker() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(t("closeMedia")) { state.media.closeMedia() }
                    .disabled(state.media.mediaPath == nil)
                Divider()
                Button(t("save")) { state.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button(t("menuSaveAs")) { state.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                exportMenu
                Button(t("menuExportTranslation")) {
                    state.exportDocument(format: state.document.doc.format, source: .translation)
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button(t("undo")) { state.document.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.document.canUndo)
                Button(t("redo")) { state.document.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.document.canRedo)
                Divider()
                Button(menuLabel("findReplace")) { state.activePanel = .findReplace }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu(t("subtitleMenu")) {
                Button(t("addCue")) { state.document.addCue() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button(t("splitCue")) { splitActiveCue() }
                    .disabled(state.document.activeCueId == nil)
                Button(t("mergeCues")) {
                    state.document.mergeCues(Array(state.document.selectedIds))
                }
                .disabled(state.document.selectedIds.count < 2)
                Button(t("deleteCue")) {
                    state.document.deleteCues(Array(state.document.selectedIds))
                }
                .disabled(state.document.selectedIds.isEmpty)
                Divider()
                Button(menuLabel("shiftTime")) { state.activePanel = .shiftTime }
                Button(menuLabel("pointSync")) { state.activePanel = .pointSync }
                Button(menuLabel("changeSpeed")) { state.activePanel = .changeSpeed }
                Button(menuLabel("batchCleanup")) { state.activePanel = .batchCleanup }
                Button(menuLabel("statistics")) { state.activePanel = .statistics }
                Button(menuLabel("qualityIssues")) { state.activePanel = .qualityIssues }
                Button(menuLabel("spellCheck")) { state.activePanel = .spellCheck }
                Divider()
                Button(menuLabel("styleManager")) { state.activePanel = .styleManager }
                Button(menuLabel("inlineTagEditor")) { state.activePanel = .inlineTagEditor }
                Button(menuLabel("embeddedAssets")) { state.activePanel = .embeddedAssets }
                Button(menuLabel("rawEdit")) { state.activePanel = .rawEditor }
            }
            // No Space accelerator here — it would block typing spaces in cue
            // text (matches appMenu.ts's playbackMenu).
            CommandMenu(t("playbackMenu")) {
                Button(t("playPause")) { state.media.togglePlay() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button(t("skipBack5")) { state.media.skip(-5) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                Button(t("skipBack1")) { state.media.skip(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button(t("skipFwd1")) { state.media.skip(1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(t("skipFwd5")) { state.media.skip(5) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            }
            CommandGroup(after: .appSettings) {
                Button(menuLabel("settings")) { state.activePanel = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            // Merged into the single, system-titled View menu (CommandMenu
            // would instead open a SECOND top-level menu next to it, titled
            // in our in-app language while AppKit's own "View" stays in the
            // system's language — the exact mismatch this was written to fix).
            CommandGroup(after: .toolbar) {
                Divider()
                Button(t("resetLayout")) { state.settings.resetDockLayout() }
                Divider()
                Toggle(t("showTranslation"), isOn: Binding(
                    get: { state.settings.showTranslation },
                    set: { state.settings.showTranslation = $0 }
                ))
                Toggle(t("showActor"), isOn: Binding(
                    get: { state.settings.showActor },
                    set: { state.settings.showActor = $0 }
                ))
                Divider()
                Menu(t("language")) {
                    Picker("", selection: Binding(
                        get: { state.settings.language },
                        set: { state.settings.language = $0 }
                    )) {
                        Text("한국어").tag(AppLang.ko)
                        Text("English").tag(AppLang.en)
                        Text("日本語").tag(AppLang.ja)
                    }
                    .pickerStyle(.inline)
                }
            }
            CommandGroup(replacing: .help) {
                Button(menuLabel("shortcuts")) { state.activePanel = .help }
            }
        }
    }

    /// Splits the active cue at the playhead if it falls inside it, else at the
    /// midpoint (mirrors appMenu.ts's onSplit / CueList.tsx ContextMenu splitCue).
    private func splitActiveCue() {
        guard let id = state.document.activeCueId,
              let cue = state.document.doc.cues.first(where: { $0.id == id }) else { return }
        let tNow = state.media.mediaPath != nil ? state.media.currentTime : nil
        let at = (tNow.map { $0 > cue.start && $0 < cue.end } == true) ? tNow! : (cue.start + cue.end) / 2
        state.document.splitCue(cue.id, atTime: at)
    }

    /// File ▸ 최근 파일 ▸ — a submenu (View), nested inside the File CommandGroup.
    @ViewBuilder
    private var recentFilesMenu: some View {
        Menu(t("recentFilesMenu")) {
            if state.settings.recentFiles.isEmpty {
                Text(t("noRecentFiles"))
            } else {
                ForEach(state.settings.recentFiles, id: \.self) { path in
                    Button((path as NSString).lastPathComponent) { state.openSubtitlePath(path) }
                }
                Divider()
                Button(t("clearRecentFiles")) { state.settings.clearRecentFiles() }
            }
        }
    }

    /// File ▸ 내보내기 ▸ — a submenu (View), nested inside the File CommandGroup.
    @ViewBuilder
    private var exportMenu: some View {
        Menu(t("exportAs")) {
            Button("SubRip (.srt)") { state.exportDocument(format: .srt) }
            Button("WebVTT (.vtt)") { state.exportDocument(format: .vtt) }
            Button("ASS/SSA (.ass)") { state.exportDocument(format: .ass) }
            Button("SAMI (.smi)") { state.exportDocument(format: .smi) }
            Button(t("exportSmiCp949")) { state.exportDocument(format: .smi, encodingLabel: "cp949") }
            Divider()
            Button("YouTube (.sbv)") { state.exportDocument(format: .sbv) }
            Button("LRC (.lrc)") { state.exportDocument(format: .lrc) }
            Button("Plain Text (.txt)") { state.exportDocument(format: .txt) }
        }
    }
}
