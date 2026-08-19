// Tab strip for multiple open documents — see DocumentTabs.swift for why this
// sits over one shared DocumentModel rather than one instance per tab.
// Deliberately unstyled-minimal: this is a utility strip, not the app's
// visual centerpiece (that's the cue grid/waveform/video below it).

import SwiftUI
import GlyphlineCore

struct DocumentTabBar: View {
    let state: AppState

    var body: some View {
        // A single-item CHIP strip (nothing to switch between, a close
        // button that would just close your only tab) really is chrome
        // nobody asked for, so that part still only appears once there's
        // something to switch between. But the "+" button is the one and
        // only way to REACH a second tab in the first place — hiding it
        // exactly when you have 1 tab (the moment you'd most want it) meant
        // the only discoverable path to multi-tab was File ▸ New/Open, with
        // this button invisible until you already had 2+ tabs some other
        // way.
        if state.tabs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(state.tabs) { tab in
                        TabChip(
                            title: displayName(tab),
                            isDirty: tab.id == state.activeTabId ? state.document.isDirty : tab.isDirty,
                            isActive: tab.id == state.activeTabId,
                            onSelect: { state.switchToTab(tab.id) },
                            onClose: { state.closeTab(tab.id) }
                        )
                    }
                    newTabButton
                }
            }
            .background(GlyphColor.surface)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .bottom)
        } else {
            HStack(spacing: 1) {
                newTabButton
                Spacer(minLength: 0)
            }
            .background(GlyphColor.surface)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .bottom)
        }
    }

    private var newTabButton: some View {
        Button(action: { state.openNewTab() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GlyphColor.quiet)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(t("newTab"))
    }

    private func displayName(_ tab: DocumentTab) -> String {
        (tab.id == state.activeTabId ? state.document.fileName : tab.fileName) ?? t("untitled")
    }
}

private struct TabChip: View {
    let title: String
    let isDirty: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(GlyphFont.body(11))
                .foregroundStyle(isActive ? GlyphColor.ink : GlyphColor.quiet)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)
            if isDirty {
                Circle().fill(GlyphColor.warn).frame(width: 5, height: 5)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(GlyphColor.quiet)
            }
            .buttonStyle(.plain)
            .opacity(hovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? GlyphColor.bg : Color.clear)
        .overlay(
            Rectangle().frame(height: 2).foregroundStyle(isActive ? GlyphColor.accent : .clear),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}
