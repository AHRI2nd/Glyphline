// App shell layout: video+waveform row over a cue-list row, transport pinned to
// the bottom. Mirrors the Tauri app's DockLayout ratio (video/waveform 42,
// cues 58) using AppKit-backed splits — arbitrary drag/drop docking like
// flexlayout is a stretch goal (see plan's Risk section); this fixed-but-resizable
// 3-pane split satisfies "구조 보전" for now.

import SwiftUI
import GlyphlineCore

struct ContentView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TitleHeader(document: state.document)

            VSplitView {
                HSplitView {
                    PaneChrome(title: t("panelVideo")) {
                        if state.media.mediaPath != nil, state.media.mediaKind == .video {
                            MPVVideoView(media: state.media, document: state.document)
                        } else if MPVLibrary.isAvailable {
                            PanePlaceholder(message: state.media.mediaKind == .audio ? "♪ \(state.media.mediaName ?? "")" : t("noMediaHint"))
                        } else {
                            PanePlaceholder(message: t("mpvMissing"))
                        }
                    }
                    .frame(minWidth: 240)

                    WaveformPane(document: state.document, media: state.media)
                        .frame(minWidth: 200)
                }
                .frame(minHeight: 180)

                CuePane(document: state.document, media: state.media, settings: state.settings, onEditTags: { cue in
                    state.document.setActiveCue(cue.id)
                    state.activePanel = .inlineTagEditor
                })
                    .frame(minHeight: 160)
            }

            TransportBar(media: state.media, document: state.document)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in state.handleDroppedFile(path: url.path) }
                }
            }
            return true
        }
        .sheet(item: Binding(get: { state.activePanel }, set: { state.activePanel = $0 })) { panel in
            panelView(panel)
        }
        .sheet(item: Binding(get: { state.pendingExport }, set: { state.pendingExport = $0 })) { pending in
            ExportWarningPanel(
                pending: pending,
                onConfirm: {
                    state.pendingExport = nil
                    state.performExport(format: pending.format, source: pending.source, encodingLabel: pending.encodingLabel)
                },
                onCancel: { state.pendingExport = nil }
            )
        }
        .sheet(item: Binding(get: { state.recovery }, set: { _ in })) { data in
            RecoveryPanel(
                data: data,
                onRestore: { state.restoreRecovery() },
                onDiscard: { state.discardRecovery() }
            )
        }
        .alert(t("errorTitle"), isPresented: Binding(get: { state.lastError != nil }, set: { if !$0 { state.lastError = nil } })) {
            Button(t("ok")) { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }

    @ViewBuilder
    private func panelView(_ panel: ActivePanel) -> some View {
        switch panel {
        case .findReplace: FindReplacePanel(document: state.document)
        case .batchCleanup: BatchCleanupPanel(document: state.document)
        case .pointSync: PointSyncPanel(document: state.document, media: state.media)
        case .changeSpeed: ChangeSpeedPanel(document: state.document)
        case .statistics: StatisticsPanel(document: state.document)
        case .shiftTime: ShiftTimePanel(document: state.document)
        case .qualityIssues: QualityIssuesPanel(document: state.document, settings: state.settings)
        case .styleManager: StyleManagerPanel(document: state.document)
        case .embeddedAssets: EmbeddedAssetsPanel(document: state.document)
        case .inlineTagEditor: InlineTagEditorPanel(document: state.document)
        case .settings: SettingsPanel(settings: state.settings)
        case .rawEditor: RawEditorPanel(document: state.document)
        case .help: HelpPanel()
        }
    }
}

private struct TitleHeader: View {
    let document: DocumentModel

    var body: some View {
        HStack {
            Text("Glyphline")
                .font(GlyphFont.display(14))
                .foregroundStyle(GlyphColor.signal)
            Spacer()
            HStack(spacing: 6) {
                Text(document.fileName ?? t("untitled"))
                    .font(GlyphFont.body(11))
                    .foregroundStyle(GlyphColor.quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if document.isDirty {
                    Text("• \(t("unsaved"))")
                        .font(GlyphFont.body(11))
                        .foregroundStyle(GlyphColor.warn)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .bottom)
    }
}
