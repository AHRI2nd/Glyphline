// Localization lookup. Backed by Resources/{ko,en,ja}.lproj/Localizable.strings
// (classic Foundation localization — NOT a String Catalog; see CLAUDE.md / M7
// notes for why .xcstrings doesn't work with a plain `swift build`).

import Foundation
import Observation

/// Resolves the SwiftPM resource bundle. Prefers the standard, codesign-safe
/// Contents/Resources/ location that `scripts/release.sh` assembles a signed
/// build into; falls back to `Bundle.module` (SwiftPM's own generated
/// accessor, which expects the resource bundle as a sibling of Contents/ —
/// fine for `swift run`/`swift build`/`swift test`, but that placement fails
/// codesign's "unsealed contents in bundle root" check, which is exactly why
/// the release script doesn't use it).
private func resolveResourceBundle() -> Bundle {
    if let resourceURL = Bundle.main.resourceURL {
        let candidate = resourceURL.appendingPathComponent("Glyphline_Glyphline.bundle")
        if FileManager.default.fileExists(atPath: candidate.path), let bundle = Bundle(url: candidate) {
            return bundle
        }
    }
    return .module
}

/// Supported UI languages (ported from ../../src/i18n/translations.ts's Lang).
enum AppLang: String, CaseIterable, Codable {
    case ko, en, ja

    /// Best guess from the system's preferred localizations, falling back to en.
    static var systemDefault: AppLang {
        for code in resolveResourceBundle().preferredLocalizations {
            if let lang = AppLang(rawValue: String(code.prefix(2))) { return lang }
        }
        return .en
    }
}

/// Holds the active locale bundle. `t(_:)` reads `bundle` on every call, and
/// since this is `@Observable`, any SwiftUI view (or NSViewRepresentable
/// update*/make* method — same tracking mechanism) that calls `t(_:)` during
/// body/update evaluation re-renders automatically when the language changes,
/// without threading AppSettings through 200+ call sites.
@MainActor
@Observable
final class L10nStore {
    static let shared = L10nStore()
    private(set) var bundle: Bundle = resolveResourceBundle()

    func setLanguage(_ lang: AppLang) {
        let root = resolveResourceBundle()
        guard let path = root.path(forResource: lang.rawValue, ofType: "lproj"),
              let b = Bundle(path: path) else {
            bundle = root
            return
        }
        bundle = b
    }
}

@MainActor
func t(_ key: String) -> String {
    L10nStore.shared.bundle.localizedString(forKey: key, value: nil, table: nil)
}

@MainActor
func t(_ key: String, _ args: CVarArg...) -> String {
    String(format: t(key), arguments: args)
}

/// Label for a command that needs more input before it can finish — i.e. one
/// that opens a dialog. macOS marks those with a trailing ellipsis.
///
/// The ellipsis is added here rather than baked into the strings files so each
/// concept has exactly ONE name: "일괄 정리" is the panel's title and
/// `menuLabel("batchCleanup")` is the menu item that opens it. Storing both
/// spellings separately is what let them drift apart (a panel titled
/// "스타일 매니저" opened by a menu item called "스타일 관리…").
@MainActor
func menuLabel(_ key: String) -> String { t(key) + "…" }
