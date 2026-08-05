// Single shared source of truth for an in-progress dock-tab drag.
//
// The drag is a plain SwiftUI DragGesture on the tab chip — NOT an AppKit/
// NSItemProvider drag session. The system drag pipeline was tried first and
// failed in practice on macOS SwiftUI: dropEntered/dropUpdated fired (zone
// previews appeared) but performDrop/dropExited never did, so panels never
// moved and stale previews lingered. Since this drag never leaves the app,
// none of that machinery is needed: the gesture reports cursor positions in
// the dock's coordinate space, `dockHitTest` (DockModel.swift) resolves them
// against the layout tree, and the gesture's onEnded commits the move
// synchronously. Deterministic, no operation negotiation, no async payloads.

import Foundation

@MainActor
@Observable
final class DockDragState {
    /// The panel currently being dragged (nil = no drag in progress).
    var draggingPanel: PanelKind?
    /// Cursor position in the dock area's coordinate space (drives the ghost chip).
    var cursor: CGPoint = .zero
    /// What the drop is measured against (a tabset, or the whole dock for an
    /// outer-edge drop) and the zone within it — drives the single zone preview.
    var hoverTarget: DockTarget?
    var hoverZone: DropZone?

    var isDragging: Bool { draggingPanel != nil }

    func update(panel: PanelKind, cursor: CGPoint, hit: (target: DockTarget, zone: DropZone)?) {
        draggingPanel = panel
        self.cursor = cursor
        hoverTarget = hit?.target
        hoverZone = hit?.zone
    }

    func end() {
        draggingPanel = nil
        hoverTarget = nil
        hoverZone = nil
    }
}
