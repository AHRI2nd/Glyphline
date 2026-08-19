// Persistent view of long-running background operations — burn-in encoding,
// batch conversion, shot-change detection. These already ran as fire-and-
// forget Tasks before this window existed; what was missing was anywhere to
// check on one after closing the panel that started it (the Task keeps
// running, but its progress lived in that panel's local @State, which is
// torn down with the sheet). This reads AppState.backgroundJobs — state that
// outlives any one panel — plus MediaModel.sceneCutStatus directly, since
// scene-cut detection already lives on the app-lifetime MediaModel and
// doesn't need a second, duplicate tracking mechanism.

import SwiftUI
import GlyphlineCore

let ACTIVITY_WINDOW_ID = "activity"

struct ActivityWindow: View {
    let state: AppState
    /// This view doubles as docked panel content (ContentView's
    /// dockPanelContent sets .panelPresentation to .pane there) — the
    /// open-state tracking below must only fire for the standalone Window,
    /// or simply having the panel docked would read as "the window is open."
    @Environment(\.panelPresentation) private var presentation

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(GlyphColor.quiet)
                    Text(t("activityEmpty")).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    ActivityRow(row: row)
                        .listRowBackground(GlyphColor.bg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider().overlay(GlyphColor.border)
            HStack {
                Spacer()
                Button(t("activityClearFinished")) { state.clearFinishedBackgroundJobs() }
                    .controlSize(.small)
                    .disabled(!hasFinished)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(GlyphColor.surface)
        }
        .frame(minWidth: 380, minHeight: 260)
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
        .onAppear { if presentation != .pane { state.activityWindowOpen = true } }
        .onDisappear { if presentation != .pane { state.activityWindowOpen = false } }
    }

    private var hasFinished: Bool {
        state.backgroundJobs.contains { if case .running = $0.status { return false }; return true }
    }

    /// Background jobs plus a synthetic row for scene-cut detection when it
    /// has ever been run for the current media — kept out of the generic
    /// array since MediaModel already owns that state as the single source
    /// of truth WaveformPane reads from.
    private var rows: [ActivityRow.Data] {
        var out = state.backgroundJobs.map {
            ActivityRow.Data(id: $0.id, title: $0.title, status: $0.status, startedAt: $0.startedAt)
        }
        switch state.media.sceneCutStatus {
        case .idle:
            break
        case .detecting:
            out.append(ActivityRow.Data(
                id: sceneCutRowId, title: t("detectSceneCuts") + ": " + (state.media.mediaName ?? ""),
                status: .running(progress: nil), startedAt: Date()))
        case .ready:
            out.append(ActivityRow.Data(
                id: sceneCutRowId, title: t("detectSceneCuts") + ": " + (state.media.mediaName ?? ""),
                status: .succeeded(t("sceneCutCount", "\(state.media.sceneCuts.count)")), startedAt: Date()))
        case .failed(let message):
            out.append(ActivityRow.Data(
                id: sceneCutRowId, title: t("detectSceneCuts") + ": " + (state.media.mediaName ?? ""),
                status: .failed(message), startedAt: Date()))
        }
        return out
    }

    private let sceneCutRowId = UUID(uuidString: "00000000-0000-0000-0000-00000000c07") ?? UUID()
}

private struct ActivityRow: View {
    struct Data: Identifiable {
        let id: UUID
        let title: String
        let status: BackgroundJob.Status
        let startedAt: Date
    }
    let row: Data

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(GlyphFont.body(12)).lineLimit(1)
                switch row.status {
                case .running(let fraction):
                    if let fraction {
                        ProgressView(value: fraction).tint(GlyphColor.accent)
                    }
                case .succeeded(let message):
                    if let message {
                        Text(message).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet).lineLimit(2)
                    }
                case .failed(let message):
                    Text(message).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet).lineLimit(2)
                }
            }
            Spacer()
            Text(row.startedAt, style: .time)
                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var icon: some View {
        switch row.status {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(GlyphColor.good)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(GlyphColor.warn)
        }
    }
}
