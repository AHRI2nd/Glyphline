// Crash-recovery autosave. Every 30s, snapshots every DIRTY tab (not just the
// foreground one — losing a background tab's changes to a crash defeats the
// point of the safety net), lossless .glyph JSON.  On startup the app offers
// to restore the most recent snapshot; older ones for the SAME tab stay
// available in the recovery sheet, and any OTHER tab that also had pending
// recovery data gets offered afterward (see AppState.restoreRecovery /
// discardRecovery's group-advancing logic).
//
// WHY a ROLLING SET PER TAB rather than one file: a single slot is
// overwritten every 30 seconds, so the moment a bad edit is autosaved the
// good version is gone — the safety net only protected against crashes, not
// against the far more common "I broke this and undo won't reach back far
// enough". Keeping the last few snapshots per tab costs a handful of small
// files and turns the net into something you can actually pick a point from.
//
// Snapshots live in the temp directory (the OS may purge them between
// sessions), which is correct for crash recovery: they are not a backup
// system, and treating them as one would invite relying on them instead of
// saving.

import Foundation
import GlyphlineCore

struct AutosaveData: Codable, Identifiable {
    var savedAt: Date
    /// Which tab this came from — a fresh UUID every launch (tabs aren't
    /// persisted as a session), but stable for the lifetime of the run that
    /// wrote it, which is exactly what's needed to group "5 rolling versions
    /// of the same document" apart from "a different tab's own snapshot".
    var tabId: UUID
    var filePath: String?
    var fileName: String?
    var glyph: String

    var id: Date { savedAt } // sheet(item:) needs Identifiable; timestamp is unique enough here
}

@MainActor
final class AutosaveService {
    /// How many snapshots to keep PER TAB. Enough to step back a few minutes
    /// of work without letting the temp directory grow without bound.
    private static let keepCountPerTab = 5
    private static let prefix = "glyphline_autosave_"
    private static var directory: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }

    private weak var state: AppState?
    private var timer: Timer?

    init(state: AppState) {
        self.state = state
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Every dirty tab — the active one read live from `document` (the only
    /// one that can actually be edited), inactive ones from their frozen
    /// snapshot, same source `AppState.anyTabDirty` already reads.
    private func tick() {
        guard let state else { return }
        for tab in state.tabs {
            let isActive = tab.id == state.activeTabId
            let dirty = isActive ? state.document.isDirty : tab.isDirty
            guard dirty else { continue }
            let doc = isActive ? state.document.doc : tab.snapshot
            guard !doc.cues.isEmpty else { continue }
            guard let glyph = try? serializeGlyph(doc) else { continue }
            let data = AutosaveData(
                savedAt: Date(), tabId: tab.id,
                filePath: isActive ? state.document.filePath : tab.path,
                fileName: isActive ? state.document.fileName : tab.fileName,
                glyph: glyph)
            guard let json = try? JSONEncoder().encode(data) else { continue }

            // tabId in the filename groups one tab's rolling history together
            // and keeps different tabs' files from colliding or interleaving.
            let stamp = Int(data.savedAt.timeIntervalSince1970 * 1000)
            let url = Self.directory.appendingPathComponent("\(Self.prefix)\(tab.id.uuidString)_\(stamp).json")
            // .atomic matters more here than anywhere else in the app: this
            // file exists to survive a crash, and a plain write leaves a
            // truncated file if the process dies mid-write. Every other
            // write path is already atomic; this one was the outlier.
            try? json.write(to: url, options: .atomic)
            Self.pruneOldSnapshots(tabId: tab.id)
        }
    }

    /// Snapshot files, in no particular order — callers that need
    /// chronological order sort the DECODED `savedAt`, not the filename,
    /// since the filename now leads with tabId rather than a timestamp.
    private static func snapshotURLs(tabId: UUID? = nil) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { url in
            guard url.pathExtension == "json" else { return false }
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            guard let tabId else { return true }
            return name.hasPrefix("\(prefix)\(tabId.uuidString)_")
        }
    }

    private static func pruneOldSnapshots(tabId: UUID) {
        let sorted = snapshotURLs(tabId: tabId).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in sorted.dropFirst(keepCountPerTab) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Every recoverable snapshot across every tab, newest first. A corrupt
    /// file is skipped rather than aborting the scan — one bad write
    /// shouldn't hide the rest.
    static func pendingSnapshots() -> [AutosaveData] {
        snapshotURLs()
            .compactMap { url -> AutosaveData? in
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
                return try? JSONDecoder().decode(AutosaveData.self, from: data)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// The most recent snapshot — what the app offers on launch.
    static func checkPending() -> AutosaveData? { pendingSnapshots().first }

    /// Clears every tab's recovery data.
    static func clear() {
        for url in snapshotURLs() { try? FileManager.default.removeItem(at: url) }
        // Also remove the pre-rolling single-slot file, so upgrading from an
        // older build doesn't leave one orphan snapshot behind forever.
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("glyphline_autosave.json"))
    }

    /// Clears recovery data for ONE tab only — used when that tab's recovery
    /// has been resolved (restored or discarded) but other tabs' pending
    /// recovery data is still waiting to be offered.
    static func clearGroup(tabId: UUID) {
        for url in snapshotURLs(tabId: tabId) { try? FileManager.default.removeItem(at: url) }
    }
}
