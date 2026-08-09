// A small, always-on-top window: play/pause, skip, and the line currently
// under the playhead — for referencing timing while working in another app
// (a dictionary, a script doc, a browser tab) without alt-tabbing back just
// to see what's playing right now or what line is up. Unlike DetachedVideoWindow
// this carries no picture — it's a control surface, not a second view of the
// video, so it stays useful even with only audio loaded.

import SwiftUI
import AppKit
import GlyphlineCore

let MINI_PLAYER_WINDOW_ID = "miniPlayer"

struct MiniPlayerWindow: View {
    let state: AppState
    @Environment(\.panelPresentation) private var presentation

    var body: some View {
        VStack(spacing: 10) {
            Text(currentCueText)
                .font(GlyphFont.body(13))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(currentCueText.isEmpty ? GlyphColor.quiet : GlyphColor.ink)
                .frame(maxWidth: .infinity, minHeight: 44)

            HStack(spacing: 22) {
                MiniButton(system: "gobackward.5") { state.media.skip(-5) }
                MiniButton(system: state.media.isPlaying ? "pause.fill" : "play.fill", big: true) {
                    state.media.togglePlay()
                }
                MiniButton(system: "goforward.5") { state.media.skip(5) }
            }

            Text("\(formatDisplayTime(state.media.currentTime)) / \(formatDisplayTime(state.media.duration))")
                .font(GlyphFont.data(10))
                .foregroundStyle(GlyphColor.quiet)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 280, minHeight: 150)
        .disabled(state.media.mediaPath == nil)
        .opacity(state.media.mediaPath == nil ? 0.4 : 1)
        .background(GlyphColor.bg)
        .background(floatingConfigurator)
        .preferredColorScheme(.dark)
    }

    /// Only applied in the standalone Window scene — `view.window` in a
    /// docked pane resolves to the MAIN app window, and setting THAT to
    /// `.floating`/all-Spaces would misapply "always on top" to the whole
    /// app instead of just this control, so it must be skipped when docked.
    @ViewBuilder
    private var floatingConfigurator: some View {
        if presentation != .pane {
            FloatingWindowConfigurator()
        }
    }

    /// The cue whose span the playhead is currently inside — independent of
    /// `document.activeCueId` (that's the grid's edit selection, not "what's
    /// showing right now"), so this stays in sync purely from playback.
    private var currentCueText: String {
        guard state.media.mediaPath != nil else { return t("miniPlayerNoMedia") }
        let time = state.media.currentTime
        guard let cue = state.document.doc.cues.first(where: { $0.start <= time && time < $0.end }) else {
            return ""
        }
        return cue.text
    }
}

private struct MiniButton: View {
    let system: String
    var big = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: big ? 22 : 15))
                .foregroundStyle(GlyphColor.ink)
                .frame(width: big ? 34 : 26, height: big ? 34 : 26)
        }
        .buttonStyle(.plain)
    }
}

/// Bridges to AppKit once inserted into the view hierarchy to make this
/// window float above every other app's windows and follow the user across
/// Spaces/full-screen apps — SwiftUI's `Window` scene has no direct API for
/// window level, so this reaches into the underlying NSWindow the one way
/// available: an invisible NSView that can see its own `.window`.
private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
