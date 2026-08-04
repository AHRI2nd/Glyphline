// Crash-recovery autosave (ported from ../../../src/App.tsx's autosave effect).
// Every 30s, if the document is dirty and non-empty, snapshot it (lossless
// .glyph JSON) to a fixed temp path. On startup, the app offers to restore it.
// The file is deleted on manual save, explicit discard, or "close without saving".

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
    private static let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glyphline_autosave.json")

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
        // .atomic matters more here than anywhere else in the app: this file
        // exists to survive a crash, and a plain write leaves a truncated file
        // if the process dies mid-write. checkPending() silently returns nil on
        // a corrupt file, so the failure mode is "recovery quietly unavailable
        // exactly when it was needed". Every other write path in the app is
        // already atomic; this one was the outlier.
        try? json.write(to: Self.path, options: .atomic)
    }

    /// Checked once at launch — returns the pending autosave, if any.
    static func checkPending() -> AutosaveData? {
        guard let data = try? Data(contentsOf: path), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(AutosaveData.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: path)
    }
}
