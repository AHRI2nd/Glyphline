// Subtitle file read/write (ported from ../../../src-tauri/src/lib.rs's
// read_text_file / write_text_file / write_text_file_encoded, plus the
// glyph/format dispatch from ../../../src/stores/useSubtitleStore.ts).

import Foundation

/// Line terminator written out. Deliverable systems disagree about this:
/// broadcast pipelines and a lot of Windows/hardware players want CRLF, while
/// everything on Unix wants LF. Writing only LF meant re-running files through
/// another tool before delivery.
public enum LineEnding: String, Codable, Sendable, CaseIterable {
    case lf, crlf
    public var terminator: String { self == .crlf ? "\r\n" : "\n" }
}

/// How text is written out. UTF-8 without a BOM is the default; the rest exist
/// because specific delivery targets demand them.
public struct TextOutputOptions: Sendable, Equatable {
    public var encodingLabel: String
    public var lineEnding: LineEnding
    /// Some players only recognise a UTF-8 file when it starts with a BOM.
    public var writeBOM: Bool

    public init(encodingLabel: String = "utf-8", lineEnding: LineEnding = .lf, writeBOM: Bool = false) {
        self.encodingLabel = encodingLabel
        self.lineEnding = lineEnding
        self.writeBOM = writeBOM
    }

    public static let `default` = TextOutputOptions()
}

public enum SubtitleFileIO {
    /// Read + decode a subtitle file (encoding-aware, see TextEncoding) and
    /// parse it by its path's extension.
    /// `forcingEncoding` overrides auto-detection — the escape hatch for a file
    /// that detected wrong, which was previously unrecoverable: the user saw
    /// mojibake and had no way to say "no, it's CP949".
    public static func open(path: String, forcingEncoding label: String? = nil) throws -> SubtitleDocument {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Binary formats have no "text encoding" — the bytes ARE the data.
        // Bridge them 1:1 (see STL.swift's bytesToLatin1String) instead of
        // running BOM/chardet detection, which would corrupt them.
        if detectFormat(path) == .external(.stl) {
            return adapterForFormat(.stl).parse(bytesToLatin1String([UInt8](data)))
        }
        let raw: String
        if let label {
            guard let forced = TextEncoding.decode(data, forcing: label) else {
                throw FileIOError.encodingMismatch(label)
            }
            raw = forced
        } else {
            raw = TextEncoding.decode(data)
        }
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

    /// Export in an external format with the caller's output options.
    public static func export(
        _ doc: SubtitleDocument,
        format: SubFormat,
        to path: String,
        options: TextOutputOptions = .default
    ) throws {
        let content = adapterForFormat(format).serialize(doc)
        if format == .stl {
            // Raw bytes via the Latin-1 bridge, bypassing CRLF/BOM/encoding-
            // label handling entirely — none of that applies to a binary format.
            try Data(latin1StringToBytes(content)).write(to: URL(fileURLWithPath: path), options: .atomic)
            return
        }
        if format == .scc {
            // Plain ASCII with a fixed literal header real decoders match
            // byte-for-byte — a non-UTF-8 encoding (UTF-16 especially) would
            // corrupt it, and a BOM would break the header check. Same
            // exemption as .stl, just already representable without the
            // Latin-1 bridge.
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        try writeText(content, to: path, options: options)
    }

    /// Applies line-ending and BOM choices, then writes in the chosen encoding.
    public static func writeText(_ content: String, to path: String, options: TextOutputOptions) throws {
        // Normalise to LF first so a document that already contains CRLF (from
        // an imported file) doesn't come out with CRCRLF.
        var text = content.replacingOccurrences(of: "\r\n", with: "\n")
        if options.lineEnding == .crlf {
            text = text.replacingOccurrences(of: "\n", with: "\r\n")
        }
        let encoding = TextEncoding.encoding(forLabel: options.encodingLabel)
        guard var data = text.data(using: encoding) else {
            throw FileIOError.encodingMismatch(options.encodingLabel)
        }
        if options.writeBOM, let bom = bomBytes(for: encoding) {
            data = bom + data
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func bomBytes(for encoding: String.Encoding) -> Data? {
        switch encoding {
        case .utf8: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: return Data([0xFF, 0xFE])
        case .utf16BigEndian: return Data([0xFE, 0xFF])
        default: return nil // legacy single/double-byte encodings have no BOM
        }
    }
}

public enum FileIOError: Error, CustomStringConvertible {
    /// The bytes aren't representable in the requested encoding.
    case encodingMismatch(String)
    public var description: String {
        switch self {
        case .encodingMismatch(let label):
            return "\(TextEncoding.displayName(forLabel: label))"
        }
    }
}
