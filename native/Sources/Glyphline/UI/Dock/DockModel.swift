// Free-docking layout model (flexlayout-react equivalent). A `DockNode` tree of
// `.split` (horizontal/vertical, weighted children) and `.tabs` (a tab group,
// each tab holding one PanelKind) nodes. Every mutation is a pure function that
// returns a new tree — no in-place mutation, no per-node identity needed, since
// each PanelKind appears exactly once in the whole tree and can be found by
// searching. `path` (child-index chain from root) identifies a specific split
// for weight changes and a specific tabset for tab selection.

import Foundation

enum PanelKind: String, Codable, CaseIterable, Hashable {
    case video, waveform, subtitles

    var titleKey: String {
        switch self {
        case .video: return "panelVideo"
        case .waveform: return "panelWaveform"
        case .subtitles: return "panelSubtitles"
        }
    }
}

enum SplitAxis: String, Codable, Equatable {
    case horizontal, vertical
}

enum DropZone {
    case center, top, bottom, left, right
}

indirect enum DockNode: Codable, Equatable {
    case split(axis: SplitAxis, children: [DockNode], weights: [Double])
    case tabs(panels: [PanelKind], selected: PanelKind)

    /// Matches the Tauri DockLayout's default: video+waveform side by side on
    /// top (each half), cues below — video/waveform : cues ≈ 42 : 58.
    static let defaultLayout = DockNode.split(
        axis: .vertical,
        children: [
            .split(
                axis: .horizontal,
                children: [
                    .tabs(panels: [.video], selected: .video),
                    .tabs(panels: [.waveform], selected: .waveform),
                ],
                weights: [0.5, 0.5]
            ),
            .tabs(panels: [.subtitles], selected: .subtitles),
        ],
        weights: [0.42, 0.58]
    )
}

// ── pure tree operations ────────────────────────────────────────────────────────

/// Removes a panel from wherever it is in the tree. The tabset it was in loses
/// that tab (and is dropped entirely if it becomes empty); a split left with
/// only one surviving child collapses into that child. Returns nil only if the
/// whole tree would become empty (never happens with 3 fixed panels in normal
/// use, but callers should treat nil defensively).
func removingPanel(_ panel: PanelKind, from node: DockNode) -> DockNode? {
    switch node {
    case .tabs(var panels, var selected):
        guard panels.contains(panel) else { return node }
        panels.removeAll { $0 == panel }
        if panels.isEmpty { return nil }
        if selected == panel { selected = panels[0] }
        return .tabs(panels: panels, selected: selected)

    case .split(let axis, let children, let weights):
        var newChildren: [DockNode] = []
        var newWeights: [Double] = []
        for (child, w) in zip(children, weights) {
            if let updated = removingPanel(panel, from: child) {
                newChildren.append(updated)
                newWeights.append(w)
            }
        }
        if newChildren.isEmpty { return nil }
        if newChildren.count == 1 { return newChildren[0] }
        let total = newWeights.reduce(0, +)
        let normalized = total > 0 ? newWeights.map { $0 / total } : newWeights.map { _ in 1.0 / Double(newWeights.count) }
        return .split(axis: axis, children: newChildren, weights: normalized)
    }
}

/// Inserts `panel` relative to `targetPanel`'s location: `.center` merges it in
/// as a new tab in that tabset (selecting it); the edge zones wrap the target's
/// tabset in a new 50/50 split with a fresh single-tab tabset for `panel`.
func insertingPanel(_ panel: PanelKind, dropZone: DropZone, targetPanel: PanelKind, into node: DockNode) -> DockNode {
    switch node {
    case .tabs(var panels, _):
        guard panels.contains(targetPanel) else { return node }
        switch dropZone {
        case .center:
            if !panels.contains(panel) { panels.append(panel) }
            return .tabs(panels: panels, selected: panel)
        case .top, .bottom:
            let fresh = DockNode.tabs(panels: [panel], selected: panel)
            let children = dropZone == .top ? [fresh, node] : [node, fresh]
            return .split(axis: .vertical, children: children, weights: [0.5, 0.5])
        case .left, .right:
            let fresh = DockNode.tabs(panels: [panel], selected: panel)
            let children = dropZone == .left ? [fresh, node] : [node, fresh]
            return .split(axis: .horizontal, children: children, weights: [0.5, 0.5])
        }

    case .split(let axis, let children, let weights):
        return .split(axis: axis, children: children.map { insertingPanel(panel, dropZone: dropZone, targetPanel: targetPanel, into: $0) }, weights: weights)
    }
}

/// Removes `panel` from its current spot and re-inserts it at `zone` relative
/// to `targetPanel`. A no-op if dropped onto itself or its own tabset's center.
func movingPanel(_ panel: PanelKind, toZone zone: DropZone, ofTarget targetPanel: PanelKind, in root: DockNode) -> DockNode {
    guard panel != targetPanel else { return root }
    guard let removed = removingPanel(panel, from: root) else { return root }
    return insertingPanel(panel, dropZone: zone, targetPanel: targetPanel, into: removed)
}

/// Replaces the weights of the split node reached by `path` (child-index chain
/// from root; empty path = root itself).
func updatingWeights(at path: [Int], to weights: [Double], in node: DockNode) -> DockNode {
    guard case .split(let axis, var children, let currentWeights) = node else { return node }
    guard let first = path.first else {
        return .split(axis: axis, children: children, weights: weights)
    }
    guard children.indices.contains(first) else { return node }
    children[first] = updatingWeights(at: Array(path.dropFirst()), to: weights, in: children[first])
    return .split(axis: axis, children: children, weights: currentWeights)
}

/// Sets which tab is selected in the tabset reached by `path`.
func updatingSelection(at path: [Int], to panel: PanelKind, in node: DockNode) -> DockNode {
    guard let first = path.first else {
        guard case .tabs(let panels, _) = node, panels.contains(panel) else { return node }
        return .tabs(panels: panels, selected: panel)
    }
    guard case .split(let axis, var children, let weights) = node, children.indices.contains(first) else { return node }
    children[first] = updatingSelection(at: Array(path.dropFirst()), to: panel, in: children[first])
    return .split(axis: axis, children: children, weights: weights)
}
