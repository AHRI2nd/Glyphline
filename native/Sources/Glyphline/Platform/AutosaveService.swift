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
        try? json.write(to: Self.path)
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
