// App shell layout: a free-docking area (video/waveform/subtitles — drag tabs
// to split/merge/reorder, see UI/Dock/) over a transport bar pinned to the
// bottom. Mirrors the Tauri app's flexlayout-based DockLayout, including
// per-launch persistence and View ▸ 레이아웃 초기화.

import SwiftUI
import GlyphlineCore

struct ContentView: View {
    let state: AppState
    @State private var dockDragState = DockDragState()

    var body: some View {
        VStack(spacing: 0) {
            TitleHeader(document: state.document)

            // The dock root: owns the drag coordinate space and resolves chip-drag
            // positions against the layout tree (dockHitTest) — both the live
            // zone preview and the drop commit derive from the same hit test.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    DockLayoutView(
                        node: state.settings.dockLayout,
                        dragState: dockDragState,
                        content: panelContent,
                        onSelect: { panel, path in state.settings.selectDockTab(panel, tabsetPath: path) },
                        onWeightsChange: { path, weights in state.settings.setDockWeights(at: path, to: weights) },
                        onTabDragChanged: { panel, location in
                            let hit = dockHitTest(location, in: state.settings.dockLayout, rect: CGRect(origin: .zero, size: geo.size))
                            // resolveDockDrop nils out no-op drops (e.g. onto the
                            // panel's own single-tab tabset) so no preview shows
                            // for them — a visible highlight always means the
                            // release will perform exactly that move.
                            let resolved = resolveDockDrop(dragged: panel, hit: hit, in: state.settings.dockLayout)
                            dockDragState.update(panel: panel, cursor: location, hit: resolved)
                        },
                        onTabDragEnded: { panel, location in
                            // Commit exactly what the last onChanged previewed. Do NOT
                            // recompute from onEnded's location: macOS DragGesture has
                            // reported end locations inconsistent with the preceding
                            // onChanged stream in named coordinate spaces, which made
                            // the drop silently miss while the preview looked right.
                            // The preview IS the contract — what you saw is what lands.
                            let target = dockDragState.hoverTarget
                            let zone = dockDragState.hoverZone
                            dockDragState.end()
                            if let target, let zone {
                                state.settings.moveDockPanel(panel, toZone: zone, ofTarget: target)
                            }
                        }
                    )

                    // Ghost chip following the cursor — the DragGesture-based drag
                    // has no system drag image, so this is the "I'm dragging" cue.
                    if let dragging = dockDragState.draggingPanel {
                        Text(t(dragging.titleKey))
                            .font(GlyphFont.display(11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(GlyphColor.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(GlyphColor.accent, in: RoundedRectangle(cornerRadius: 5))
                            .shadow(radius: 6)
                            .position(x: dockDragState.cursor.x, y: dockDragState.cursor.y - 14)
                            .allowsHitTesting(false)
                    }
                }
            }
            .coordinateSpace(name: DOCK_COORDINATE_SPACE)
            .padding(GlyphMetric.paneSpacing)

            TransportBar(media: state.media, document: state.document)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(GlyphColor.bg)
        .scaleEffect(state.settings.uiScale)
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

    private func panelContent(_ kind: PanelKind) -> AnyView {
        switch kind {
        case .video:
            return AnyView(Group {
                if state.media.mediaPath != nil, state.media.mediaKind == .video {
                    MPVVideoView(media: state.media, document: state.document)
                } else if MPVLibrary.isAvailable {
                    PanePlaceholder(message: state.media.mediaKind == .audio ? "♪ \(state.media.mediaName ?? "")" : t("noMediaHint"))
                } else {
                    PanePlaceholder(message: t("mpvMissing"))
                }
            })
        case .waveform:
            return AnyView(WaveformPane(document: state.document, media: state.media))
        case .subtitles:
            return AnyView(CuePane(document: state.document, media: state.media, settings: state.settings, onEditTags: { cue in
                state.document.setActiveCue(cue.id)
                state.activePanel = .inlineTagEditor
            }))
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
        case .closeConfirm: CloseConfirmPanel(state: state)
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
