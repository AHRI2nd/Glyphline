// Recursive renderer for a DockNode tree. `path` (child-index chain from root)
// is threaded down so weight/selection callbacks can address the exact node
// that changed without needing per-node identity — see DockModel.swift.

import SwiftUI
import AppKit

struct DockLayoutView: View {
    let node: DockNode
    var path: [Int] = []
    let content: (PanelKind) -> AnyView
    let onMove: (PanelKind, DropZone, PanelKind) -> Void
    let onSelect: (PanelKind, [Int]) -> Void
    let onWeightsChange: ([Int], [Double]) -> Void

    var body: some View {
        switch node {
        case .split(let axis, let children, let weights):
            SplitContainer(
                axis: axis, children: children, weights: weights, path: path,
                content: content, onMove: onMove, onSelect: onSelect, onWeightsChange: onWeightsChange
            )
        case .tabs(let panels, let selected):
            TabsetView(
                panels: panels, selected: selected,
                content: content,
                onSelect: { onSelect($0, path) },
                onMove: onMove
            )
        }
    }
}

/// One level of split: lays out children along `axis` proportional to `weights`,
/// with a draggable divider between each pair that redistributes weight between
/// just that adjacent pair (matches flexlayout/VSplitView-style resizing).
struct SplitContainer: View {
    let axis: SplitAxis
    let children: [DockNode]
    let weights: [Double]
    let path: [Int]
    let content: (PanelKind) -> AnyView
    let onMove: (PanelKind, DropZone, PanelKind) -> Void
    let onSelect: (PanelKind, [Int]) -> Void
    let onWeightsChange: ([Int], [Double]) -> Void

    @State private var dragStartWeights: [Double]?
    private let dividerThickness: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let available = max(1, total - dividerThickness * CGFloat(max(0, children.count - 1)))

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
                node: child, path: path + [i],
                content: content, onMove: onMove, onSelect: onSelect, onWeightsChange: onWeightsChange
            )
            .frame(
                width: axis == .horizontal ? available * CGFloat(weights[i]) : nil,
                height: axis == .vertical ? available * CGFloat(weights[i]) : nil
            )

            if i < children.count - 1 {
                DividerHandle(axis: axis)
                    .frame(
                        width: axis == .horizontal ? dividerThickness : nil,
                        height: axis == .vertical ? dividerThickness : nil
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
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
