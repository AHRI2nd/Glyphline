// App shell layout: a free-docking area (video/waveform/subtitles — drag tabs
// to split/merge/reorder, see UI/Dock/) over a transport bar pinned to the
// bottom. Mirrors the Tauri app's flexlayout-based DockLayout, including
// per-launch persistence and View ▸ 레이아웃 초기화.

import SwiftUI
import GlyphlineCore

struct ContentView: View {
    let state: AppState
    @State private var dockDragState = DockDragState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        badge: { $0 == .subtitles ? state.document.doc.cues.count : nil },
                        onSelect: { panel, path in
                            withAnimation(.easeOut(duration: 0.15)) {
                                state.settings.selectDockTab(panel, tabsetPath: path)
                            }
                        },
                        onWeightsChange: { path, weights in state.settings.setDockWeights(at: path, to: weights) },
                        onTabDragChanged: { panel, location in
                            let hit = dockHitTest(location, in: state.settings.dockLayout, rect: CGRect(origin: .zero, size: geo.size))
                            // resolveDockDrop nils out no-op drops (e.g. onto the
                            // panel's own single-tab tabset) so no preview shows
                            // for them — a visible highlight always means the
                            // release will perform exactly that move.
                            let resolved = resolveDockDrop(dragged: panel, hit: hit, in: state.settings.dockLayout)
                            // Only the pickup animates (scrim fades in, chip lifts);
                            // every later frame is applied raw so cursor tracking
                            // stays exactly 1:1 with the pointer.
                            if dockDragState.draggingPanel == nil, !reduceMotion {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    dockDragState.update(panel: panel, cursor: location, hit: resolved)
                                }
                            } else {
                                dockDragState.update(panel: panel, cursor: location, hit: resolved)
                            }
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
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                                dockDragState.end()
                            }
                            if let target, let zone {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                                    state.settings.moveDockPanel(panel, toZone: zone, ofTarget: target)
                                }
                            }
                        }
                    )

                    // Dims the workspace and lights the destination — see
                    // DockDragOverlay for the full rationale.
                    if dockDragState.isDragging {
                        DockDragOverlay(
                            dragState: dockDragState,
                            layout: state.settings.dockLayout,
                            dockSize: geo.size
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    // The tab in hand. Rides above the scrim on a raised shadow so
                    // it reads as lifted off the surface rather than pasted on it.
                    if let dragging = dockDragState.draggingPanel {
                        Text(t(dragging.titleKey))
                            .font(GlyphFont.display(11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(GlyphColor.accent, in: RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
                            // Tracks the cursor with zero lag — precision beats
                            // smoothing for a 1:1 follower. Only the pickup is
                            // animated, so the drag doesn't pop into existence.
                            .position(x: dockDragState.cursor.x, y: dockDragState.cursor.y - 16)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
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
                older: state.olderRecoveries,
                onRestore: { state.restoreRecovery($0) },
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
                } else if state.media.mediaKind == .audio {
                    // Media IS loaded here — just not a video — so this isn't an
                    // empty state needing an action, only a status note.
                    PanePlaceholder(icon: "music.note", title: t("audioLoadedTitle"), subtitle: state.media.mediaName)
                } else if MPVLibrary.isAvailable {
                    PanePlaceholder(
                        icon: "film", title: t("noMediaShort"), subtitle: t("noMediaDesc"),
                        actions: [PlaceholderAction(label: t("openMedia"), prominent: true) { state.openMediaPicker() }]
                    )
                } else {
                    PanePlaceholder(
                        icon: "exclamationmark.triangle", title: t("mpvMissing"), subtitle: t("mpvMissingDesc"),
                        actions: [PlaceholderAction(label: menuLabel("settings")) { state.activePanel = .settings }]
                    )
                }
            })
        case .waveform:
            return AnyView(WaveformPane(document: state.document, media: state.media, settings: state.settings, onOpenMedia: { state.openMediaPicker() }))
        case .subtitles:
            return AnyView(CuePane(
                document: state.document, media: state.media, settings: state.settings,
                onEditTags: { cue in
                    state.document.setActiveCue(cue.id)
                    state.activePanel = .inlineTagEditor
                },
                onOpenSubtitle: { state.openSubtitlePicker() }
            ))
        }
    }

    @ViewBuilder
    private func panelView(_ panel: ActivePanel) -> some View {
        switch panel {
        case .findReplace: FindReplacePanel(document: state.document)
        case .batchCleanup: BatchCleanupPanel(document: state.document, settings: state.settings)
        case .pointSync: PointSyncPanel(document: state.document, media: state.media)
        case .changeSpeed: ChangeSpeedPanel(document: state.document)
        case .statistics: StatisticsPanel(document: state.document)
        case .shiftTime: ShiftTimePanel(document: state.document)
        case .qualityIssues: QualityIssuesPanel(document: state.document, settings: state.settings)
        case .spellCheck: SpellCheckPanel(document: state.document, settings: state.settings)
        case .translationCheck: TranslationCheckPanel(document: state.document, settings: state.settings)
        case .compareFiles:
            CompareFilesPanel(document: state.document, media: state.media) { state.lastError = $0 }
        case .karaokeTiming: KaraokeTimingPanel(document: state.document, media: state.media)
        case .closeConfirm: CloseConfirmPanel(state: state)
        case .styleManager: StyleManagerPanel(document: state.document)
        case .embeddedAssets: EmbeddedAssetsPanel(document: state.document)
        case .inlineTagEditor: InlineTagEditorPanel(document: state.document)
        case .settings: SettingsPanel(settings: state.settings, media: state.media)
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
