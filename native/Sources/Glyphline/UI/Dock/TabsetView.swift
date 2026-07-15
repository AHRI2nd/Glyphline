// A tab group: tab bar (draggable tabs, click to select) + the selected panel's
// content. The content area is itself a drop target — dropping a tab onto its
// center merges it in as a new tab; dropping onto an edge (25% margin) splits
// this tabset and inserts the dropped panel alongside it (mirrors flexlayout's
// drag-to-dock affordance). Drag payload is the raw PanelKind string — simplest
// robust representation for an in-process-only drag.

import SwiftUI

struct TabsetView: View {
    let panels: [PanelKind]
    let selected: PanelKind
    let content: (PanelKind) -> AnyView
    let onSelect: (PanelKind) -> Void
    let onMove: (PanelKind, DropZone, PanelKind) -> Void

    @State private var hoverZone: DropZone?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ZStack {
                content(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isDropTargeted, let hoverZone {
                    DropZoneIndicator(zone: hoverZone)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverZone = Self.zone(for: location, in: geo.size)
                            case .ended:
                                break
                            }
                        }
                }
            )
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let dragged = PanelKind(rawValue: raw),
                      let zone = hoverZone, let target = selected as PanelKind? else { return false }
                onMove(dragged, zone, target)
                isDropTargeted = false
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
                if !targeted { hoverZone = nil }
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
                    .draggable(panel.rawValue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(GlyphColor.surface)
    }

    private static func zone(for location: CGPoint, in size: CGSize) -> DropZone {
        guard size.width > 0, size.height > 0 else { return .center }
        let margin: CGFloat = 0.25
        let nx = location.x / size.width
        let ny = location.y / size.height
        if nx < margin { return .left }
        if nx > 1 - margin { return .right }
        if ny < margin { return .top }
        if ny > 1 - margin { return .bottom }
        return .center
    }
}

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
