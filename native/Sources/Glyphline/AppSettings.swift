// App-wide settings (ported from ../../src/stores/useSettingsStore.ts). Only the
// pieces M5's panels need — persistence (UserDefaults / .xcstrings-driven i18n)
// is M6 scope; this holds live values for the current session.

import Observation
import Foundation
import GlyphlineCore

@MainActor
@Observable
final class AppSettings {
    var quality: QualityThresholds = DEFAULT_THRESHOLDS
    var showTranslation = false
    var showActor = false

    var language: AppLang {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
            L10nStore.shared.setLanguage(language)
        }
    }
    private let languageKey = "glyphline.language"

    /// Most-recent-first subtitle paths (max 8), persisted across launches.
    private(set) var recentFiles: [String] = []
    private let recentFilesKey = "glyphline.recentFiles"

    init() {
        recentFiles = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        if let saved = UserDefaults.standard.string(forKey: languageKey), let lang = AppLang(rawValue: saved) {
            language = lang
        } else {
            language = .systemDefault
        }
        L10nStore.shared.setLanguage(language)
    }

    func addRecentFile(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        if recentFiles.count > 8 { recentFiles.removeLast(recentFiles.count - 8) }
        UserDefaults.standard.set(recentFiles, forKey: recentFilesKey)
    }

    func clearRecentFiles() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }
}
