// App shell layout: a free-docking area (video/waveform/subtitles — drag tabs
// to split/merge/reorder, see UI/Dock/) over a transport bar pinned to the
// bottom. Mirrors the Tauri app's flexlayout-based DockLayout, including
// per-launch persistence and View ▸ 레이아웃 초기화.

import SwiftUI
import GlyphlineCore

struct ContentView: View {
    let state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            TitleHeader(state: state)
            DocumentTabBar(state: state)

            // The dock root: owns the drag coordinate space and resolves chip-drag
            // positions against the layout tree (dockHitTest) — both the live
            // zone preview and the drop commit derive from the same hit test.
            // ViewAccessor captures this ZStack's own NSView so a torn-off
            // panel's window (a separate SwiftUI Window/view hierarchy) can
            // still hit-test its drag against this exact rect — see
            // DockTearOff.swift.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ViewAccessor { view in state.dockRootView = view }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    DockLayoutView(
                        node: state.settings.dockLayout,
                        dragState: state.dockDragState,
                        content: { dockPanelContent($0, state: state, dismissWindow: dismissWindow) },
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
                            if state.dockDragState.draggingPanel == nil, !reduceMotion {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    state.dockDragState.update(panel: panel, cursor: location, hit: resolved)
                                }
                            } else {
                                state.dockDragState.update(panel: panel, cursor: location, hit: resolved)
                            }
                            // .video can't be torn off past the window edge
                            // (see DockTearOff.swift) — every other tab shows
                            // an inviting closedHand cursor there, but video
                            // would just silently snap back on release with
                            // no explanation. Swap to the standard macOS
                            // "not allowed" cursor the instant it crosses the
                            // edge, so the drag itself signals why.
                            if panel == .video {
                                let blocked = !state.isPointInsideMainWindow(NSEvent.mouseLocation)
                                (blocked ? NSCursor.operationNotAllowed : NSCursor.closedHand).set()
                            }
                        },
                        onTabDragEnded: { panel, location in
                            // Commit exactly what the last onChanged previewed. Do NOT
                            // recompute the in-dock hit from onEnded's location: macOS
                            // DragGesture has reported end locations inconsistent with
                            // the preceding onChanged stream in named coordinate
                            // spaces, which made the drop silently miss while the
                            // preview looked right. The preview IS the contract — what
                            // you saw is what lands. The tear-off check below is
                            // exempt from that concern: it reads NSEvent.mouseLocation
                            // (global screen coordinates) directly, sidestepping named-
                            // coordinate-space reporting entirely.
                            let target = state.dockDragState.hoverTarget
                            let zone = state.dockDragState.hoverZone
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                                state.dockDragState.end()
                            }
                            if !state.isPointInsideMainWindow(NSEvent.mouseLocation) {
                                // Dropped past the window's own edge — pop it into
                                // its own floating window instead of an in-dock
                                // move. .video is excluded (see DockTearOff.swift);
                                // tearOffPanel() is a no-op for it.
                                state.tearOffPanel(panel, openWindow: openWindow)
                            } else if let target, let zone {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84)) {
                                    state.settings.moveDockPanel(panel, toZone: zone, ofTarget: target)
                                }
                            }
                        }
                    )

                    // Dims the workspace and lights the destination — see
                    // DockDragOverlay for the full rationale.
                    if state.dockDragState.isDragging {
                        DockDragOverlay(
                            dragState: state.dockDragState,
                            layout: state.settings.dockLayout,
                            dockSize: geo.size
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    // The tab in hand. Rides above the scrim on a raised shadow so
                    // it reads as lifted off the surface rather than pasted on it.
                    if let dragging = state.dockDragState.draggingPanel {
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
                            .position(x: state.dockDragState.cursor.x, y: state.dockDragState.cursor.y - 16)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
            }
            .coordinateSpace(name: DOCK_COORDINATE_SPACE)
            .padding(GlyphMetric.paneSpacing)

            TransportBar(
                media: state.media,
                document: state.document,
                frameRate: state.settings.frameMode
                    ? state.settings.effectiveFrameRate(detected: state.media.detectedFrameRate)
                    : nil
            )
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(ViewAccessor { view in state.mainWindow = view.window })
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

    @ViewBuilder
    private func panelView(_ panel: ActivePanel) -> some View {
        switch panel {
        case .batchCleanup: BatchCleanupPanel(document: state.document, settings: state.settings, media: state.media)
        case .pointSync: PointSyncPanel(document: state.document, media: state.media)
        case .changeSpeed: ChangeSpeedPanel(document: state.document)
        case .shiftTime: ShiftTimePanel(document: state.document)
        case .compareFiles:
            CompareFilesPanel(document: state.document, media: state.media) { state.lastError = $0 }
        case .exportRange: ExportRangePanel(state: state)
        case .autoSpot: AutoSpotPanel(document: state.document, media: state.media)
        case .batchConvert: BatchConvertPanel(state: state)
        case .deliveryPipeline: DeliveryPipelinePanel(state: state)
        case .customRules: CustomRulesPanel(document: state.document, settings: state.settings)
        case .resampleResolution: ResampleResolutionPanel(document: state.document)
        case .burnIn: BurnInPanel(state: state)
        case .closeConfirm(let tabToClose): CloseConfirmPanel(state: state, tabToClose: tabToClose)
        case .styleManager: StyleManagerPanel(document: state.document)
        case .embeddedAssets: EmbeddedAssetsPanel(document: state.document)
        case .settings: SettingsPanel(settings: state.settings, media: state.media, document: state.document)
        case .rawEditor: RawEditorPanel(document: state.document)
        case .help: HelpPanel()
        }
    }
}

/// Renders a dock panel's live content for `kind` — shared between the main
/// window's dock (ContentView) and a torn-off panel's own window
/// (TornOffPanelWindow), so a panel looks and behaves identically whichever
/// one currently hosts it. A free function (not a ContentView method) so
/// TornOffPanelWindow, which has no ContentView instance, can call it too.
@MainActor
func dockPanelContent(_ kind: PanelKind, state: AppState, dismissWindow: DismissWindowAction) -> AnyView {
    switch kind {
    case .video:
        return AnyView(Group {
            if state.videoDetached {
                // The real MPVVideoView lives in the detached window right
                // now — never render a second one here, since each
                // instance owns its own mpv playback instance (see
                // DetachedVideoWindow's header note).
                PanePlaceholder(
                    icon: "macwindow.on.rectangle", title: t("videoDetachedTitle"), subtitle: t("videoDetachedDesc"),
                    actions: [PlaceholderAction(label: t("redockVideo"), prominent: true) {
                        // Both paths back must close the OTHER window,
                        // not just flip the flag — otherwise the detached
                        // window would keep rendering its own MPVVideoView
                        // at the same time this pane resumes rendering
                        // its own, and two mpv instances would end up
                        // fighting over the same file.
                        state.videoDetached = false
                        dismissWindow(id: DETACHED_VIDEO_WINDOW_ID)
                    }]
                )
            } else if state.media.mediaPath != nil, state.media.mediaKind == .video {
                MPVVideoView(media: state.media, document: state.document, settings: state.settings)
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
    case .qualityIssues:
        return AnyView(QualityIssuesPanel(document: state.document, settings: state.settings, media: state.media)
            .environment(\.panelPresentation, .pane))
    case .proofread:
        return AnyView(SpellCheckPanel(document: state.document, settings: state.settings)
            .environment(\.panelPresentation, .pane))
    case .translationCheck:
        return AnyView(TranslationCheckPanel(document: state.document, settings: state.settings)
            .environment(\.panelPresentation, .pane))
    case .findReplace:
        return AnyView(FindReplacePanel(document: state.document)
            .environment(\.panelPresentation, .pane))
    case .karaoke:
        return AnyView(KaraokeTimingPanel(document: state.document, media: state.media)
            .environment(\.panelPresentation, .pane))
    case .overview:
        return AnyView(OverviewPanel(document: state.document, media: state.media)
            .environment(\.panelPresentation, .pane))
    case .history:
        return AnyView(HistoryPanel(document: state.document)
            .environment(\.panelPresentation, .pane))
    case .inspector:
        return AnyView(InlineTagEditorPanel(document: state.document, media: state.media)
            .environment(\.panelPresentation, .pane))
    case .statistics:
        return AnyView(StatisticsPanel(document: state.document)
            .environment(\.panelPresentation, .pane))
    case .activity:
        return AnyView(ActivityWindow(state: state)
            .environment(\.panelPresentation, .pane))
    case .miniPlayer:
        return AnyView(MiniPlayerWindow(state: state)
            .environment(\.panelPresentation, .pane))
    case .projectDashboard:
        return AnyView(ProjectDashboardWindow(state: state)
            .environment(\.panelPresentation, .pane))
    case .sharedGlossary:
        return AnyView(SharedGlossaryWindow(settings: state.settings)
            .environment(\.panelPresentation, .pane))
    case .subtitles:
        return AnyView(CuePane(
            document: state.document, media: state.media, settings: state.settings,
            onEditTags: { cue in
                state.document.setActiveCue(cue.id)
                state.settings.revealPanel(.inspector)
            },
            onOpenSubtitle: { state.openSubtitlePicker() }
        ))
    }
}

private struct TitleHeader: View {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Text("Glyphline")
                .font(GlyphFont.display(14))
                .foregroundStyle(GlyphColor.signal)
            Spacer()
            HStack(spacing: 10) {
                if !state.backgroundJobs.isEmpty {
                    activityIndicator
                }
                HStack(spacing: 6) {
                    Text(state.document.fileName ?? t("untitled"))
                        .font(GlyphFont.body(11))
                        .foregroundStyle(GlyphColor.quiet)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if state.document.isDirty {
                        Text("• \(t("unsaved"))")
                            .font(GlyphFont.body(11))
                            .foregroundStyle(GlyphColor.warn)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .bottom)
    }

    /// Only shown once something has run this session — an empty tray icon
    /// on every launch would just be noise. Running jobs get a live spinner;
    /// once everything's settled it stays as a plain marker so a finished
    /// (or failed) job someone isn't watching is still discoverable.
    private var activityIndicator: some View {
        Button { if !state.activityWindowOpen { openWindow(id: ACTIVITY_WINDOW_ID) } } label: {
            HStack(spacing: 4) {
                if state.runningBackgroundJobCount > 0 {
                    ProgressView().controlSize(.mini)
                    Text("\(state.runningBackgroundJobCount)").font(GlyphFont.data(10))
                } else {
                    Image(systemName: "checkmark.circle").font(.system(size: 11))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.runningBackgroundJobCount > 0 ? GlyphColor.signal : GlyphColor.quiet)
        .help(t("activityWindowTitle"))
    }
}
