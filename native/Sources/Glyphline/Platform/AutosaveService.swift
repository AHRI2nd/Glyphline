// Crash-recovery autosave. Every 30s, if the document is dirty and non-empty,
// snapshot it (lossless .glyph JSON). On startup the app offers to restore the
// most recent snapshot; older ones stay available in the recovery sheet.
//
// WHY a ROLLING SET rather than one file: a single slot is overwritten every
// 30 seconds, so the moment a bad edit is autosaved the good version is gone —
// the safety net only protected against crashes, not against the far more
// common "I broke this and undo won't reach back far enough". Keeping the last
// few snapshots costs a handful of small files and turns the net into
// something you can actually pick a point from.
//
// Snapshots live in the temp directory (the OS may purge them between
// sessions), which is correct for crash recovery: they are not a backup
// system, and treating them as one would invite relying on them instead of
// saving.

import Foundation
import GlyphlineCore

struct AutosaveData: Codable, Identifiable {
    var savedAt: Date
    var filePath: String?
    var fileName: String?
    var glyph: String

    var id: Date { savedAt } // sheet(item:) needs Identifiable; timestamp is unique enough here
}

@MainActor
final class AutosaveService {
    /// How many snapshots to keep. Enough to step back a few minutes of work
    /// without letting the temp directory grow without bound.
    private static let keepCount = 5
    private static let prefix = "glyphline_autosave_"
    private static var directory: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }

    private weak var document: DocumentModel?
    private var timer: Timer?

    init(document: DocumentModel) {
        self.document = document
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let document, document.isDirty, !document.doc.cues.isEmpty else { return }
        guard let glyph = try? serializeGlyph(document.doc) else { return }
        let data = AutosaveData(savedAt: Date(), filePath: document.filePath, fileName: document.fileName, glyph: glyph)
        guard let json = try? JSONEncoder().encode(data) else { return }

        // Timestamped name so snapshots sort by filename and never collide.
        let stamp = Int(data.savedAt.timeIntervalSince1970 * 1000)
        let url = Self.directory.appendingPathComponent("\(Self.prefix)\(stamp).json")
        // .atomic matters more here than anywhere else in the app: this file
        // exists to survive a crash, and a plain write leaves a truncated file
        // if the process dies mid-write. Every other write path is already
        // atomic; this one was the outlier.
        try? json.write(to: url, options: .atomic)
        Self.pruneOldSnapshots()
    }

    /// Snapshot files, newest first.
    private static func snapshotURLs() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // timestamp-named
    }

    private static func pruneOldSnapshots() {
        for url in snapshotURLs().dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Every recoverable snapshot, newest first. A corrupt file is skipped
    /// rather than aborting the scan — one bad write shouldn't hide the rest.
    static func pendingSnapshots() -> [AutosaveData] {
        snapshotURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return try? JSONDecoder().decode(AutosaveData.self, from: data)
        }
    }

    /// The most recent snapshot — what the app offers on launch.
    static func checkPending() -> AutosaveData? { pendingSnapshots().first }

    static func clear() {
        for url in snapshotURLs() { try? FileManager.default.removeItem(at: url) }
        // Also remove the pre-rolling single-slot file, so upgrading from an
        // older build doesn't leave one orphan snapshot behind forever.
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("glyphline_autosave.json"))
    }
}
