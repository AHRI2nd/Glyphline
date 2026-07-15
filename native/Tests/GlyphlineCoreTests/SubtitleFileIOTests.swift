import Testing
import Foundation
@testable import GlyphlineCore

@Suite("SubtitleFileIO")
struct SubtitleFileIOTests {
    private func tempPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("glyphline-test-\(UUID().uuidString)-\(name)").path
    }

    @Test("open() detects format by extension and parses")
    func openSrt() throws {
        let path = tempPath("cue.srt")
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nHello\n"
        try srt.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let doc = try SubtitleFileIO.open(path: path)
        #expect(doc.format == .srt)
        #expect(doc.cues.count == 1)
        #expect(doc.cues[0].text == "Hello")
    }

    @Test("open() decodes CP949 SMI transparently")
    func openCP949Smi() throws {
        let path = tempPath("cue.smi")
        let smi = "<SAMI><BODY><SYNC Start=1000><P Class=KRCC>안녕</BODY></SAMI>"
        let data = smi.data(using: TextEncoding.cp949)!
        try data.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let doc = try SubtitleFileIO.open(path: path)
        #expect(doc.format == .smi)
        #expect(doc.cues.first?.text == "안녕")
    }

    @Test("saveGlyph writes UTF-8 lossless round-trip")
    func saveGlyphRoundTrip() throws {
        let path = tempPath("project.glyph")
        defer { try? FileManager.default.removeItem(atPath: path) }

        var doc = SubtitleDocument.empty(.vtt)
        doc.cues = [Cue(id: "a", start: 1, end: 2, text: "hello", translation: "안녕")]
        try SubtitleFileIO.saveGlyph(doc, to: path)

        let reopened = try SubtitleFileIO.open(path: path)
        #expect(reopened == doc)
    }

    @Test("export writes a legacy-encoded SMI when requested")
    func exportCP949() throws {
        let path = tempPath("out.smi")
        defer { try? FileManager.default.removeItem(atPath: path) }

        var doc = SubtitleDocument.empty(.smi)
        doc.cues = [Cue(id: "a", start: 1, end: 3, text: "안녕하세요")]
        try SubtitleFileIO.export(doc, format: .smi, to: path, encodingLabel: "cp949")

        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = String(data: bytes, encoding: TextEncoding.cp949)
        #expect(decoded?.contains("안녕하세요") == true)
    }
}
