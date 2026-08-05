// Glyphline canonical data model (ported from ../../src/types/subtitle.ts).
//
// The whole app edits a single in-memory `SubtitleDocument`. External formats
// (SRT/VTT/ASS/SMI/SBV/LRC/TXT) are adapters that parse into / serialize out of
// this model; the native `.glyph` (JSON) format persists it losslessly.
//
// Codable is tuned to match the TypeScript `.glyph` JSON shape byte-for-byte so
// existing project files round-trip: property names are the JSON keys, and
// synthesized Codable omits `nil` optionals (via encodeIfPresent) — matching how
// the TS serializer omits `undefined` fields.

import Foundation

/// External subtitle formats (the native project format is `.glyph`).
public enum SubFormat: String, Codable, Sendable, CaseIterable {
    case srt, vtt, ass, smi, sbv, lrc, txt
}

/// The native project file extension.
public let NATIVE_EXT = "glyph"

/// Word/character-level timing inside a cue (karaoke, enhanced LRC, forced
/// alignment). Only `.glyph` round-trips these losslessly. `start`/`end` are
/// absolute seconds (not relative to the cue).
public struct SyncToken: Codable, Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public var confidence: Double?

    public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// One run of ASS Dialogue text: an optional override block (the `{...}` content
/// WITHOUT braces, verbatim) followed by literal text. Preserves every inline
/// tag losslessly, known or not.
public struct AssSpan: Codable, Equatable, Sendable {
    public var tags: String?
    public var text: String

    public init(tags: String? = nil, text: String) {
        self.tags = tags
        self.text = text
    }
}

/// Absolute on-screen position override (ASS `\pos` etc.).
public struct CuePosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A single subtitle event. Time is always float seconds.
public struct Cue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var start: Double
    public var end: Double
    public var text: String                 // may contain "\n" (breaks preserved)
    public var translation: String?         // parallel translation — .glyph-only
    public var tokens: [SyncToken]?         // word/char sync
    public var assSpans: [AssSpan]?         // ASS inline tag + text runs (lossless)
    public var style: String?               // ASS style name
    public var layer: Int?                  // ASS layer
    public var actor: String?               // ASS Name field
    public var position: CuePosition?       // absolute position override
    public var raw: [String: String]?       // format-specific unparsed fields

    public init(
        id: String,
        start: Double,
        end: Double,
        text: String,
        translation: String? = nil,
        tokens: [SyncToken]? = nil,
        assSpans: [AssSpan]? = nil,
        style: String? = nil,
        layer: Int? = nil,
        actor: String? = nil,
        position: CuePosition? = nil,
        raw: [String: String]? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.translation = translation
        self.tokens = tokens
        self.assSpans = assSpans
        self.style = style
        self.layer = layer
        self.actor = actor
        self.position = position
        self.raw = raw
    }
}

/// An ASS/SSA style definition.
public struct AssStyle: Codable, Equatable, Sendable {
    public var name: String
    public var fontName: String
    public var fontSize: Double
    public var primaryColour: String
    public var outlineColour: String
    public var backColour: String
    public var bold: Bool
    public var italic: Bool
    public var outline: Double
    public var shadow: Double
    public var alignment: Int
    public var marginL: Int
    public var marginR: Int
    public var marginV: Int
    public var raw: [String: String]?

    public init(
        name: String,
        fontName: String = "Arial",
        fontSize: Double = 48,
        primaryColour: String = "&H00FFFFFF",
        outlineColour: String = "&H00000000",
        backColour: String = "&H00000000",
        bold: Bool = false,
        italic: Bool = false,
        outline: Double = 2,
        shadow: Double = 0,
        alignment: Int = 2,
        marginL: Int = 10,
        marginR: Int = 10,
        marginV: Int = 10,
        raw: [String: String]? = nil
    ) {
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.primaryColour = primaryColour
        self.outlineColour = outlineColour
        self.backColour = backColour
        self.bold = bold
        self.italic = italic
        self.outline = outline
        self.shadow = shadow
        self.alignment = alignment
        self.marginL = marginL
        self.marginR = marginR
        self.marginV = marginV
        self.raw = raw
    }
}

/// A file embedded in an ASS `[Fonts]`/`[Graphics]` section. `data` is the raw
/// UU-encoded payload lines (joined with "\n"), preserved verbatim for lossless
/// round-trip — never decoded on parse.
public struct AssEmbedded: Codable, Equatable, Sendable {
    public var name: String   // the `fontname:` / `filename:` value
    public var data: String   // raw encoded data lines, verbatim

    public init(name: String, data: String) {
        self.name = name
        self.data = data
    }
}

/// The single in-memory document every part of the app edits.
public struct SubtitleDocument: Codable, Equatable, Sendable {
    public var format: SubFormat
    public var frameRate: Double?
    public var styles: [AssStyle]?
    public var fonts: [AssEmbedded]?      // ASS [Fonts]
    public var graphics: [AssEmbedded]?   // ASS [Graphics]
    public var cues: [Cue]
    public var meta: [String: String]
    /// Words the proofreader should leave alone in THIS project — character
    /// names, place names, invented terms. Kept per-document rather than in the
    /// system dictionary because one show's cast shouldn't silence warnings in
    /// another's. `.glyph` only; external formats have nowhere to put it.
    /// Optional so existing files (which lack the key) decode unchanged and
    /// files that never use the feature don't grow a field.
    public var ignoredWords: [String]?
    /// Source→translation term mappings checked by TermConsistency. Per-project
    /// for the same reason as `ignoredWords`: one show's cast list is wrong for
    /// another's. Optional so existing files decode unchanged and documents
    /// that never use it don't grow the key.
    public var glossary: [GlossaryEntry]?

    public init(
        format: SubFormat = .srt,
        frameRate: Double? = nil,
        styles: [AssStyle]? = nil,
        fonts: [AssEmbedded]? = nil,
        graphics: [AssEmbedded]? = nil,
        cues: [Cue] = [],
        meta: [String: String] = [:],
        ignoredWords: [String]? = nil,
        glossary: [GlossaryEntry]? = nil
    ) {
        self.format = format
        self.frameRate = frameRate
        self.styles = styles
        self.fonts = fonts
        self.graphics = graphics
        self.cues = cues
        self.meta = meta
        self.ignoredWords = ignoredWords
        self.glossary = glossary
    }
}

public extension SubtitleDocument {
    /// A fresh empty document.
    static func empty(_ format: SubFormat = .srt) -> SubtitleDocument {
        SubtitleDocument(format: format, cues: [], meta: [:])
    }
}

/// Native `.glyph` wrapper: lossless serialization + version migration.
public struct GlyphFile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var document: SubtitleDocument

    public init(schemaVersion: Int = GLYPH_SCHEMA_VERSION, document: SubtitleDocument) {
        self.schemaVersion = schemaVersion
        self.document = document
    }
}

public let GLYPH_SCHEMA_VERSION = 1

/// Monotonic-ish unique id for cues created at runtime (mirrors the TS scheme
/// `cue-<base36 time>-<base36 counter>`). IDs read from files are kept verbatim,
/// so this only labels newly created cues.
public func newCueId() -> String {
    let n = CueID.next()
    let time = Int(Date().timeIntervalSince1970 * 1000)
    return "cue-\(String(time, radix: 36))-\(String(n, radix: 36))"
}

private enum CueID {
    nonisolated(unsafe) private static var counter = 0
    private static let lock = NSLock()
    static func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return counter
    }
}
