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

    /// 0.7...1.3, applied as a `.scaleEffect` on the whole window content.
    var uiScale: Double {
        didSet { UserDefaults.standard.set(uiScale, forKey: uiScaleKey) }
    }
    private let uiScaleKey = "glyphline.uiScale"

    var autoCheckUpdate: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdate, forKey: autoCheckUpdateKey) }
    }
    private let autoCheckUpdateKey = "glyphline.autoCheckUpdate"
    /// Ephemeral (not persisted) — set by `UpdateCheck` when a newer release exists.
    var availableUpdateVersion: String?

    /// Free-docking layout tree (video/waveform/subtitles panes) — see DockModel.swift.
    var dockLayout: DockNode {
        didSet { persistDockLayout() }
    }
    private let dockLayoutKey = "glyphline.dockLayout"

    /// Most-recent-first subtitle paths (max 8), persisted across launches.
    private(set) var recentFiles: [String] = []
    private let recentFilesKey = "glyphline.recentFiles"

    init() {
        recentFiles = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []

        let resolvedLanguage: AppLang
        if let saved = UserDefaults.standard.string(forKey: languageKey), let lang = AppLang(rawValue: saved) {
            resolvedLanguage = lang
        } else {
            resolvedLanguage = .systemDefault
        }
        language = resolvedLanguage

        let savedScale = UserDefaults.standard.double(forKey: uiScaleKey)
        uiScale = savedScale > 0 ? savedScale : 1.0
        autoCheckUpdate = UserDefaults.standard.object(forKey: autoCheckUpdateKey) as? Bool ?? true

        if let data = UserDefaults.standard.data(forKey: dockLayoutKey),
           let decoded = try? JSONDecoder().decode(DockNode.self, from: data) {
            dockLayout = decoded
        } else {
            dockLayout = .defaultLayout
        }

        // Deferred until every stored property is set — touching `self.language`
        // (a computed/observed property) any earlier trips Swift's strict
        // definite-initialization check.
        L10nStore.shared.setLanguage(resolvedLanguage)
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

    // ── Dock layout mutations ───────────────────────────────────────────────────

    func moveDockPanel(_ panel: PanelKind, toZone zone: DropZone, ofTarget target: PanelKind) {
        dockLayout = movingPanel(panel, toZone: zone, ofTarget: target, in: dockLayout)
    }

    func selectDockTab(_ panel: PanelKind, tabsetPath: [Int]) {
        dockLayout = updatingSelection(at: tabsetPath, to: panel, in: dockLayout)
    }

    func setDockWeights(at path: [Int], to weights: [Double]) {
        dockLayout = updatingWeights(at: path, to: weights, in: dockLayout)
    }

    func resetDockLayout() {
        dockLayout = .defaultLayout
    }

    private func persistDockLayout() {
        guard let data = try? JSONEncoder().encode(dockLayout) else { return }
        UserDefaults.standard.set(data, forKey: dockLayoutKey)
    }
}
