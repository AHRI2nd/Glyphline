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
import AppKit

struct TabsetView: View {
    let panels: [PanelKind]
    let selected: PanelKind
    let dragState: DockDragState
    let content: (PanelKind) -> AnyView
    /// Optional count shown after a tab's title, e.g. "SUBTITLES 619" — nil
    /// for panels with nothing to count (video/waveform).
    let badge: (PanelKind) -> Int?
    let onSelect: (PanelKind) -> Void
    let onTabDragChanged: (PanelKind, CGPoint) -> Void
    let onTabDragEnded: (PanelKind, CGPoint) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            content(selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GlyphColor.bg)
        .clipShape(RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius).strokeBorder(GlyphColor.border, lineWidth: 0.5))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(panels, id: \.self) { panel in
                // Dimmed while ITS panel is the one being dragged — without this,
                // both the original chip and the cursor-following ghost chip
                // (ContentView) read as two separate, equally "real" tabs, which
                // reads as confusing/duplicated rather than "this one is moving."
                TabChip(panel: panel, isSelected: panel == selected, count: badge(panel))
                    .opacity(dragState.draggingPanel == panel ? 0.35 : 1)
                    .animation(.easeOut(duration: 0.1), value: dragState.draggingPanel == panel)
                    .onTapGesture { onSelect(panel) }
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(DOCK_COORDINATE_SPACE))
                            .onChanged { value in
                                if dragState.draggingPanel == nil { NSCursor.closedHand.push() }
                                onTabDragChanged(panel, value.location)
                            }
                            .onEnded { value in
                                NSCursor.pop()
                                onTabDragEnded(panel, value.location)
                            }
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
    let count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(t(panel.titleKey))
                .textCase(.uppercase)
                .tracking(0.5)
            if let count {
                Text("\(count)")
                    .font(GlyphFont.data(10))
                    .foregroundStyle(isSelected ? GlyphColor.quiet : GlyphColor.quiet.opacity(0.7))
            }
        }
        .font(GlyphFont.display(11, weight: .semibold))
        .foregroundStyle(isSelected ? GlyphColor.ink : GlyphColor.quiet)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected ? GlyphColor.bg : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
    }
}

// The drop preview lives at the dock root (DockDragOverlay) — a tabset can
// only paint within its own bounds, so drawing it here clipped it and put it
// under sibling panes.
