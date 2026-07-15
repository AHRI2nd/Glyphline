// SwiftUI wrapper for MPVSurfaceView. Owns the surface's lifecycle and wires it
// to MediaModel (engine reference + poll callback) and to the document (debounced
// ASS subtitle push on cue edits) — the native equivalent of VideoPlayer.tsx.

import SwiftUI
import GlyphlineCore

struct MPVVideoView: NSViewRepresentable {
    let media: MediaModel
    let document: DocumentModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        guard let surface = MPVSurfaceView(mpvFrame: .zero) else {
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.black.cgColor
            return fallback
        }
        surface.onPoll = { [weak media] time, duration, paused in
            DispatchQueue.main.async { media?.applyPolled(time: time, duration: duration, paused: paused) }
        }
        media.engine = surface
        context.coordinator.surface = surface
        return surface
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Open new media when the path changes.
        if media.mediaPath != context.coordinator.lastPath {
            context.coordinator.lastPath = media.mediaPath
            if let path = media.mediaPath { media.engine?.open(path: path) }
        }
        // Debounced subtitle push on cue-timing/text changes.
        let sig = subtitleSignature(document.doc.cues)
        if sig != context.coordinator.lastSubSignature {
            context.coordinator.lastSubSignature = sig
            context.coordinator.scheduleSubtitlePush(document: document, media: media)
        }
    }

    private func subtitleSignature(_ cues: [Cue]) -> String {
        cues.map { "\($0.id):\(String(format: "%.3f", $0.start)):\(String(format: "%.3f", $0.end)):\($0.text)" }
            .joined(separator: "\n")
    }

    @MainActor
    final class Coordinator {
        weak var surface: MPVSurfaceView?
        var lastPath: String?
        var lastSubSignature: String?
        private var pushTask: Task<Void, Never>?

        func scheduleSubtitlePush(document: DocumentModel, media: MediaModel) {
            pushTask?.cancel()
            let doc = document.doc
            pushTask = Task { [weak media] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let media else { return }
                let ass = serializeAss(withDefaultStyleIfNeeded(doc))
                media.pushSubtitles(ass)
            }
        }
    }
}

/// mpv needs a complete ASS script including at least one style; documents
/// loaded from styleless formats (SRT/VTT/…) have no `styles`, so synthesize a
/// minimal default rather than emitting an invalid script.
private func withDefaultStyleIfNeeded(_ doc: SubtitleDocument) -> SubtitleDocument {
    guard doc.styles?.isEmpty ?? true else { return doc }
    var d = doc
    d.styles = [AssStyle(name: "Default")]
    return d
}
