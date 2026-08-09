// Burn the current subtitles into a copy of the loaded video (see
// BurnInEncoder.swift) — a review file a client can watch in QuickTime
// without this app or a subtitle-aware player.

import SwiftUI
import UniformTypeIdentifiers
import GlyphlineCore

struct BurnInPanel: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    private var document: DocumentModel { state.document }
    private var media: MediaModel { state.media }

    private enum Status: Equatable {
        case idle, running(Double?), done(String), failed(String)
    }
    @State private var status: Status = .idle

    var body: some View {
        PanelShell(title: t("burnIn"), width: 420) {
            VStack(alignment: .leading, spacing: 12) {
                if !BurnInEncoder.ffmpegAvailable {
                    Text(t("ffmpegMissing")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.amber)
                } else if media.mediaPath == nil || media.mediaKind != .video {
                    Text(t("burnInNeedsVideo")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.amber)
                } else {
                    Text(t("burnInHint")).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                }

                switch status {
                case .idle: EmptyView()
                case .running(let fraction):
                    VStack(alignment: .leading, spacing: 4) {
                        if let fraction {
                            ProgressView(value: fraction).tint(GlyphColor.accent)
                            Text("\(Int(fraction * 100))%").font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                case .done(let path):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(GlyphColor.good)
                        Text(t("burnInDone", (path as NSString).lastPathComponent))
                            .font(GlyphFont.body(12)).lineLimit(1)
                    }
                case .failed(let message):
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(GlyphColor.warn)
                        Text(message).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet).lineLimit(4)
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("burnInStart")) { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
                .disabled(!canStart)
        }
    }

    private var canStart: Bool {
        guard case .idle = status else {
            if case .failed = status { return true }
            return false
        }
        return BurnInEncoder.ffmpegAvailable && media.mediaPath != nil && media.mediaKind == .video
    }

    private func start() {
        guard let videoPath = media.mediaPath else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        let base = (media.mediaName as NSString?)?.deletingPathExtension ?? "video"
        panel.nameFieldStringValue = "\(base)_burned.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        status = .running(nil)
        let doc = document.doc
        let duration = media.duration
        let jobId = state.startBackgroundJob(t("burnIn") + ": " + (url.path as NSString).lastPathComponent)
        Task {
            do {
                try await BurnInEncoder.encode(
                    videoPath: videoPath, document: doc, outputPath: url.path, durationHint: duration
                ) { fraction in
                    status = .running(fraction)
                    state.updateBackgroundJob(jobId, progress: fraction)
                }
                status = .done(url.path)
                state.finishBackgroundJob(jobId, success: true, message: url.path)
            } catch {
                let message = String(describing: error)
                status = .failed(message)
                state.finishBackgroundJob(jobId, success: false, message: message)
            }
        }
    }
}
