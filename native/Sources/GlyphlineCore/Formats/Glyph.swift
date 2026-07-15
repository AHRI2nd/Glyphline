// Native .glyph format — lossless JSON serialization of SubtitleDocument
// (ported from ../../src/formats/glyph.ts). This is the canonical save format;
// everything in the model round-trips exactly. External formats are lossy exports.

import Foundation

public enum GlyphError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let m): return m }
    }
}

public func serializeGlyph(_ doc: SubtitleDocument) throws -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted]
    let data = try enc.encode(GlyphFile(document: doc))
    return String(data: data, encoding: .utf8) ?? ""
}

public func parseGlyph(_ raw: String) throws -> SubtitleDocument {
    guard let data = raw.data(using: .utf8) else { throw GlyphError.invalid(".glyph 인코딩 오류") }
    // Lenient wrapper: schemaVersion may be absent (defaults to 1), matching TS.
    struct LenientFile: Decodable {
        var schemaVersion: Int?
        var document: SubtitleDocument
    }
    let file: LenientFile
    do {
        file = try JSONDecoder().decode(LenientFile.self, from: data)
    } catch {
        throw GlyphError.invalid(".glyph 파싱 실패: \(error)")
    }
    return migrate(file.schemaVersion ?? 1, file.document)
}

/// Forward migrations. v1 is current; a newer file loads as-is (defensive).
/// NOTE: unlike the TS version, Swift's decoder drops unrecognized JSON keys —
/// revisit if forward-compat preservation of unknown fields becomes needed.
private func migrate(_ version: Int, _ doc: SubtitleDocument) -> SubtitleDocument {
    _ = version
    return doc
}
