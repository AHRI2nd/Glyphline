// Localization lookup. Backed by Resources/{ko,en,ja}.lproj/Localizable.strings
// (classic Foundation localization — NOT a String Catalog; see CLAUDE.md / M7
// notes for why .xcstrings doesn't work with a plain `swift build`).

import Foundation
import Observation

/// Supported UI languages (ported from ../../src/i18n/translations.ts's Lang).
enum AppLang: String, CaseIterable, Codable {
    case ko, en, ja

    /// Best guess from the system's preferred localizations, falling back to en.
    static var systemDefault: AppLang {
        for code in Bundle.module.preferredLocalizations {
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
    private(set) var bundle: Bundle = .module

    func setLanguage(_ lang: AppLang) {
        guard let path = Bundle.module.path(forResource: lang.rawValue, ofType: "lproj"),
              let b = Bundle(path: path) else {
            bundle = .module
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
