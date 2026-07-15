// Shared chrome for a docked pane: header label + content area on the app's
// zinc dark palette. Mirrors the Tauri app's docked panel structure
// (video/waveform/cues) and its bg-zinc-900/border-zinc-800 look.

import SwiftUI

struct PaneChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(GlyphFont.display(11, weight: .semibold))
                    .foregroundStyle(GlyphColor.quiet)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(GlyphColor.surface)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GlyphColor.bg)
        .clipShape(RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: GlyphMetric.cornerRadius)
                .strokeBorder(GlyphColor.border, lineWidth: 0.5)
        )
    }
}

/// Placeholder body for panes not yet implemented (video=M4, waveform=M4, cue
/// grid=M3). Shows the pane's purpose so the shell is inspectable before those
/// milestones land.
struct PanePlaceholder: View {
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Text(message)
                .font(GlyphFont.body(12))
                .foregroundStyle(GlyphColor.quiet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
