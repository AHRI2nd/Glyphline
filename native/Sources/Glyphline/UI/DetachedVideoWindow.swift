// The video panel as its own OS window — for a second-monitor layout (video
// on one screen, grid/waveform on the other), which the single-window dock
// can't offer. Reuses MPVVideoView exactly as the docked panel does; nothing
// mpv-specific changes here, since the render-API surface (MPVSurfaceView) is
// a plain, ordinary NSOpenGLView with no attachment to any particular parent
// window — it's just as embeddable in this window as in the dock's.
//
// Exactly one MPVSurfaceView exists at a time: the dock's video slot shows a
// placeholder instead of MPVVideoView while this window is open (see
// ContentView's `.video` case), so there's never two independent mpv
// instances racing to own the same file's playback.

import SwiftUI
import GlyphlineCore

struct DetachedVideoWindow: View {
    let state: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            videoArea
                .background(Color.black)
            HStack {
                Text(state.media.mediaName ?? t("untitled"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .lineLimit(1)
                Spacer()
                Button(t("redockVideo")) {
                    // The dock's own placeholder assumes .video is still in
                    // dockLayout (it's rendering that pane's placeholder
                    // right now, after all) — but this window's OWN button
                    // has no such guarantee: View ▸ Panels ▸ Video can
                    // remove .video from the dock entirely while this window
                    // is open, and without this check, redocking would just
                    // close the window with nowhere left for the video to
                    // reappear.
                    if !state.settings.visiblePanels.contains(.video) {
                        state.settings.togglePanel(.video)
                    }
                    state.videoDetached = false
                    dismissWindow(id: DETACHED_VIDEO_WINDOW_ID)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(GlyphColor.surface)
        }
        .frame(minWidth: 320, minHeight: 220)
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
        // Covers BOTH ways this window can close: the red button (AppKit
        // closes it directly, no app code runs first) and our own re-dock
        // button above (which already resets the flag itself, so this is a
        // harmless repeat of the same assignment in that case). Either way,
        // the dock's video slot needs to know to show the real view again.
        .onDisappear { state.videoDetached = false }
    }

    /// Mirrors ContentView's docked `.video` case (minus the "detached
    /// elsewhere" branch, which can't apply to the detached window itself) —
    /// MPVVideoView is a bare NSOpenGLView wrapper with no empty-state
    /// handling of its own, so this window rendered as a plain black
    /// rectangle whenever nothing was loaded, only audio was loaded, or mpv
    /// itself wasn't installed. The docked panel already explains all three;
    /// this window just never repeated that explanation.
    @ViewBuilder
    private var videoArea: some View {
        if state.media.mediaPath != nil, state.media.mediaKind == .video {
            MPVVideoView(media: state.media, document: state.document, settings: state.settings)
        } else if state.media.mediaKind == .audio {
            PanePlaceholder(icon: "music.note", title: t("audioLoadedTitle"), subtitle: state.media.mediaName)
        } else if MPVLibrary.isAvailable {
            PanePlaceholder(
                icon: "film", title: t("noMediaShort"), subtitle: t("noMediaDesc"),
                actions: [PlaceholderAction(label: t("openMedia"), prominent: true) { state.openMediaPicker() }]
            )
        } else {
            PanePlaceholder(
                icon: "exclamationmark.triangle", title: t("mpvMissing"), subtitle: t("mpvMissingDesc"),
                actions: [PlaceholderAction(label: menuLabel("settings")) { state.activePanel = .settings }]
            )
        }
    }
}

let DETACHED_VIDEO_WINDOW_ID = "detachedVideo"
