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

/// A dialog-opening action offered from an empty-state pane (e.g. "Open Media").
/// `prominent` picks the one action that's the obvious next step — at most one
/// per placeholder should be prominent, matching the app's other panels where
/// exactly one confirming button gets `.borderedProminent`.
struct PlaceholderAction: Identifiable {
    let id = UUID()
    let label: String
    var prominent: Bool = false
    let action: () -> Void
}

/// Empty-state body for a docked pane with nothing to show yet (no media
/// loaded, no cues in the document, mpv missing). All three panes share this
/// one view so their empty states can't drift into different wording,
/// spacing, or punctuation the way the three ad-hoc placeholders they replaced
/// had (one hardcoded the English "File" menu name inside a Korean string,
/// one had no call to action at all).
///
/// Shape is icon → short title → one-line explanation → the action(s) that
/// actually resolve the empty state, so "무엇이 없는지" and "무엇을 해야 하는지"
/// are always both on screen, not just implied by a menu hint.
struct PanePlaceholder: View {
    let icon: String
    let title: String
    var subtitle: String?
    var actions: [PlaceholderAction] = []

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(GlyphColor.quiet.opacity(0.55))
            Text(title)
                .font(GlyphFont.body(13, weight: .medium))
                .foregroundStyle(GlyphColor.quiet)
            if let subtitle {
                Text(subtitle)
                    .font(GlyphFont.body(11))
                    .foregroundStyle(GlyphColor.quiet.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { item in
                        if item.prominent {
                            Button(item.label, action: item.action)
                                .buttonStyle(.borderedProminent)
                                .tint(GlyphColor.accent)
                                .controlSize(.small)
                        } else {
                            Button(item.label, action: item.action)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
