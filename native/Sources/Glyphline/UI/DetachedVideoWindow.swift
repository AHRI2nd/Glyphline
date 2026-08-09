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
            MPVVideoView(media: state.media, document: state.document, settings: state.settings)
                .background(Color.black)
            HStack {
                Text(state.media.mediaName ?? t("untitled"))
                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                    .lineLimit(1)
                Spacer()
                Button(t("redockVideo")) {
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
}

let DETACHED_VIDEO_WINDOW_ID = "detachedVideo"
