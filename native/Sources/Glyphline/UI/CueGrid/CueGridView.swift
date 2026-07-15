// The cue grid — NSTableView wrapped for SwiftUI (NSViewRepresentable). This is
// the M3 "핵심 편집 표면": virtualized rows (NSTableView only materializes visible
// cells, so this scales to thousands of cues for free — the performance worry
// flagged in the Tauri build's CueList.tsx is structurally gone here), inline
// editing, multi/range selection, keyboard navigation, and a right-click menu.
//
// Columns: flag (quality dot) · # · Start · End · Dur/CPS · Style · Actor · Text ·
// Translation. Start/End/Style/Actor/Text/Translation are editable in place.

import AppKit
import SwiftUI
import GlyphlineCore

struct CueGridView: NSViewRepresentable {
    let document: DocumentModel
    let media: MediaModel
    let settings: AppSettings
    var onEditTags: ((Cue) -> Void)?

    func makeCoordinator() -> CueGridCoordinator {
        let coordinator = CueGridCoordinator(document: document)
        // Jump the playhead to a cue's start when it becomes active (click or
        // arrow-key navigation) — mirrors CueRow.tsx's onClick seek behavior.
        coordinator.onRowActivated = { [weak media] cue in
            guard let media, media.mediaPath != nil else { return }
            media.seek(cue.start)
        }
        // I/O/P live timing needs the current playhead; nil until media loads.
        coordinator.playheadProvider = { [weak media] in
            guard let media, media.mediaPath != nil else { return nil }
            return media.currentTime
        }
        // Context menu "Play from Here" (ported from ContextMenu ctxPlayHere).
        coordinator.onPlayHere = { [weak media] cue in
            guard let media, media.mediaPath != nil else { return }
            media.seek(cue.start)
        }
        coordinator.mediaAvailable = { [weak media] in media?.mediaPath != nil }
        coordinator.onEditTags = onEditTags
        return coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = CueTableView()
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.rowHeight = 26
        table.headerView = NSTableHeaderView()
        table.style = .plain
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.menu = context.coordinator.makeContextMenu()

        syncColumns(table, settings: settings)

        table.onTimingKey = { [weak coordinator = context.coordinator] key in
            coordinator?.handleTimingKey(key)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        context.coordinator.tableView = table
        context.coordinator.reload()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Reading `document.doc`/`activeCueId`/`selectedIds`/`settings.quality`
        // here registers this view with Observation tracking — SwiftUI
        // re-invokes updateNSView when any of them change, matching the same
        // mechanism `body` uses.
        context.coordinator.sync(activeCueId: document.activeCueId, selectedIds: document.selectedIds)
        context.coordinator.qualityThresholds = settings.quality
        context.coordinator.onEditTags = onEditTags
        if let table = nsView.documentView as? NSTableView {
            syncColumns(table, settings: settings)
            // Column titles and the context menu are plain strings set once at
            // construction — rebuild them so a live language switch (View ▸
            // 언어) actually relocalizes the grid, not just SwiftUI-driven panels.
            table.menu = context.coordinator.makeContextMenu()
        }
        context.coordinator.reload()
    }

    /// Actor/Translation are optional (View ▸ 화자/번역 열 표시, default hidden —
    /// matches useSettingsStore.ts's defaults); every other column is always
    /// shown. Adds/removes NSTableColumns to match, preserving CueColumn order,
    /// and refreshes titles on every call so language switches take effect.
    private func syncColumns(_ table: NSTableView, settings: AppSettings) {
        func isVisible(_ col: CueColumn) -> Bool {
            switch col {
            case .actor: return settings.showActor
            case .translation: return settings.showTranslation
            default: return true
            }
        }
        for (index, col) in CueColumn.allCases.enumerated() {
            let existing = table.tableColumn(withIdentifier: col.identifier)
            if isVisible(col), existing == nil {
                let column = NSTableColumn(identifier: col.identifier)
                column.title = col.title
                column.width = col.defaultWidth
                column.minWidth = col.minWidth
                if let maxWidth = col.maxWidth { column.maxWidth = maxWidth }
                table.addTableColumn(column)
                table.moveColumn(table.tableColumns.count - 1, toColumn: min(index, table.tableColumns.count - 1))
            } else if !isVisible(col), let existing {
                table.removeTableColumn(existing)
            } else if let existing {
                existing.title = col.title
            }
        }
    }
}

/// Column identity + presentation. Order here is left-to-right column order.
@MainActor
enum CueColumn: CaseIterable {
    case flag, index, start, end, duration, style, actor, text, translation

    var identifier: NSUserInterfaceItemIdentifier { .init("col.\(self)") }

    var title: String {
        switch self {
        case .flag: return ""
        case .index: return t("cueNumber")
        case .start: return t("start")
        case .end: return t("end")
        case .duration: return "\(t("duration"))/CPS"
        case .style: return t("cueStyle")
        case .actor: return t("actor")
        case .text: return t("text")
        case .translation: return t("translation")
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .flag: return 14
        case .index: return 34
        case .start, .end: return 82
        case .duration: return 64
        case .style, .actor: return 90
        case .text, .translation: return 220
        }
    }
    var minWidth: CGFloat {
        switch self {
        case .flag: return 14
        case .index: return 28
        case .start, .end: return 70
        case .duration: return 56
        case .style, .actor: return 50
        case .text, .translation: return 120
        }
    }
    var maxWidth: CGFloat? {
        switch self {
        case .flag: return 14
        case .index: return 44
        case .duration: return 76
        default: return nil
        }
    }

    var isEditable: Bool {
        switch self {
        case .start, .end, .style, .actor, .text, .translation: return true
        case .flag, .index, .duration: return false
        }
    }
}
