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
    let onSelect: (PanelKind, [Int]) -> Void
    let onWeightsChange: ([Int], [Double]) -> Void
    let onTabDragChanged: (PanelKind, CGPoint) -> Void
    let onTabDragEnded: (PanelKind, CGPoint) -> Void

    var body: some View {
        switch node {
        case .split(let axis, let children, let weights):
            SplitContainer(
                axis: axis, children: children, weights: weights, path: path, dragState: dragState,
                content: content, onSelect: onSelect, onWeightsChange: onWeightsChange,
                onTabDragChanged: onTabDragChanged, onTabDragEnded: onTabDragEnded
            )
        case .tabs(let panels, let selected):
            TabsetView(
                panels: panels, selected: selected, dragState: dragState,
                content: content,
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

    @ViewBuilder
    private func row(available: CGFloat) -> some View {
        ForEach(Array(children.enumerated()), id: \.offset) { i, child in
            DockLayoutView(
                node: child, path: path + [i], dragState: dragState,
                content: content, onSelect: onSelect, onWeightsChange: onWeightsChange,
                onTabDragChanged: onTabDragChanged, onTabDragEnded: onTabDragEnded
            )
            .frame(
                width: axis == .horizontal ? available * CGFloat(weights[i]) : nil,
                height: axis == .vertical ? available * CGFloat(weights[i]) : nil
            )

            if i < children.count - 1 {
                DividerHandle(axis: axis)
                    .frame(
                        width: axis == .horizontal ? DOCK_DIVIDER_THICKNESS : nil,
                        height: axis == .vertical ? DOCK_DIVIDER_THICKNESS : nil
                    )
                    .gesture(
                        // Translation MUST be measured in the stable dock space,
                        // not .local: the divider itself moves as weights change,
                        // so a .local translation loses exactly the distance the
                        // divider traveled — settling at cursorΔ/2 (the divider
                        // visibly lagging the cursor at half speed).
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(DOCK_COORDINATE_SPACE))
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
                    )
            }
        }
    }
}

private struct DividerHandle: View {
    let axis: SplitAxis
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? GlyphColor.accent.opacity(0.6) : GlyphColor.border)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
