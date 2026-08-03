// A tab group: tab bar (drag a chip to re-dock its panel, click to select) +
// the selected panel's content. Dropping onto a tabset's center merges the
// dragged panel in as a tab; the outer 25% edges split it (flexlayout's
// drag-to-dock affordance).
//
// The drag is a plain DragGesture in the dock's named coordinate space — see
// DockDragState.swift for why the system NSItemProvider drag was abandoned.
// This view is intentionally dumb: the chip gesture just forwards positions
// up via onTabDrag*/; hit-testing and the actual move live at the dock root
// (ContentView), which knows the full tree + dock size.

import SwiftUI

struct TabsetView: View {
    let panels: [PanelKind]
    let selected: PanelKind
    let dragState: DockDragState
    let content: (PanelKind) -> AnyView
    let onSelect: (PanelKind) -> Void
    let onTabDragChanged: (PanelKind, CGPoint) -> Void
    let onTabDragEnded: (PanelKind, CGPoint) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ZStack {
                content(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Each panel lives in exactly one tabset, so "hoverTarget is one
                // of OUR tabs" uniquely identifies this tabset. (Matching any tab
                // — not just `selected` — matters for tear-out drops, whose
                // anchor is a sibling tab rather than the selected one.)
                if let hoverTarget = dragState.hoverTarget, panels.contains(hoverTarget),
                   let zone = dragState.hoverZone {
                    DropZoneIndicator(zone: zone)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(GlyphColor.bg)
        .clipShape(RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius).strokeBorder(GlyphColor.border, lineWidth: 0.5))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(panels, id: \.self) { panel in
                TabChip(panel: panel, isSelected: panel == selected)
                    .onTapGesture { onSelect(panel) }
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(DOCK_COORDINATE_SPACE))
                            .onChanged { value in onTabDragChanged(panel, value.location) }
                            .onEnded { value in onTabDragEnded(panel, value.location) }
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(GlyphColor.surface)
    }
}

/// Name of the coordinate space attached to the dock root (ContentView) —
/// chip drag gestures report locations in this space so dockHitTest can
/// resolve them against the layout tree.
let DOCK_COORDINATE_SPACE = "glyphline.dock"

private struct TabChip: View {
    let panel: PanelKind
    let isSelected: Bool

    var body: some View {
        Text(t(panel.titleKey))
            .font(GlyphFont.display(11, weight: .semibold))
            .foregroundStyle(isSelected ? GlyphColor.ink : GlyphColor.quiet)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? GlyphColor.bg : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
    }
}

/// Translucent overlay previewing where a dropped tab will land — full-pane
/// tint for a center merge, a half-pane band for an edge split.
private struct DropZoneIndicator: View {
    let zone: DropZone

    var body: some View {
        GeometryReader { geo in
            let r = rect(for: zone, in: geo.size)
            RoundedRectangle(cornerRadius: 4)
                .fill(GlyphColor.accent.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(GlyphColor.accentHover, lineWidth: 2))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        }
    }

    private func rect(for zone: DropZone, in size: CGSize) -> CGRect {
        switch zone {
        case .center: return CGRect(x: 0, y: 0, width: size.width, height: size.height)
        case .top: return CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
        case .bottom: return CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
        case .left: return CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
        case .right: return CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
        }
    }
}
