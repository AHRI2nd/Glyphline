// Subtitle file read/write (ported from ../../../src-tauri/src/lib.rs's
// read_text_file / write_text_file / write_text_file_encoded, plus the
// glyph/format dispatch from ../../../src/stores/useSubtitleStore.ts).

import Foundation

public enum SubtitleFileIO {
    /// Read + decode a subtitle file (encoding-aware, see TextEncoding) and
    /// parse it by its path's extension.
    public static func open(path: String) throws -> SubtitleDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let raw = TextEncoding.decode(data)
        switch detectFormat(path) {
        case .glyph: return try parseGlyph(raw)
        case .external(let fmt): return adapterForFormat(fmt).parse(raw)
        case nil: throw FormatRegistryError.unsupportedExtension(path)
        }
    }

    /// Save as the native lossless `.glyph` project format (always UTF-8).
    public static func saveGlyph(_ doc: SubtitleDocument, to path: String) throws {
        let content = try serializeGlyph(doc)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Export in an external format. `encodingLabel` (e.g. "euc-kr") writes a
    /// legacy encoding for players that need it (Korean SMI); omitted → UTF-8.
    public static func export(_ doc: SubtitleDocument, format: SubFormat, to path: String, encodingLabel: String? = nil) throws {
        let content = adapterForFormat(format).serialize(doc)
        let encoding = encodingLabel.map(TextEncoding.encoding(forLabel:)) ?? .utf8
        try content.write(toFile: path, atomically: true, encoding: encoding)
    }
}
