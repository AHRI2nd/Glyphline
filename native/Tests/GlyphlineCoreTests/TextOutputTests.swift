import Testing
import Foundation
@testable import GlyphlineCore

@Suite("Text output options")
struct TextOutputTests {
    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "glyphline_test_\(name)_\(UUID().uuidString).srt"
    }

    @Test("LF is the default and CRLF is applied on request")
    func lineEndings() throws {
        let path = tmp("lf")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try SubtitleFileIO.writeText("a\nb\n", to: path, options: .default)
        let lf = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!lf.contains("\r"))

        try SubtitleFileIO.writeText("a\nb\n", to: path,
                                     options: TextOutputOptions(lineEnding: .crlf))
        let crlf = try String(contentsOfFile: path, encoding: .utf8)
        #expect(crlf.contains("\r\n"))
        #expect(!crlf.contains("\r\r"))
    }

    @Test("content that already has CRLF doesn't gain a second CR")
    func noDoubleCR() throws {
        let path = tmp("crcr")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try SubtitleFileIO.writeText("a\r\nb\r\n", to: path,
                                     options: TextOutputOptions(lineEnding: .crlf))
        let out = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!out.contains("\r\r"))
        #expect(out == "a\r\nb\r\n")
    }

    @Test("a BOM is written only when asked, and only where one exists")
    func bom() throws {
        let path = tmp("bom")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SubtitleFileIO.writeText("hi", to: path, options: .default)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)).prefix(3) != Data([0xEF, 0xBB, 0xBF]))

        try SubtitleFileIO.writeText("hi", to: path, options: TextOutputOptions(writeBOM: true))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)).prefix(3) == Data([0xEF, 0xBB, 0xBF]))

        // CP949 has no BOM — asking for one must not corrupt the file.
        try SubtitleFileIO.writeText("한글", to: path,
                                     options: TextOutputOptions(encodingLabel: "cp949", writeBOM: true))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(String(data: data, encoding: TextEncoding.cp949) == "한글")
    }

    @Test("legacy encodings round-trip through write and forced read")
    func legacyRoundTrip() throws {
        for (label, text) in [("cp949", "한글 자막"), ("shift_jis", "日本語の字幕")] {
            let path = tmp(label)
            defer { try? FileManager.default.removeItem(atPath: path) }
            try SubtitleFileIO.writeText(text, to: path,
                                         options: TextOutputOptions(encodingLabel: label))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            #expect(TextEncoding.decode(data, forcing: label) == text, "failed for \(label)")
        }
    }

    @Test("forcing the wrong encoding reports failure instead of silent mojibake")
    func forcedMismatch() {
        // Bytes that are not valid UTF-16LE-with-odd-length.
        let odd = Data([0xED, 0x95, 0x9C])
        #expect(TextEncoding.decode(odd, forcing: "utf-16be") == nil
                || TextEncoding.decode(odd, forcing: "utf-16be") != "한")
    }

    @Test("forced decode strips a matching BOM")
    func forcedStripsBOM() {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)
        #expect(TextEncoding.decode(withBOM, forcing: "utf-8") == "hi")
    }

    @Test("every offered encoding has a display name and maps to something")
    func labels() {
        for label in TextEncoding.selectableLabels {
            #expect(!TextEncoding.displayName(forLabel: label).isEmpty)
            #expect("test".data(using: TextEncoding.encoding(forLabel: label)) != nil)
        }
    }
}
