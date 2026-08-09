// Format registry (ported from ../../src/formats/index.ts).
// Adding a new external format = one adapter file + one entry here.

import Foundation

public struct FormatAdapter: Sendable {
    public let id: SubFormat
    public let label: String
    public let extensions: [String] // first is the canonical/default extension
    public let parse: @Sendable (String) -> SubtitleDocument
    public let serialize: @Sendable (SubtitleDocument) -> String
}

public let EXTERNAL_ADAPTERS: [FormatAdapter] = [
    FormatAdapter(id: .srt, label: "SubRip (.srt)", extensions: ["srt"], parse: parseSrt, serialize: serializeSrt),
    FormatAdapter(id: .vtt, label: "WebVTT (.vtt)", extensions: ["vtt"], parse: parseVtt, serialize: serializeVtt),
    FormatAdapter(id: .ass, label: "ASS/SSA (.ass)", extensions: ["ass", "ssa"], parse: parseAss, serialize: serializeAss),
    FormatAdapter(id: .smi, label: "SAMI (.smi)", extensions: ["smi", "sami"], parse: parseSmi, serialize: serializeSmi),
    FormatAdapter(id: .sbv, label: "YouTube (.sbv)", extensions: ["sbv"], parse: parseSbv, serialize: serializeSbv),
    FormatAdapter(id: .lrc, label: "LRC Lyrics (.lrc)", extensions: ["lrc"], parse: parseLrc, serialize: serializeLrc),
    FormatAdapter(id: .txt, label: "Plain Text (.txt)", extensions: ["txt"], parse: parseTxt, serialize: serializeTxt),
    // .xml is listed last so a bare .xml opens as TTML only when nothing more
    // specific claimed it — the extension is generic, the others are not.
    FormatAdapter(id: .ttml, label: "TTML/DFXP (.ttml)", extensions: ["ttml", "dfxp", "xml"], parse: parseTtml, serialize: serializeTtml),
    FormatAdapter(id: .stl, label: "EBU-STL (.stl)", extensions: ["stl"], parse: parseStl, serialize: serializeStl),
    FormatAdapter(id: .scc, label: "Scenarist SCC (.scc)", extensions: ["scc"], parse: parseScc, serialize: serializeScc),
]

/// Every extension we can open, including the native project file.
public func openExtensions() -> [String] {
    [NATIVE_EXT] + EXTERNAL_ADAPTERS.flatMap(\.extensions)
}

public func extensionOf(_ path: String) -> String {
    (path as NSString).pathExtension.lowercased()
}

public enum FormatRegistryError: Error, CustomStringConvertible {
    case unknownFormat(SubFormat)
    case unsupportedExtension(String)
    public var description: String {
        switch self {
        case .unknownFormat(let f): return "알 수 없는 포맷: \(f)"
        case .unsupportedExtension(let p): return "지원하지 않는 확장자입니다: \(p)"
        }
    }
}

public func adapterForFormat(_ format: SubFormat) -> FormatAdapter {
    // Every SubFormat case has a registered adapter (enforced by the switch in
    // detectedFormat below being exhaustive over the same set) — force-unwrap is safe.
    EXTERNAL_ADAPTERS.first { $0.id == format }!
}

private func adapterForExtension(_ ext: String) -> FormatAdapter? {
    EXTERNAL_ADAPTERS.first { $0.extensions.contains(ext) }
}

public enum DetectedFormat: Equatable, Sendable {
    case glyph
    case external(SubFormat)
}

/// Detect by extension; `.glyph` for the native file, else an external format, else nil.
public func detectFormat(_ path: String) -> DetectedFormat? {
    let ext = extensionOf(path)
    if ext == NATIVE_EXT { return .glyph }
    return adapterForExtension(ext).map { .external($0.id) }
}

/// Parse file content based on its path's extension.
public func parseByPath(_ path: String, _ raw: String) throws -> SubtitleDocument {
    switch detectFormat(path) {
    case .glyph: return try parseGlyph(raw)
    case .external(let fmt): return adapterForFormat(fmt).parse(raw)
    case nil: throw FormatRegistryError.unsupportedExtension(path)
    }
}
