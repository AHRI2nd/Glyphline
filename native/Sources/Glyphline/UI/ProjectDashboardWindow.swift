// At-a-glance overview of every open tab — cue count, quality-issue count,
// dirty status — with quick-switch and a save-all shortcut. DocumentTabBar
// already lists tabs by name, but only what fits a thin strip; this is the
// wider view for "which of these five files still needs work" without
// clicking through each one.

import SwiftUI
import GlyphlineCore

let PROJECT_DASHBOARD_WINDOW_ID = "projectDashboard"

struct ProjectDashboardWindow: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            List(state.tabs) { tab in
                DashboardRow(
                    tab: tab, isActive: tab.id == state.activeTabId,
                    liveDoc: tab.id == state.activeTabId ? state.document.doc : nil,
                    liveDirty: tab.id == state.activeTabId ? state.document.isDirty : nil,
                    thresholds: state.settings.quality
                )
                .contentShape(Rectangle())
                .onTapGesture { state.switchToTab(tab.id) }
                .listRowBackground(tab.id == state.activeTabId ? GlyphColor.surface : GlyphColor.bg)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().overlay(GlyphColor.border)
            HStack {
                Text(t("dashboardTabCount", "\(state.tabs.count)"))
                    .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                Spacer()
                Button(t("dashboardSaveAll")) { saveAll() }
                    .controlSize(.small)
                    .disabled(!state.anyTabDirty)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(GlyphColor.surface)
        }
        .frame(minWidth: 420, minHeight: 260)
        .background(GlyphColor.bg)
        .preferredColorScheme(.dark)
    }

    /// Saves every dirty tab in place, switching through them one at a time
    /// (only the active DocumentModel can actually be written — see
    /// DocumentTabs.swift) and returning to whichever tab was active when
    /// this was invoked.
    private func saveAll() {
        let originalTab = state.activeTabId
        for tab in state.tabs {
            let isDirty = tab.id == state.activeTabId ? state.document.isDirty : tab.isDirty
            guard isDirty else { continue }
            if tab.id != state.activeTabId { state.switchToTab(tab.id) }
            state.saveDocument()
        }
        if state.activeTabId != originalTab { state.switchToTab(originalTab) }
    }
}

private struct DashboardRow: View {
    let tab: DocumentTab
    let isActive: Bool
    /// Non-nil only for the active tab — read live rather than from the
    /// (necessarily stale-until-next-switch) snapshot.
    let liveDoc: SubtitleDocument?
    let liveDirty: Bool?
    let thresholds: QualityThresholds

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isDirty ? GlyphColor.warn : Color.clear)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.fileName ?? t("untitled"))
                    .font(GlyphFont.body(12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? GlyphColor.signal : GlyphColor.ink)
                    .lineLimit(1)
                if let path = tab.path {
                    Text(path).font(GlyphFont.data(9)).foregroundStyle(GlyphColor.quiet).lineLimit(1)
                }
            }
            Spacer()
            Text(t("dashboardCueCount", "\(doc.cues.count)"))
                .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
            if issueCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text("\(issueCount)").font(GlyphFont.data(11))
                }
                .foregroundStyle(GlyphColor.amber)
            }
        }
        .padding(.vertical, 4)
    }

    private var doc: SubtitleDocument { liveDoc ?? tab.snapshot }
    private var isDirty: Bool { liveDirty ?? tab.isDirty }

    private var issueCount: Int {
        var count = 0
        var prev: Cue?
        for cue in sortedCues(doc.cues) {
            if hasAnyIssue(evaluateCue(cue, prev: prev, thresholds: thresholds)) { count += 1 }
            prev = cue
        }
        return count
    }
}
