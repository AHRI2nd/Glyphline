// The drop preview, drawn once at the dock root above every pane.
//
// Design: focus choreography, the convention professional docking UIs
// converged on (VS Code, Figma, Blender, Premiere). Picking up a tab drops the
// whole workspace into a dimmed state and lights ONLY the destination, so the
// preview reads as figure against ground instead of competing with panel
// content. Three layers, each answering a different question:
//
//   scrim   → "you are placing something" (everything else recedes)
//   outline → "into THIS pane"
//   zone    → "in THIS part of it", labeled with the literal outcome
//
// Drawn here rather than inside each TabsetView because a tabset can only
// paint within its own bounds — the preview would be clipped by, and z-ordered
// under, sibling panes. dockTabsetRect (DockModel) recomputes the target's
// geometry from the same math SplitContainer lays out with.

import SwiftUI

struct DockDragOverlay: View {
    let dragState: DockDragState
    let layout: DockNode
    let dockSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var targetRect: CGRect? {
        guard let target = dragState.hoverTarget else { return nil }
        switch target {
        case .root:
            return CGRect(origin: .zero, size: dockSize)
        case .panel(let panel):
            return dockTabsetRect(containing: panel, in: layout, rect: CGRect(origin: .zero, size: dockSize))
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.45))

            if let targetRect, let zone = dragState.hoverZone {
                RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius)
                    .strokeBorder(GlyphColor.signal.opacity(0.5), lineWidth: 1)
                    .frame(width: targetRect.width, height: targetRect.height)
                    .offset(x: targetRect.minX, y: targetRect.minY)

                // A root drop spans a whole edge, so its highlight uses the
                // root fraction rather than the half a pane-relative split takes.
                let isRoot = dragState.hoverTarget == .root
                let zr = (isRoot ? dockRootZoneRect(zone, in: targetRect)
                                 : dockZoneRect(zone, in: targetRect)).insetBy(dx: 5, dy: 5)
                RoundedRectangle(cornerRadius: 6)
                    .fill(GlyphColor.accent.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(GlyphColor.accentHover, lineWidth: 2))
                    .overlay(OutcomeLabel(zone: zone, isRoot: isRoot))
                    .frame(width: zr.width, height: zr.height)
                    .offset(x: zr.minX, y: zr.minY)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: dragState.hoverZone)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: dragState.hoverTarget)
    }
}

/// Names the result in plain language, paired with a glyph that diagrams the
/// resulting layout. The glyph carries the part that's genuinely ambiguous —
/// tab-merge vs. split — while the highlight's position already says which
/// side, so the two signals layer instead of repeating each other.
private struct OutcomeLabel: View {
    let zone: DropZone
    /// Root drops span a full window edge — a materially different outcome
    /// from splitting the pane under the cursor, so it gets its own wording
    /// rather than reusing "split left/right/top/bottom".
    let isRoot: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(t(labelKey))
        }
        .font(GlyphFont.display(11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(GlyphColor.accent, in: Capsule())
        .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
    }

    private var icon: String {
        if isRoot {
            return zone == .left || zone == .right
                ? "rectangle.lefthalf.inset.filled" : "rectangle.bottomhalf.inset.filled"
        }
        switch zone {
        case .center: return "rectangle.stack"
        case .left, .right: return "rectangle.split.2x1"
        case .top, .bottom: return "rectangle.split.1x2"
        }
    }

    private var labelKey: String {
        if isRoot {
            switch zone {
            case .left: return "dockDockLeftFull"
            case .right: return "dockDockRightFull"
            case .top: return "dockDockTopFull"
            case .bottom, .center: return "dockDockBottomFull"
            }
        }
        switch zone {
        case .center: return "dockMergeAsTab"
        case .left: return "dockSplitLeft"
        case .right: return "dockSplitRight"
        case .top: return "dockSplitTop"
        case .bottom: return "dockSplitBottom"
        }
    }
}
