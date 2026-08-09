// Drag a dock tab past the main window's own edge to pop it into its own
// floating OS window ("tear off"); drag that window's header back over the
// main dock to merge it back in (see TornOffPanelWindow.swift). Reuses the
// exact same zone-preview/hit-test pipeline as in-window tab dragging
// (dockHitTest/resolveDockDrop/movingPanel in DockModel.swift) — the only
// genuinely new piece is translating a cross-window global (screen) point
// into the dock root's local coordinate space, since SwiftUI's named
// coordinate spaces don't span separate windows.
//
// .video is deliberately excluded from tearOffPanel(): it already has its
// own detach mechanism (AppState.videoDetached + DetachedVideoWindow) with
// careful mpv-instance lifecycle handling (see that file's header) that this
// generic path knows nothing about. Tearing it off through here too would
// risk two live mpv engines racing to own the same file's playback.

import SwiftUI
import AppKit

/// Reports the NSView backing a SwiftUI view once it's in the hierarchy —
/// used to capture the main window and the dock root's own view for
/// cross-window screen-point hit-testing. Zero-size and invisible; it only
/// exists to answer `view.window`/`view.convert(_:to:)`.
struct ViewAccessor: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension AppState {
    /// Whether a screen point falls inside the main window's frame at all —
    /// the coarse tear-off/merge-back gate before any finer hit-testing.
    func isPointInsideMainWindow(_ screenPoint: CGPoint) -> Bool {
        guard let mainWindow else { return false }
        return mainWindow.frame.contains(screenPoint)
    }

    /// Converts a screen point into the dock root's local SwiftUI coordinate
    /// space (top-left origin, matching the `CGRect(origin: .zero, size:
    /// geo.size)` dockHitTest is already called with for in-window drags) —
    /// nil if the point isn't over the dock root at all.
    func dockLocalPoint(forScreenPoint screenPoint: CGPoint) -> CGPoint? {
        guard let dockRootView, let window = dockRootView.window else { return nil }
        let screenFrame = window.convertToScreen(dockRootView.convert(dockRootView.bounds, to: nil))
        guard screenFrame.contains(screenPoint) else { return nil }
        let windowLocal = window.convertPoint(fromScreen: screenPoint)
        let viewLocal = dockRootView.convert(windowLocal, from: nil)
        // AppKit view-local is bottom-left origin; SwiftUI's local space
        // (what dockHitTest expects) is top-left — flip Y.
        return CGPoint(x: viewLocal.x, y: dockRootView.bounds.height - viewLocal.y)
    }

    /// The dock root's current size, for building the same `rect` in-window
    /// drags use — needed by a torn-off window, which has no GeometryReader
    /// of its own over the main dock.
    var dockRootSize: CGSize { dockRootView?.bounds.size ?? .zero }

    /// Removes `panel` from the dock and opens it as its own floating
    /// window. Refused for the last remaining panel (nothing to return to,
    /// same rule as `AppSettings.togglePanel`) and for `.video` (see file
    /// header) — a no-op in both cases, so the drag just snaps back in place.
    func tearOffPanel(_ panel: PanelKind, openWindow: OpenWindowAction) {
        guard panel != .video, settings.visiblePanels.count > 1,
              let next = removingPanel(panel, from: settings.dockLayout) else { return }
        settings.dockLayout = next
        openWindow(value: panel)
    }

    /// Merges a torn-off panel back into the dock at a specific zone/target —
    /// used by the precise drag-back gesture in TornOffPanelWindow. Also
    /// correct if `panel` somehow isn't in the tree yet (the normal torn-off
    /// case): `movingPanel` degrades to a plain insert when there's nothing
    /// to remove first.
    func mergePanelBack(_ panel: PanelKind, toZone zone: DropZone, ofTarget target: DockTarget) {
        settings.dockLayout = movingPanel(panel, toZone: zone, ofTarget: target, in: settings.dockLayout)
    }

    /// Merges a torn-off panel back at a predictable default spot — used
    /// when its window is simply closed (red button) rather than dragged
    /// back, where there's no drop position to be precise about.
    func mergePanelBackDefault(_ panel: PanelKind) {
        settings.dockLayout = addingPanelAsTab(panel, into: settings.dockLayout)
    }
}
