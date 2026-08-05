// Free-docking layout model (flexlayout-react equivalent). A `DockNode` tree of
// `.split` (horizontal/vertical, weighted children) and `.tabs` (a tab group,
// each tab holding one PanelKind) nodes. Every mutation is a pure function that
// returns a new tree — no in-place mutation, no per-node identity needed, since
// each PanelKind appears exactly once in the whole tree and can be found by
// searching. `path` (child-index chain from root) identifies a specific split
// for weight changes and a specific tabset for tab selection.

import Foundation
import CoreGraphics

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

/// What a drop is measured against.
///
/// `.panel` splits the tabset holding that panel, so the new pane only spans
/// that tabset. `.root` splits the WHOLE dock, which is the only way to get a
/// pane that runs the full width or height of the window — with tabset-relative
/// drops alone, a bottom pane could never be wider than whatever tabset it was
/// dropped on.
enum DockTarget: Equatable, Hashable {
    case panel(PanelKind)
    case root
}

/// How much of the dock a root-edge drop takes. A full-width strip along an
/// edge is nearly always a secondary pane (a waveform under the video, say),
/// so an even split would waste the main area; tabset-relative drops still use
/// half, where the two panes are peers.
let DOCK_ROOT_SPLIT_FRACTION: Double = 0.3

/// Wraps the entire layout so `panel` occupies one full edge of the dock.
func insertingPanelAtRoot(_ panel: PanelKind, zone: DropZone, into node: DockNode) -> DockNode {
    let fresh = DockNode.tabs(panels: [panel], selected: panel)
    let f = DOCK_ROOT_SPLIT_FRACTION
    switch zone {
    case .center:
        return node // "tab into the whole dock" has no meaning — edges only
    case .top:
        return .split(axis: .vertical, children: [fresh, node], weights: [f, 1 - f])
    case .bottom:
        return .split(axis: .vertical, children: [node, fresh], weights: [1 - f, f])
    case .left:
        return .split(axis: .horizontal, children: [fresh, node], weights: [f, 1 - f])
    case .right:
        return .split(axis: .horizontal, children: [node, fresh], weights: [1 - f, f])
    }
}

/// Removes `panel` from its current spot and re-inserts it at `zone` relative
/// to `target`. A no-op if dropped onto itself or its own tabset's center.
func movingPanel(_ panel: PanelKind, toZone zone: DropZone, ofTarget target: DockTarget, in root: DockNode) -> DockNode {
    if case .panel(let p) = target, panel == p { return root }
    guard let removed = removingPanel(panel, from: root) else { return root }
    switch target {
    case .root:
        return insertingPanelAtRoot(panel, zone: zone, into: removed)
    case .panel(let p):
        return insertingPanel(panel, dropZone: zone, targetPanel: p, into: removed)
    }
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

// ── model-driven hit testing (drives the custom tab drag) ────────────────────────

/// Divider thickness used by BOTH SplitContainer's layout and dockHitTest below.
/// They must agree, or hit-test rectangles drift from what's on screen.
let DOCK_DIVIDER_THICKNESS: CGFloat = 6

/// Which tabset is under `point` (its full tab list + selected panel — every
/// panel appears exactly once in the tree, so either identifies it uniquely),
/// and which drop zone of it. Mirrors SplitContainer's weight-proportional
/// layout exactly, so no view frame registration is needed. `nil` when the
/// point is on a divider or outside `rect`.
/// One resolved drop location.
struct DockHit: Equatable {
    var target: DockTarget
    var zone: DropZone
    /// Tabs of the tabset under the cursor — empty for a root hit. Used by
    /// resolveDockDrop to pick a tear-out anchor.
    var panels: [PanelKind] = []
    var selected: PanelKind?
}

/// Outer band that docks against the WHOLE window rather than the pane under
/// the cursor. Narrow on purpose: it sits on top of the pane's own edge zone,
/// so anything wider would make ordinary pane-relative drops near a window
/// edge hard to hit.
let DOCK_ROOT_EDGE_BAND: CGFloat = 22

/// Top-level hit test. Checks the dock's outer band first — that's the only
/// path that yields a full-width/height pane — then falls through to the
/// tabset the cursor is actually over.
func dockHitTest(_ point: CGPoint, in node: DockNode, rect: CGRect) -> DockHit? {
    guard rect.contains(point) else { return nil }
    if let zone = rootEdgeZone(for: point, in: rect) {
        return DockHit(target: .root, zone: zone)
    }
    guard let hit = tabsetHitTest(point, in: node, rect: rect) else { return nil }
    return DockHit(target: .panel(hit.selected), zone: hit.zone,
                   panels: hit.panels, selected: hit.selected)
}

/// Which outer edge `point` is hugging, or nil when it's in the interior.
/// Corners resolve to whichever edge is nearer, so there's no dead zone.
func rootEdgeZone(for point: CGPoint, in rect: CGRect) -> DropZone? {
    let dLeft = point.x - rect.minX
    let dRight = rect.maxX - point.x
    let dTop = point.y - rect.minY
    let dBottom = rect.maxY - point.y
    let nearest = min(dLeft, dRight, dTop, dBottom)
    guard nearest < DOCK_ROOT_EDGE_BAND else { return nil }
    if nearest == dLeft { return .left }
    if nearest == dRight { return .right }
    if nearest == dTop { return .top }
    return .bottom
}

private func tabsetHitTest(_ point: CGPoint, in node: DockNode, rect: CGRect) -> (panels: [PanelKind], selected: PanelKind, zone: DropZone)? {
    guard rect.contains(point) else { return nil }
    switch node {
    case .tabs(let panels, let selected):
        return (panels, selected, dropZone(for: point, in: rect))
    case .split(let axis, let children, let weights):
        let total = axis == .horizontal ? rect.width : rect.height
        let available = max(1, total - DOCK_DIVIDER_THICKNESS * CGFloat(max(0, children.count - 1)))
        var offset: CGFloat = axis == .horizontal ? rect.minX : rect.minY
        for (child, weight) in zip(children, weights) {
            let length = available * CGFloat(weight)
            let childRect = axis == .horizontal
                ? CGRect(x: offset, y: rect.minY, width: length, height: rect.height)
                : CGRect(x: rect.minX, y: offset, width: rect.width, height: length)
            if childRect.contains(point) {
                return tabsetHitTest(point, in: child, rect: childRect)
            }
            offset += length + DOCK_DIVIDER_THICKNESS
        }
        return nil // on a divider
    }
}

/// Turns a raw hit into an actionable (target, zone) — or nil when the drop
/// would not visibly change the layout, so the CALLER SHOWS NO PREVIEW for it.
/// This is the "what you see is what lands" contract, an exact equivalence:
/// a zone highlight is shown ⇔ releasing performs a move that changes the
/// tree. Without this, dropping a tab a few points inside its own pane's edge
/// showed a convincing preview and then silently did nothing (the self-target
/// no-op guard in movingPanel), as did idempotent drops like dropping a panel
/// onto the edge it already sits against.
///
/// Rules:
/// - Hover over another tabset: anchor = its selected tab.
/// - Own tabset, single tab: every zone is a no-op — it's already there.
/// - Own tabset, multiple tabs, center: no-op (already a tab here).
/// - Own tabset, multiple tabs, edge: TEAR-OUT — split alongside, anchored to
///   a sibling tab that stays behind (flexlayout supports this).
/// - Finally, simulate the move against `root`: if the resulting tree is
///   identical (idempotent drop), suppress.
func resolveDockDrop(
    dragged: PanelKind,
    hit: DockHit?,
    in root: DockNode
) -> (target: DockTarget, zone: DropZone)? {
    guard let hit else { return nil }
    let candidate: (target: DockTarget, zone: DropZone)
    switch hit.target {
    case .root:
        candidate = (.root, hit.zone)
    case .panel:
        guard let selected = hit.selected else { return nil }
        if !hit.panels.contains(dragged) {
            candidate = (.panel(selected), hit.zone)
        } else if hit.panels.count > 1, hit.zone != .center,
                  let anchor = hit.panels.first(where: { $0 != dragged }) {
            candidate = (.panel(anchor), hit.zone)
        } else {
            return nil
        }
    }
    // Same equivalence as before, now covering root drops too: a panel already
    // occupying that whole edge re-docks to an identical tree, so no preview.
    guard movingPanel(dragged, toZone: candidate.zone, ofTarget: candidate.target, in: root) != root else {
        return nil
    }
    return candidate
}

/// Edge zones are a FIXED width/height (up to 25% of the pane, for tiny panes)
/// rather than a proportional 25% of whatever size the pane happens to be —
/// a constant-size hit target is learnable (the same physical distance from
/// an edge always works), where a percentage-based one silently changes size
/// as panes are resized, undermining the muscle memory a user builds up.
func dropZone(for point: CGPoint, in rect: CGRect) -> DropZone {
    guard rect.width > 0, rect.height > 0 else { return .center }
    let marginX = min(80, rect.width * 0.25)
    let marginY = min(80, rect.height * 0.25)
    let x = point.x - rect.minX
    let y = point.y - rect.minY
    if x < marginX { return .left }
    if x > rect.width - marginX { return .right }
    if y < marginY { return .top }
    if y > rect.height - marginY { return .bottom }
    return .center
}

/// The on-screen rect of the tabset containing `panel`, in dock coordinates.
/// Geometry mirrors dockHitTest/SplitContainer exactly — they must stay in
/// lockstep. Lets the dock root draw the drop preview over the whole
/// workspace (correct z-order above every pane) instead of each tabset
/// drawing its own, which buried the preview under sibling panes.
func dockTabsetRect(containing panel: PanelKind, in node: DockNode, rect: CGRect) -> CGRect? {
    switch node {
    case .tabs(let panels, _):
        return panels.contains(panel) ? rect : nil
    case .split(let axis, let children, let weights):
        let total = axis == .horizontal ? rect.width : rect.height
        let available = max(1, total - DOCK_DIVIDER_THICKNESS * CGFloat(max(0, children.count - 1)))
        var offset: CGFloat = axis == .horizontal ? rect.minX : rect.minY
        for (child, weight) in zip(children, weights) {
            let length = available * CGFloat(weight)
            let childRect = axis == .horizontal
                ? CGRect(x: offset, y: rect.minY, width: length, height: rect.height)
                : CGRect(x: rect.minX, y: offset, width: rect.width, height: length)
            if let found = dockTabsetRect(containing: panel, in: child, rect: childRect) { return found }
            offset += length + DOCK_DIVIDER_THICKNESS
        }
        return nil
    }
}

/// Preview rect for a root-edge drop: the full-width/height strip the panel
/// will occupy, sized to match DOCK_ROOT_SPLIT_FRACTION so the highlight is
/// the shape you actually get.
func dockRootZoneRect(_ zone: DropZone, in r: CGRect) -> CGRect {
    let f = CGFloat(DOCK_ROOT_SPLIT_FRACTION)
    switch zone {
    case .center: return r
    case .top: return CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * f)
    case .bottom: return CGRect(x: r.minX, y: r.maxY - r.height * f, width: r.width, height: r.height * f)
    case .left: return CGRect(x: r.minX, y: r.minY, width: r.width * f, height: r.height)
    case .right: return CGRect(x: r.maxX - r.width * f, y: r.minY, width: r.width * f, height: r.height)
    }
}

/// Where a drop lands inside its target pane — the region that will be
/// occupied after the move. `.center` takes the whole pane (it becomes a tab
/// there); edges take the half they'll split off.
func dockZoneRect(_ zone: DropZone, in r: CGRect) -> CGRect {
    switch zone {
    case .center: return r
    case .top: return CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2)
    case .bottom: return CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2)
    case .left: return CGRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height)
    case .right: return CGRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height)
    }
}

/// A stable identity for a subtree, independent of its position among
/// siblings — the exact set of panels it (recursively) contains, since every
/// PanelKind appears exactly once in the whole tree. Used as SwiftUI ForEach
/// ids in SplitContainer so a tab move/split animates as an insert+remove of
/// the moved subtree instead of every sibling silently reindexing (which is
/// what `.offset`-based ids would do, producing a jarring cross-fade of
/// unrelated panels instead of the one that actually moved).
func dockNodeID(_ node: DockNode) -> String {
    switch node {
    case .tabs(let panels, _):
        return panels.map(\.rawValue).sorted().joined(separator: ",")
    case .split(_, let children, _):
        return children.map(dockNodeID).joined(separator: "|")
    }
}
