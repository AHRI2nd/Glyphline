// Recursive renderer for a DockNode tree. `path` (child-index chain from root)
// is threaded down so weight/selection callbacks can address the exact node
// that changed without needing per-node identity — see DockModel.swift.
// Tab-drag positions are forwarded up (onTabDragChanged/Ended) to the dock
// root, which owns hit-testing — see DockDragState.swift.

import SwiftUI
import AppKit

struct DockLayoutView: View {
    let node: DockNode
    var path: [Int] = []
    let dragState: DockDragState
    let content: (PanelKind) -> AnyView
    var badge: (PanelKind) -> Int? = { _ in nil }
    let onSelect: (PanelKind, [Int]) -> Void
    let onWeightsChange: ([Int], [Double]) -> Void
    let onTabDragChanged: (PanelKind, CGPoint) -> Void
    let onTabDragEnded: (PanelKind, CGPoint) -> Void

    var body: some View {
        switch node {
        case .split(let axis, let children, let weights):
            SplitContainer(
                axis: axis, children: children, weights: weights, path: path, dragState: dragState,
                content: content, badge: badge, onSelect: onSelect, onWeightsChange: onWeightsChange,
                onTabDragChanged: onTabDragChanged, onTabDragEnded: onTabDragEnded
            )
        case .tabs(let panels, let selected):
            TabsetView(
                panels: panels, selected: selected, dragState: dragState,
                content: content, badge: badge,
                onSelect: { onSelect($0, path) },
                onTabDragChanged: onTabDragChanged,
                onTabDragEnded: onTabDragEnded
            )
        }
    }
}

/// One level of split: lays out children along `axis` proportional to `weights`,
/// with a draggable divider between each pair that redistributes weight between
/// just that adjacent pair (matches flexlayout/VSplitView-style resizing).
/// Layout math (weight-proportional lengths + DOCK_DIVIDER_THICKNESS gaps) must
/// stay in lockstep with dockHitTest in DockModel.swift.
struct SplitContainer: View {
    let axis: SplitAxis
    let children: [DockNode]
    let weights: [Double]
    let path: [Int]
    let dragState: DockDragState
    let content: (PanelKind) -> AnyView
    let badge: (PanelKind) -> Int?
    let onSelect: (PanelKind, [Int]) -> Void
    let onWeightsChange: ([Int], [Double]) -> Void
    let onTabDragChanged: (PanelKind, CGPoint) -> Void
    let onTabDragEnded: (PanelKind, CGPoint) -> Void

    @State private var dragStartWeights: [Double]?

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let available = max(1, total - DOCK_DIVIDER_THICKNESS * CGFloat(max(0, children.count - 1)))

            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) { row(available: available) }
                } else {
                    VStack(spacing: 0) { row(available: available) }
                }
            }
        }
    }

    /// Identity is the set of panels a subtree contains, not its sibling index
    /// — a tab move/split then reads as one subtree inserting and another
    /// removing, which SwiftUI can animate cleanly. Offset-based ids would
    /// instead make every LATER sibling "change identity" on any insertion,
    /// producing a jarring cross-fade across unrelated panels.
    private struct IdentifiedChild: Identifiable {
        let id: String
        let index: Int
        let node: DockNode
    }

    private var identifiedChildren: [IdentifiedChild] {
        children.enumerated().map { IdentifiedChild(id: dockNodeID($1), index: $0, node: $1) }
    }

    @ViewBuilder
    private func row(available: CGFloat) -> some View {
        ForEach(identifiedChildren) { entry in
            let i = entry.index
            DockLayoutView(
                node: entry.node, path: path + [i], dragState: dragState,
                content: content, badge: badge, onSelect: onSelect, onWeightsChange: onWeightsChange,
                onTabDragChanged: onTabDragChanged, onTabDragEnded: onTabDragEnded
            )
            .frame(
                width: axis == .horizontal ? available * CGFloat(weights[i]) : nil,
                height: axis == .vertical ? available * CGFloat(weights[i]) : nil
            )
            .transition(.opacity.combined(with: .scale(scale: 0.94)))

            if i < children.count - 1 {
                let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named(DOCK_COORDINATE_SPACE))
                    // Translation MUST be measured in the stable dock space,
                    // not .local: the divider itself moves as weights change,
                    // so a .local translation loses exactly the distance the
                    // divider traveled — settling at cursorΔ/2 (the divider
                    // visibly lagging the cursor at half speed).
                    .onChanged { value in
                        if dragStartWeights == nil { dragStartWeights = weights }
                        guard let start = dragStartWeights, i + 1 < start.count else { return }
                        let delta = axis == .horizontal ? value.translation.width : value.translation.height
                        let deltaFrac = Double(delta / available)
                        var next = start
                        let pairTotal = start[i] + start[i + 1]
                        next[i] = min(max(0.08, start[i] + deltaFrac), pairTotal - 0.08)
                        next[i + 1] = pairTotal - next[i]
                        onWeightsChange(path, next)
                    }
                    .onEnded { _ in dragStartWeights = nil }

                DockDivider(axis: axis, drag: drag)
            }
        }
    }
}

/// The visible/layout-contributing strip stays exactly DOCK_DIVIDER_THICKNESS
/// (dockHitTest's tab-drag math depends on that staying in lockstep with what
/// SplitContainer lays out) — but 6pt alone is a thin target to actually land
/// a mouse/trackpad drag on, and a top-bottom split sits right up against
/// whatever native AppKit view (the grid's NSTableView, the waveform's
/// NSScrollView) is directly above/below it, which can end up owning the
/// pointer if the drag doesn't start precisely on that strip. Hover, cursor,
/// AND the drag gesture all live on one invisible overlay several points
/// wider on each side than the visible line — same trick every pro app's
/// splitters use (thin visual line, fatter grab area) — layered on top of,
/// not split across, the visible Rectangle: driving them from two separate
/// onHover handlers (one on the thin strip, one on the wider overlay) would
/// double up NSCursor's push/pop stack the moment the pointer crosses from
/// the wide area into the thin one.
private struct DockDivider<DragGestureType: Gesture>: View {
    let axis: SplitAxis
    let drag: DragGestureType
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? GlyphColor.accent.opacity(0.6) : GlyphColor.border)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .frame(
                width: axis == .horizontal ? DOCK_DIVIDER_THICKNESS : nil,
                height: axis == .vertical ? DOCK_DIVIDER_THICKNESS : nil
            )
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .frame(
                        width: axis == .horizontal ? DOCK_DIVIDER_THICKNESS + DOCK_DIVIDER_HIT_PAD * 2 : nil,
                        height: axis == .vertical ? DOCK_DIVIDER_THICKNESS + DOCK_DIVIDER_HIT_PAD * 2 : nil
                    )
                    .onHover { inside in
                        hovering = inside
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(drag)
            )
    }
}
