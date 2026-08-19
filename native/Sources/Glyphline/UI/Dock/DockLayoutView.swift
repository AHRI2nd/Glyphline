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

            // A custom Layout, not HStack/VStack — see DockRowLayout's own
            // comment for why plain Stacks aren't safe to use here.
            DockRowLayout(axis: axis, sizes: rowItems.map { $0.size(available: available, weights: weights) }) {
                row(available: available)
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

    /// A flat, one-view-per-row list (panel, divider, panel, divider, panel…).
    private enum RowItem: Identifiable {
        case panel(IdentifiedChild)
        case divider(afterIndex: Int)
        var id: String {
            switch self {
            case .panel(let entry): return entry.id
            case .divider(let i): return "divider-\(i)"
            }
        }
        func size(available: CGFloat, weights: [Double]) -> CGFloat {
            switch self {
            case .panel(let entry): return available * CGFloat(weights[entry.index])
            case .divider: return DOCK_DIVIDER_THICKNESS
            }
        }
    }

    private var rowItems: [RowItem] {
        var items: [RowItem] = []
        for entry in identifiedChildren {
            items.append(.panel(entry))
            if entry.index < children.count - 1 {
                items.append(.divider(afterIndex: entry.index))
            }
        }
        return items
    }

    @ViewBuilder
    private func row(available: CGFloat) -> some View {
        ForEach(rowItems) { item in
            switch item {
            case .panel(let entry):
                let i = entry.index
                DockLayoutView(
                    node: entry.node, path: path + [i], dragState: dragState,
                    content: content, badge: badge, onSelect: onSelect, onWeightsChange: onWeightsChange,
                    onTabDragChanged: onTabDragChanged, onTabDragEnded: onTabDragEnded
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            case .divider(let i):
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

/// Places children edge-to-edge along `axis` at EXACT sizes (`sizes`, same
/// order as the content builder's views) — no HStack/VStack involved.
///
/// Why: HStack/VStack turned out not to be safe here. Root-caused to a real
/// SwiftUI bug (not our math) by reproducing a live bug report's exact
/// nested dock layout (video/waveform one level inside a horizontal split)
/// and pixel-sampling the actual rendered window at each step of isolating
/// it: a `.frame(height:)`-pinned VStack child sometimes silently ignored
/// its own pin and expanded to fill, hiding every sibling after it —
/// reproducible only through a properly BUNDLED app (a real Info.plist,
/// real Sparkle feed config; a bare `swift run`/unbundled debug binary
/// never showed it, and resizing the window afterward did not self-correct
/// it either, so it isn't a one-time launch race that settles out). Rather
/// than depend on exactly which `Color`-vs-`Rectangle`, which position, or
/// which bundle context avoids it — none of which SwiftUI documents or
/// guarantees — this sidesteps the negotiation entirely: every child's
/// placement proposal is the exact pixel size DockLayoutView already
/// computed, the same way `dockHitTest` in DockModel.swift computes its
/// mirror geometry. Layout protocol has been available since macOS 13;
/// this app targets 26.
private struct DockRowLayout: Layout {
    let axis: SplitAxis
    /// Parallel to the content builder's views, one exact main-axis size
    /// per subview — the SAME weight-proportional/DOCK_DIVIDER_THICKNESS
    /// math SplitContainer.body always used, just applied here instead of
    /// via `.frame()`.
    let sizes: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var offset: CGFloat = axis == .horizontal ? bounds.minX : bounds.minY
        for (i, subview) in subviews.enumerated() {
            let size = i < sizes.count ? sizes[i] : 0
            let point = axis == .horizontal ? CGPoint(x: offset, y: bounds.minY) : CGPoint(x: bounds.minX, y: offset)
            let subProposal = axis == .horizontal
                ? ProposedViewSize(width: size, height: bounds.height)
                : ProposedViewSize(width: bounds.width, height: size)
            subview.place(at: point, anchor: .topLeading, proposal: subProposal)
            offset += size
        }
    }
}

/// The visible/layout-contributing strip stays exactly DOCK_DIVIDER_THICKNESS
/// (dockHitTest's tab-drag math depends on that staying in lockstep with what
/// SplitContainer lays out) — but 6pt alone is a thin target to actually land
/// a mouse/trackpad drag on, and a top-bottom split sits right up against
/// whatever native AppKit view (the grid's NSTableView, the waveform's
/// NSScrollView) is directly above/below it, which can end up owning the
/// pointer if the drag doesn't start precisely on that strip. `inset(by:
/// -pad)` on the divider's own contentShape widens the hit area without a
/// second view carrying its own frame/proposal (see row()'s comment above
/// for why that mattered here specifically).
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
            .contentShape(Rectangle().inset(by: -DOCK_DIVIDER_HIT_PAD))
            .onHover { inside in
                hovering = inside
                if inside {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(drag)
    }
}
