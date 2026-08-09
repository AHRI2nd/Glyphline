// Resolves a font NAME (as it appears in an ASS style or \fn override) to an
// installed system font's file on disk, via CoreText — the platform-specific
// half of task N. GlyphlineCore stays pure/no-AppKit; this is the one place
// that actually touches the font system.

import AppKit
import CoreText
import GlyphlineCore

enum FontCollector {
    struct Resolved {
        let name: String
        let url: URL
    }

    /// Best-effort resolution: tries the name as a PostScript name first (the
    /// common case for anything not a plain family name), then as a family
    /// name via NSFontManager. Returns nil if nothing on the system matches —
    /// the caller reports that font as "not found" rather than guessing.
    static func resolve(_ name: String) -> Resolved? {
        let descriptor: CTFontDescriptor
        if let byPostScriptName = CTFontCreateWithName(name as CFString, 12, nil) as CTFont? {
            descriptor = CTFontCopyFontDescriptor(byPostScriptName)
        } else if let family = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: 12) {
            descriptor = CTFontDescriptorCreateWithNameAndSize(family.fontName as CFString, 12)
        } else {
            return nil
        }
        guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else { return nil }
        // CTFontCreateWithName silently falls back to the system UI font when
        // the name matches nothing real — verify the resolved font's
        // PostScript/family name actually relates to what was asked for,
        // otherwise every unresolvable name would wrongly "succeed" as Helvetica.
        let resolvedFont = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let resolvedNames = [
            CTFontCopyPostScriptName(resolvedFont) as String,
            CTFontCopyFamilyName(resolvedFont) as String? ?? "",
            CTFontCopyFullName(resolvedFont) as String? ?? "",
        ]
        guard resolvedNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        return Resolved(name: name, url: url)
    }

    /// Resolves and UU-encodes every font the document references but
    /// doesn't already embed. Returns (added AssEmbedded entries, names that
    /// couldn't be found on this system).
    static func collect(for doc: SubtitleDocument) -> (embedded: [AssEmbedded], notFound: [String]) {
        var embedded: [AssEmbedded] = []
        var notFound: [String] = []
        // Two different referenced names (a style's family name and an
        // inline \fn's PostScript name, say) can resolve to the SAME
        // underlying font file — dedupe by that file, not by the name that
        // led here, or the document ends up with two [Fonts] entries sharing
        // one `name`, which breaks the SwiftUI list identity the display
        // panel keys on.
        var seenFileNames = Set((doc.fonts ?? []).map(\.name))
        for name in missingEmbeddedFonts(doc).sorted() {
            guard let resolved = resolve(name), let data = try? Data(contentsOf: resolved.url) else {
                notFound.append(name)
                continue
            }
            let fileName = resolved.url.lastPathComponent
            guard !seenFileNames.contains(fileName) else { continue }
            seenFileNames.insert(fileName)
            embedded.append(AssEmbedded(name: fileName, data: encodeAssEmbedded(data)))
        }
        return (embedded, notFound)
    }

    struct CollectedFont: Sendable {
        let fontName: String
        let destPath: String
    }

    /// Resolves every font this document references but doesn't already
    /// embed (same `missingEmbeddedFonts` set `collect(for:)` uses), and
    /// copies the actual font FILE — not a UU-encoded embed — into
    /// `destFolder` (created if needed). For the delivery pipeline's Fonts/
    /// folder, which a client needs as real files, not `collect(for:)`'s
    /// ASS-embed encoding.
    ///
    /// Dedupes by destination file name the same way `collect(for:)` dedupes
    /// by embedded entry name, so two referenced names resolving to the same
    /// underlying file only copy once.
    static func collectFiles(for doc: SubtitleDocument, into destFolder: String) -> (copied: [CollectedFont], notFound: [String]) {
        var copied: [CollectedFont] = []
        var notFound: [String] = []
        var seenFileNames = Set<String>()
        for name in missingEmbeddedFonts(doc).sorted() {
            guard let resolved = resolve(name) else {
                notFound.append(name)
                continue
            }
            let fileName = resolved.url.lastPathComponent
            guard !seenFileNames.contains(fileName) else { continue }
            seenFileNames.insert(fileName)
            let destPath = (destFolder as NSString).appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(atPath: destFolder, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destPath) {
                    try FileManager.default.removeItem(atPath: destPath)
                }
                try FileManager.default.copyItem(at: resolved.url, to: URL(fileURLWithPath: destPath))
                copied.append(CollectedFont(fontName: name, destPath: destPath))
            } catch {
                notFound.append(name)
            }
        }
        return (copied, notFound)
    }
}
