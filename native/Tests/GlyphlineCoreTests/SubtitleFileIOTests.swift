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
        try SubtitleFileIO.export(doc, format: .smi, to: path,
                                  options: TextOutputOptions(encodingLabel: "cp949"))

        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = String(data: bytes, encoding: TextEncoding.cp949)
        #expect(decoded?.contains("안녕하세요") == true)
    }

    // Regression coverage for a bug the code-review pass found: SCC (plain
    // ASCII with a literal header real decoders match byte-for-byte) was
    // falling through to the general writeText path, so a UTF-16 delivery
    // setting silently corrupted it with interleaved null bytes and a BOM
    // setting broke the header. STL already had this exemption; SCC didn't.
    @Test("export ignores the general encoding/BOM options for STL, writing raw ASCII-safe bytes")
    func exportSTLIgnoresEncodingOptions() throws {
        let path = tempPath("out.stl")
        defer { try? FileManager.default.removeItem(atPath: path) }

        var doc = SubtitleDocument(format: .stl)
        doc.cues = [Cue(id: "a", start: 1, end: 3, text: "Hello")]
        // A UTF-16 + BOM option set, exactly what would corrupt this format
        // if it were routed through the general text path.
        try SubtitleFileIO.export(doc, format: .stl, to: path,
                                  options: TextOutputOptions(encodingLabel: "utf-16le", writeBOM: true))

        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(bytes.count == 1024 + 128) // GSI + one TTI block, no BOM prefix
        #expect(bytes.prefix(3) == Data("437".utf8))
    }

    @Test("export ignores the general encoding/BOM options for SCC, writing plain UTF-8")
    func exportSCCIgnoresEncodingOptions() throws {
        let path = tempPath("out.scc")
        defer { try? FileManager.default.removeItem(atPath: path) }

        var doc = SubtitleDocument(format: .scc)
        doc.cues = [Cue(id: "a", start: 1, end: 3, text: "Hello")]
        try SubtitleFileIO.export(doc, format: .scc, to: path,
                                  options: TextOutputOptions(encodingLabel: "utf-16le", writeBOM: true))

        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        // A UTF-16-corrupted file would not decode as UTF-8 at all, let alone
        // start with the literal header real SCC decoders require.
        let text = String(data: bytes, encoding: .utf8)
        #expect(text?.hasPrefix("Scenarist_SCC V1.0") == true)
    }
}
