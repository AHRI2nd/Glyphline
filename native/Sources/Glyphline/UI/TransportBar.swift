// Transport bar (ported from ../../../src/components/Media/Transport.tsx).

import SwiftUI
import GlyphlineCore

struct TransportBar: View {
    let media: MediaModel
    let document: DocumentModel
    /// Non-nil when new cues should snap to frames (View ▸ 프레임 타임코드).
    var frameRate: Double?

    var body: some View {
        VStack(spacing: 6) {
            Scrubber(media: media)

            HStack(spacing: 10) {
                IconButton(system: "gobackward.5", label: t("skipBack5")) { media.skip(-5) }
                IconButton(system: "chevron.left", label: t("frameBack")) { media.frameStep(forward: false) }
                // No Space accelerator here — it would block typing spaces in cue
                // text (matches Transport.tsx; play/pause is menu-only, ⌘K).
                IconButton(system: media.isPlaying ? "pause.fill" : "play.fill", label: t("playPause")) { media.togglePlay() }
                IconButton(system: "chevron.right", label: t("frameForward")) { media.frameStep(forward: true) }
                IconButton(system: "goforward.5", label: t("skipFwd5")) { media.skip(5) }
                // toggleLoopActiveCue() silently did nothing when clicked
                // with no active cue and no loop already running (the guard
                // in that function just returned) — disabling here instead
                // says so up front rather than leaving the click unexplained.
                // Stays enabled while a loop IS running so it can still be
                // turned off even if the active cue selection changed since.
                IconButton(system: "repeat", label: t("loopActiveCue"), active: media.loopRegion != nil) {
                    media.toggleLoopActiveCue(document: document)
                }
                    .disabled(document.activeCueId == nil && media.loopRegion == nil)

                Text("\(formatDisplayTime(media.currentTime)) / \(formatDisplayTime(media.duration))")
                    .font(GlyphFont.data(11))
                    .foregroundStyle(GlyphColor.quiet)

                Spacer()

                IconButton(system: media.muted || media.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", label: t("mute")) {
                    media.toggleMute()
                }
                Slider(value: Binding(
                    get: { media.muted ? 0 : media.volume },
                    set: { media.setVolume($0) }
                ), in: 0...130)
                .frame(width: 80)
                .tint(GlyphColor.accentHover)

                Picker("", selection: Binding(
                    get: { media.playbackRate },
                    set: { media.setPlaybackRate($0) }
                )) {
                    ForEach(PLAYBACK_RATES, id: \.self) { r in
                        Text("\(r, specifier: "%.2g")×").tag(r)
                    }
                }
                .frame(width: 70)
                .labelsHidden()

                Button(action: addCueAtPlayhead) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text(t("cueHere"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.signal.opacity(0.9))
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlyphColor.surface)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border), alignment: .top)
        .disabled(media.mediaPath == nil)
        .opacity(media.mediaPath == nil ? 0.4 : 1)
    }

    /// Delegates to the shared rule in CueCreation.swift so this button, ⌘Return
    /// and the grid's double-click all place a cue identically.
    private func addCueAtPlayhead() {
        Glyphline.addCueAtPlayhead(document: document, media: media, frameRate: frameRate)
    }
}

private struct Scrubber: View {
    let media: MediaModel
    @State private var dragFraction: Double?
    /// Throttles the actual mpv seek, not the visible thumb — `dragFraction`
    /// still updates on every DragGesture callback (SwiftUI can deliver far
    /// more of those per second than mpv wants absolute-seek commands), so
    /// the bar itself tracks the pointer 1:1 while the video only re-seeks a
    /// bounded number of times per second instead of flooding mpv with a
    /// decode-and-display per pixel of mouse movement.
    @State private var lastSeekAt: Date?
    private let seekInterval: TimeInterval = 0.05

    var body: some View {
        GeometryReader { geo in
            let frac = dragFraction ?? (media.duration > 0 ? media.currentTime / media.duration : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(GlyphColor.border).frame(height: 3)
                Capsule().fill(GlyphColor.accentHover).frame(width: geo.size.width * max(0, min(1, frac)), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard media.duration > 0 else { return }
                        let f = max(0, min(1, value.location.x / geo.size.width))
                        dragFraction = f
                        let now = Date()
                        guard lastSeekAt == nil || now.timeIntervalSince(lastSeekAt!) >= seekInterval else { return }
                        lastSeekAt = now
                        media.seek(f * media.duration)
                    }
                    .onEnded { value in
                        // The throttle above can skip the very last onChanged
                        // before release, which would otherwise leave
                        // playback short of wherever the pointer actually let
                        // go — always land exactly there.
                        if media.duration > 0 {
                            let f = max(0, min(1, value.location.x / geo.size.width))
                            media.seek(f * media.duration)
                        }
                        dragFraction = nil
                        lastSeekAt = nil
                    }
            )
        }
        .frame(height: 12)
    }
}

private struct IconButton: View {
    let system: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12))
                .foregroundStyle(active ? GlyphColor.signal : GlyphColor.ink)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
