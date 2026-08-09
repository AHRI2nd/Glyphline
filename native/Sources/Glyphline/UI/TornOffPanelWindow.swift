// A dock panel torn out into its own floating OS window — the display half
// of the drag-to-detach/drag-to-merge system; the mechanics live in
// DockTearOff.swift. Dragging the header bar back over the main window's
// dock re-merges the panel at the exact zone dropped on, using the SAME
// dockHitTest/resolveDockDrop pipeline an ordinary in-dock tab drag uses —
// it just feeds in a cross-window-translated point instead of a same-window
// GeometryReader one. Closing the window (red button, or ⌘W) merges the
// panel back at a default spot instead, since there's no drop position to be
// precise about there.

import SwiftUI
import AppKit
import GlyphlineCore

struct TornOffPanelWindow: View {
    let state: AppState
    let kind: PanelKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    /// Set once a drag has actually resolved a merge, so onDisappear (which
    /// fires right after dismiss() too) doesn't ALSO run the default
    /// merge-back and re-add the panel a second time.
    @State private var didMergeOnDrag = false

    var body: some View {
        VStack(spacing: 0) {
            header
            dockPanelContent(kind, state: state, dismissWindow: dismissWindow)
                .environment(\.panelPresentation, .pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
        .frame(minWidth: 340, minHeight: 240)
        .onDisappear {
            guard !didMergeOnDrag else { return }
            state.mergePanelBackDefault(kind)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(GlyphColor.quiet.opacity(0.6))
            Text(t(kind.titleKey))
                .textCase(.uppercase).tracking(0.5)
                .font(GlyphFont.display(11, weight: .semibold))
                .foregroundStyle(GlyphColor.ink)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .bottom)
        .contentShape(Rectangle())
        .help(t("dragToMerge"))
        // .global here is this window's own coordinate space — irrelevant to
        // the merge logic below, which reads NSEvent.mouseLocation (true
        // screen coordinates) directly instead, the same way the in-dock
        // drag's tear-off check does (see ContentView's onTabDragEnded).
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    let screenPoint = NSEvent.mouseLocation
                    if let local = state.dockLocalPoint(forScreenPoint: screenPoint) {
                        let hit = dockHitTest(local, in: state.settings.dockLayout,
                                               rect: CGRect(origin: .zero, size: state.dockRootSize))
                        let resolved = resolveDockDrop(dragged: kind, hit: hit, in: state.settings.dockLayout)
                        state.dockDragState.update(panel: kind, cursor: local, hit: resolved)
                    } else {
                        state.dockDragState.update(panel: kind, cursor: .zero, hit: nil)
                    }
                }
                .onEnded { _ in
                    let target = state.dockDragState.hoverTarget
                    let zone = state.dockDragState.hoverZone
                    state.dockDragState.end()
                    if let target, let zone {
                        state.mergePanelBack(kind, toZone: zone, ofTarget: target)
                        didMergeOnDrag = true
                        dismiss()
                    }
                }
        )
    }
}
