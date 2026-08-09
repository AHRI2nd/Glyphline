// App entry point. Native menu bar via SwiftUI `.commands` (replaces appMenu.ts's
// Tauri Menu API).

import SwiftUI
import GlyphlineCore

@main
struct GlyphlineApp: App {
    @State private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

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
                Button(t("newFile")) { state.newDocumentTab() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(t("menuOpenSubtitle")) { state.openSubtitlePicker() }
                    .keyboardShortcut("o", modifiers: .command)
                recentFilesMenu
                Menu(t("reopenWithEncoding")) {
                    ForEach(TextEncoding.selectableLabels, id: \.self) { label in
                        Button(TextEncoding.displayName(forLabel: label)) {
                            state.reopenWithEncoding(label)
                        }
                    }
                }
                .disabled(state.document.filePath == nil)
                Button(t("openMedia")) { state.openMediaPicker() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(t("closeMedia")) { state.media.closeMedia() }
                    .disabled(state.media.mediaPath == nil)
                Divider()
                // ⌘⇧W rather than the system ⌘W (which SwiftUI already binds
                // to closing the whole window) — this closes the current TAB,
                // a different action that needs its own key.
                Button(t("closeTab")) { state.closeTab(state.activeTabId) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(state.tabs.count < 2)
                Button(t("nextTab")) { selectTab(offset: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(state.tabs.count < 2)
                Button(t("previousTab")) { selectTab(offset: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(state.tabs.count < 2)
                Divider()
                Button(t("save")) { state.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button(t("menuSaveAs")) { state.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                exportMenu
                Button(menuLabel("exportRange")) { state.activePanel = .exportRange }
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
                Button(t("findReplace")) { state.settings.revealPanel(.findReplace) }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu(t("subtitleMenu")) {
                Button(menuLabel("autoSpot")) { state.activePanel = .autoSpot }
                Button(t("addCue")) {
                    addCueAtPlayhead(
                        document: state.document, media: state.media,
                        frameRate: state.settings.frameMode
                            ? state.settings.effectiveFrameRate(detected: state.media.detectedFrameRate)
                            : nil
                    )
                }
                .keyboardShortcut(.return, modifiers: .command)
                // Split/merge/delete/duplicate are the operations a timing pass
                // repeats hundreds of times; they had no accelerators at all.
                // ⌘S/⌘⇧S (save/save as) are taken, hence ⌘⌥S for split.
                Button(t("splitCue")) { splitActiveCue() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(state.document.activeCueId == nil)
                Button(t("mergeCues")) {
                    state.document.mergeCues(Array(state.document.selectedIds))
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(state.document.selectedIds.count < 2)
                Button(t("ctxDuplicate")) {
                    guard let id = state.document.activeCueId else { return }
                    state.document.duplicateCue(id)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(state.document.activeCueId == nil)
                // ⌘⌫ rather than a bare ⌫: a plain Delete key equivalent on a
                // menu item is matched before the responder chain, which would
                // swallow backspace in every text field in the app. The bare
                // Delete key still deletes when the GRID itself has focus —
                // CueTableView handles it there, where no field editor is active.
                Button(t("deleteCue")) {
                    state.document.deleteCues(Array(state.document.selectedIds))
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.document.selectedIds.isEmpty)
                Divider()
                Button(menuLabel("shiftTime")) { state.activePanel = .shiftTime }
                Button(menuLabel("pointSync")) { state.activePanel = .pointSync }
                Button(menuLabel("changeSpeed")) { state.activePanel = .changeSpeed }
                Button(menuLabel("batchCleanup")) { state.activePanel = .batchCleanup }
                Button(t("statistics")) { state.settings.revealPanel(.statistics) }
                Button(t("overview")) { state.settings.revealPanel(.overview) }
                Button(t("historyPanel")) { state.settings.revealPanel(.history) }
                Button(t("qualityIssues")) { state.settings.revealPanel(.qualityIssues) }
                Button(t("spellCheck")) { state.settings.revealPanel(.proofread) }
                Button(t("translationCheck")) { state.settings.revealPanel(.translationCheck) }
                Button(menuLabel("compareFiles")) { state.activePanel = .compareFiles }
                Button(menuLabel("batchConvert")) { state.activePanel = .batchConvert }
                Button(menuLabel("deliveryPipeline")) { state.activePanel = .deliveryPipeline }
                Button(menuLabel("customRules")) { state.activePanel = .customRules }
                Divider()
                Button(menuLabel("styleManager")) { state.activePanel = .styleManager }
                Button(t("inlineTagEditor")) { state.settings.revealPanel(.inspector) }
                Button(menuLabel("resampleResolution")) { state.activePanel = .resampleResolution }
                Button(menuLabel("burnIn")) { state.activePanel = .burnIn }
                Button(t("karaokeTiming")) { state.settings.revealPanel(.karaoke) }
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
                Divider()
                audioTrackMenu
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
                Menu(t("panelsMenu")) {
                    ForEach(PanelKind.allCases, id: \.self) { panel in
                        Toggle(t(panel.titleKey), isOn: Binding(
                            get: { state.settings.visiblePanels.contains(panel) },
                            set: { _ in state.settings.togglePanel(panel) }
                        ))
                    }
                }
                Button(t("resetLayout")) { state.settings.resetDockLayout() }
                Divider()
                // A second-monitor layout (video on one screen, grid/waveform
                // on the other) — the dock can only rearrange panels within
                // ONE window, so this is a separate OS window instead.
                Toggle(t("detachVideoWindow"), isOn: Binding(
                    get: { state.videoDetached },
                    set: { detach in
                        state.videoDetached = detach
                        if detach {
                            openWindow(id: DETACHED_VIDEO_WINDOW_ID)
                        } else {
                            dismissWindow(id: DETACHED_VIDEO_WINDOW_ID)
                        }
                    }
                ))
                Button(t("activityWindowTitle")) { openWindow(id: ACTIVITY_WINDOW_ID) }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                Button(t("miniPlayerWindowTitle")) { openWindow(id: MINI_PLAYER_WINDOW_ID) }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button(t("dashboardWindowTitle")) { openWindow(id: PROJECT_DASHBOARD_WINDOW_ID) }
                Button(t("sharedGlossaryWindowTitle")) { openWindow(id: SHARED_GLOSSARY_WINDOW_ID) }
                Divider()
                Toggle(t("showCueEditor"), isOn: Binding(
                    get: { state.settings.showCueEditor },
                    set: { state.settings.showCueEditor = $0 }
                ))
                Toggle(t("showTranslation"), isOn: Binding(
                    get: { state.settings.showTranslation },
                    set: { state.settings.showTranslation = $0 }
                ))
                Toggle(t("showActor"), isOn: Binding(
                    get: { state.settings.showActor },
                    set: { state.settings.showActor = $0 }
                ))
                Toggle(t("safeGuides"), isOn: Binding(
                    get: { state.settings.showSafeGuides },
                    set: { state.settings.showSafeGuides = $0 }
                ))
                Toggle(t("frameTimecode"), isOn: Binding(
                    get: { state.settings.frameMode },
                    set: { state.settings.frameMode = $0 }
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

        // The detached video window — see DetachedVideoWindow.swift. A
        // separate top-level Window scene (not a sheet/panel), so it gets its
        // own title bar, can move to a second monitor, and survives
        // independently of the main window's dock layout.
        Window(t("videoWindowTitle"), id: DETACHED_VIDEO_WINDOW_ID) {
            DetachedVideoWindow(state: state)
        }
        .defaultSize(width: 640, height: 400)

        // Persistent background-job monitor — see ActivityWindow.swift.
        Window(t("activityWindowTitle"), id: ACTIVITY_WINDOW_ID) {
            ActivityWindow(state: state)
        }
        .defaultSize(width: 420, height: 320)

        // Always-on-top playback controller — see MiniPlayerWindow.swift.
        Window(t("miniPlayerWindowTitle"), id: MINI_PLAYER_WINDOW_ID) {
            MiniPlayerWindow(state: state)
        }
        .defaultSize(width: 280, height: 150)
        .windowResizability(.contentSize)

        // Multi-tab overview — see ProjectDashboardWindow.swift.
        Window(t("dashboardWindowTitle"), id: PROJECT_DASHBOARD_WINDOW_ID) {
            ProjectDashboardWindow(state: state)
        }
        .defaultSize(width: 460, height: 320)

        // Cross-project term glossary — see SharedGlossaryWindow.swift.
        Window(t("sharedGlossaryWindowTitle"), id: SHARED_GLOSSARY_WINDOW_ID) {
            SharedGlossaryWindow(settings: state.settings)
        }
        .defaultSize(width: 440, height: 340)

        // Any dock panel torn off by dragging its tab past the window's own
        // edge — see DockTearOff.swift/TornOffPanelWindow.swift. One dynamic
        // per-value window group rather than a static Window per PanelKind:
        // several panels can be torn off into separate windows at once.
        WindowGroup(t("tornOffWindowTitle"), for: PanelKind.self) { $kind in
            if let kind {
                TornOffPanelWindow(state: state, kind: kind)
            }
        }
        .defaultSize(width: 420, height: 320)
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

    /// ⌘⌥←/→ — cycles tabs, wrapping at either end.
    private func selectTab(offset: Int) {
        guard state.tabs.count > 1, let idx = state.tabs.firstIndex(where: { $0.id == state.activeTabId }) else { return }
        let next = (idx + offset + state.tabs.count) % state.tabs.count
        state.switchToTab(state.tabs[next].id)
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

    /// Playback ▸ 오디오 트랙 ▸ — which stream you're timing against. Single-track
    /// files still show the entry (disabled) rather than hiding it, so its absence
    /// never reads as "this app can't do that".
    @ViewBuilder
    private var audioTrackMenu: some View {
        Menu(t("audioTrack")) {
            if state.media.audioTracks.isEmpty {
                Text(t("noAudioTracks"))
            } else {
                ForEach(state.media.audioTracks) { track in
                    Toggle(track.label, isOn: Binding(
                        get: { state.media.currentAudioTrackId == track.id },
                        set: { _ in state.media.selectAudioTrack(track.id) }
                    ))
                }
            }
        }
        .disabled(state.media.audioTracks.count < 2)
    }

    /// File ▸ 내보내기 ▸ — a submenu (View), nested inside the File CommandGroup.
    @ViewBuilder
    private var exportMenu: some View {
        Menu(t("exportAs")) {
            Button("SubRip (.srt)") { state.exportDocument(format: .srt) }
            Button("WebVTT (.vtt)") { state.exportDocument(format: .vtt) }
            Button("ASS/SSA (.ass)") { state.exportDocument(format: .ass) }
            Button("TTML/DFXP (.ttml)") { state.exportDocument(format: .ttml) }
            Button("SAMI (.smi)") { state.exportDocument(format: .smi) }
            Button(t("exportSmiCp949")) { state.exportDocument(format: .smi, encodingLabel: "cp949") }
            Divider()
            Button("YouTube (.sbv)") { state.exportDocument(format: .sbv) }
            Button("LRC (.lrc)") { state.exportDocument(format: .lrc) }
            Button("Plain Text (.txt)") { state.exportDocument(format: .txt) }
            Divider()
            Button("EBU-STL (.stl)") { state.exportDocument(format: .stl) }
            Button("Scenarist SCC (.scc)") { state.exportDocument(format: .scc) }
        }
    }
}
