// App-wide settings (ported from ../../src/stores/useSettingsStore.ts). Only the
// pieces M5's panels need — persistence (UserDefaults / .xcstrings-driven i18n)
// is M6 scope; this holds live values for the current session.

import Observation
import Foundation
import GlyphlineCore
import Sparkle

@MainActor
@Observable
final class AppSettings {
    var quality: QualityThresholds = DEFAULT_THRESHOLDS
    var showTranslation = false
    /// The multi-line editor under the grid. On by default: the grid alone
    /// can't show or accept a line break, so hiding it would leave no way to
    /// do the most common subtitle edit there is.
    var showCueEditor: Bool {
        didSet { UserDefaults.standard.set(showCueEditor, forKey: showCueEditorKey) }
    }
    private let showCueEditorKey = "glyphline.showCueEditor"
    var showActor = false

    var language: AppLang {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
            L10nStore.shared.setLanguage(language)
            // Our own strings (Subtitle/Playback/View menu content, panels) read
            // from L10nStore above and update immediately. But File/Edit/Window/
            // Help and their standard items (Quit, Hide, Cut, Copy, Undo, Enter
            // Full Screen, …) are titled by AppKit itself from its own bundles,
            // resolved once at launch from this "AppleLanguages" default — never
            // from our in-app toggle. Writing it here keeps the two in sync from
            // the *next* launch on; AppKit caches its already-built menu strings,
            // so an already-running window can't pick this up without a restart.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
    private let languageKey = "glyphline.language"

    /// 0.7...1.3, applied as a `.scaleEffect` on the whole window content.
    var uiScale: Double {
        didSet { UserDefaults.standard.set(uiScale, forKey: uiScaleKey) }
    }
    private let uiScaleKey = "glyphline.uiScale"

    var autoCheckUpdate: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckUpdate, forKey: autoCheckUpdateKey)
            sparkleUpdater?.automaticallyChecksForUpdates = autoCheckUpdate
        }
    }
    private let autoCheckUpdateKey = "glyphline.autoCheckUpdate"

    /// Set once by `GlyphlineApp` right after it creates the Sparkle updater
    /// controller, so this toggle (already wired into Settings and persisted
    /// above) drives Sparkle's own check-scheduling instead of a second,
    /// duplicate on/off switch living inside Sparkle's own defaults.
    var sparkleUpdater: SPUUpdater? {
        didSet { sparkleUpdater?.automaticallyChecksForUpdates = autoCheckUpdate }
    }

    /// Spelling language per column. Empty string = don't dictionary-check
    /// that column, which is the only correct setting for Japanese (macOS has
    /// no Japanese spelling dictionary — the notation-variant check still runs).
    var spellTextLanguage: String {
        didSet { UserDefaults.standard.set(spellTextLanguage, forKey: spellTextLanguageKey) }
    }
    var spellTranslationLanguage: String {
        didSet { UserDefaults.standard.set(spellTranslationLanguage, forKey: spellTranslationLanguageKey) }
    }
    var spellCheckNotation: Bool {
        didSet { UserDefaults.standard.set(spellCheckNotation, forKey: spellCheckNotationKey) }
    }

    /// How exported text is written. Set once per delivery target rather than
    /// asked on every export — people ship to one place at a time.
    var exportEncoding: String {
        didSet { UserDefaults.standard.set(exportEncoding, forKey: exportEncodingKey) }
    }
    var exportCRLF: Bool {
        didSet { UserDefaults.standard.set(exportCRLF, forKey: exportCRLFKey) }
    }
    var exportBOM: Bool {
        didSet { UserDefaults.standard.set(exportBOM, forKey: exportBOMKey) }
    }
    private let exportEncodingKey = "glyphline.exportEncoding"
    private let exportCRLFKey = "glyphline.exportCRLF"
    private let exportBOMKey = "glyphline.exportBOM"

    var textOutputOptions: TextOutputOptions {
        TextOutputOptions(encodingLabel: exportEncoding,
                          lineEnding: exportCRLF ? .crlf : .lf,
                          writeBOM: exportBOM)
    }

    /// Draw the broadcast title-safe / action-safe boxes over the video.
    /// Off by default: they're a checking aid, not something you want in the
    /// way while doing ordinary timing work.
    var showSafeGuides: Bool {
        didSet { UserDefaults.standard.set(showSafeGuides, forKey: showSafeGuidesKey) }
    }
    private let showSafeGuidesKey = "glyphline.showSafeGuides"

    /// User-saved delivery profiles (named QualityThresholds) — the DEFAULT/
    /// Netflix buttons already in Settings are fixed presets; this is where a
    /// house style for a specific client goes so switching between clients'
    /// requirements is a picker, not re-typing five numbers each time.
    private(set) var deliveryProfiles: [DeliveryProfile] = []
    private let deliveryProfilesKey = "glyphline.deliveryProfiles"

    func saveDeliveryProfile(name: String, thresholds: QualityThresholds) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        deliveryProfiles.removeAll { $0.name == trimmed } // overwrite same-named profile
        deliveryProfiles.append(DeliveryProfile(name: trimmed, thresholds: thresholds))
        persistDeliveryProfiles()
    }

    func deleteDeliveryProfile(name: String) {
        deliveryProfiles.removeAll { $0.name == name }
        persistDeliveryProfiles()
    }

    private func persistDeliveryProfiles() {
        guard let data = try? JSONEncoder().encode(deliveryProfiles) else { return }
        UserDefaults.standard.set(data, forKey: deliveryProfilesKey)
    }

    /// Saved house-style find/replace rule sets — see CustomRules.swift.
    var customRules: [CustomRule] {
        didSet { persistCustomRules() }
    }
    private let customRulesKey = "glyphline.customRules"
    private func persistCustomRules() {
        guard let data = try? JSONEncoder().encode(customRules) else { return }
        UserDefaults.standard.set(data, forKey: customRulesKey)
    }

    /// House-style term glossary shared across every document — unlike
    /// `doc.glossary` (see TermConsistency.swift), which is per-project and
    /// lives only in `.glyph`, this is a standing reference (character/brand
    /// names that recur across a whole series, say) that should be available
    /// from the moment a new file is opened, not re-typed per episode. See
    /// SharedGlossaryWindow.swift for the editor and TranslationCheckPanel
    /// for where it's merged into the per-document check.
    private(set) var sharedGlossary: [GlossaryEntry] = []
    private let sharedGlossaryKey = "glyphline.sharedGlossary"

    /// `language` defaults to nil (applies regardless of active translation
    /// language) — set it once a project targets more than one language,
    /// since a shared term's correct target is language-specific.
    func upsertSharedGlossaryEntry(source: String, target: String, note: String? = nil, language: String? = nil) {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let tgt = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !tgt.isEmpty else { return }
        let lang = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLang = (lang?.isEmpty ?? true) ? nil : lang
        var list = sharedGlossary
        list.removeAll { $0.source == src && $0.language == normalizedLang }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        list.append(GlossaryEntry(
            source: src, target: tgt, note: trimmedNote?.isEmpty == false ? trimmedNote : nil, language: normalizedLang))
        sharedGlossary = list.sorted { $0.source < $1.source }
        persistSharedGlossary()
    }

    func removeSharedGlossaryEntry(source: String, language: String? = nil) {
        sharedGlossary.removeAll { $0.source == source && $0.language == language }
        persistSharedGlossary()
    }

    private func persistSharedGlossary() {
        guard let data = try? JSONEncoder().encode(sharedGlossary) else { return }
        UserDefaults.standard.set(data, forKey: sharedGlossaryKey)
    }

    /// Spectrogram vs. amplitude waveform display — see SpectrogramRenderer.
    var showSpectrogram: Bool {
        didSet { UserDefaults.standard.set(showSpectrogram, forKey: showSpectrogramKey) }
    }
    private let showSpectrogramKey = "glyphline.showSpectrogram"

    /// Waveform zoom, 0–100 on a log scale (see WaveformScrollView). Persisted
    /// because it's a working preference — how densely you want to see the
    /// audio — not per-file state, and having it snap back to the default on
    /// every launch meant re-dialling it at the start of each session.
    var waveformZoom: Double {
        didSet { UserDefaults.standard.set(waveformZoom, forKey: waveformZoomKey) }
    }
    private let waveformZoomKey = "glyphline.waveformZoom"

    /// Show timecodes as HH:MM:SS:FF and snap edits to frame boundaries.
    /// Off by default: without a video loaded there's no rate to trust, and
    /// non-broadcast work is happier in seconds.
    var frameMode: Bool {
        didSet { UserDefaults.standard.set(frameMode, forKey: frameModeKey) }
    }
    /// Manual frame rate, used when nothing was detected from the video or the
    /// user needs to override it (e.g. timing against a 25fps deliverable while
    /// previewing a 23.976 screener). 0 = follow the video.
    var frameRateOverride: Double {
        didSet { UserDefaults.standard.set(frameRateOverride, forKey: frameRateOverrideKey) }
    }
    /// Whether the translation check includes the repeated-source scan.
    var checkDivergentTranslations: Bool {
        didSet { UserDefaults.standard.set(checkDivergentTranslations, forKey: checkDivergentKey) }
    }
    private let checkDivergentKey = "glyphline.checkDivergentTranslations"
    private let frameModeKey = "glyphline.frameMode"
    private let frameRateOverrideKey = "glyphline.frameRateOverride"

    /// The rate to actually time against: the user's override wins, else what
    /// mpv read from the file, else nil (no frame grid — callers fall back to
    /// seconds rather than inventing a rate).
    func effectiveFrameRate(detected: Double?) -> Double? {
        if frameRateOverride > 0 { return frameRateOverride }
        return detected
    }
    private let spellTextLanguageKey = "glyphline.spell.textLanguage"
    private let spellTranslationLanguageKey = "glyphline.spell.translationLanguage"
    private let spellCheckNotationKey = "glyphline.spell.checkNotation"
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
        // didSet above does NOT fire for this assignment (Swift suppresses
        // property observers for a property's own first assignment inside its
        // declaring type's initializer), so AppleLanguages would otherwise stay
        // unwritten on every launch except the one where the user actively
        // re-picks a language from the menu. Do it explicitly here too.
        UserDefaults.standard.set([resolvedLanguage.rawValue], forKey: "AppleLanguages")

        let savedScale = UserDefaults.standard.double(forKey: uiScaleKey)
        uiScale = savedScale > 0 ? savedScale : 1.0
        autoCheckUpdate = UserDefaults.standard.object(forKey: autoCheckUpdateKey) as? Bool ?? true

        // Default the translation column to the UI language when macOS can
        // actually check it, and leave the source column off — source text is
        // most often the language being translated FROM, frequently Japanese,
        // which has no dictionary.
        let defaultTranslation = SystemSpellDictionary.isSupported(resolvedLanguage.rawValue)
            ? resolvedLanguage.rawValue : ""
        spellTextLanguage = UserDefaults.standard.string(forKey: spellTextLanguageKey) ?? ""
        spellTranslationLanguage = UserDefaults.standard.string(forKey: spellTranslationLanguageKey) ?? defaultTranslation
        spellCheckNotation = UserDefaults.standard.object(forKey: spellCheckNotationKey) as? Bool ?? true
        waveformZoom = UserDefaults.standard.object(forKey: waveformZoomKey) as? Double ?? 50
        showCueEditor = UserDefaults.standard.object(forKey: showCueEditorKey) as? Bool ?? true
        exportEncoding = UserDefaults.standard.string(forKey: exportEncodingKey) ?? "utf-8"
        exportCRLF = UserDefaults.standard.object(forKey: exportCRLFKey) as? Bool ?? false
        exportBOM = UserDefaults.standard.object(forKey: exportBOMKey) as? Bool ?? false
        showSafeGuides = UserDefaults.standard.object(forKey: showSafeGuidesKey) as? Bool ?? false
        showSpectrogram = UserDefaults.standard.object(forKey: showSpectrogramKey) as? Bool ?? false
        if let data = UserDefaults.standard.data(forKey: deliveryProfilesKey),
           let decoded = try? JSONDecoder().decode([DeliveryProfile].self, from: data) {
            deliveryProfiles = decoded
        }
        if let data = UserDefaults.standard.data(forKey: customRulesKey),
           let decoded = try? JSONDecoder().decode([CustomRule].self, from: data) {
            customRules = decoded
        } else {
            customRules = []
        }
        if let data = UserDefaults.standard.data(forKey: sharedGlossaryKey),
           let decoded = try? JSONDecoder().decode([GlossaryEntry].self, from: data) {
            sharedGlossary = decoded
        }
        checkDivergentTranslations = UserDefaults.standard.object(forKey: checkDivergentKey) as? Bool ?? true
        frameMode = UserDefaults.standard.object(forKey: frameModeKey) as? Bool ?? false
        frameRateOverride = UserDefaults.standard.object(forKey: frameRateOverrideKey) as? Double ?? 0

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

    func moveDockPanel(_ panel: PanelKind, toZone zone: DropZone, ofTarget target: DockTarget) {
        dockLayout = movingPanel(panel, toZone: zone, ofTarget: target, in: dockLayout)
    }

    func selectDockTab(_ panel: PanelKind, tabsetPath: [Int]) {
        dockLayout = updatingSelection(at: tabsetPath, to: panel, in: dockLayout)
    }

    func setDockWeights(at path: [Int], to weights: [Double]) {
        dockLayout = updatingWeights(at: path, to: weights, in: dockLayout)
    }

    /// Which panels are currently in the layout.
    var visiblePanels: Set<PanelKind> { panelsInTree(dockLayout) }

    /// Shows or hides a panel.
    ///
    /// Hiding the last one is refused: an empty dock has no way back, since
    /// every route to un-hide a panel lives in a menu that acts on this tree.
    func togglePanel(_ panel: PanelKind) {
        if visiblePanels.contains(panel) {
            guard visiblePanels.count > 1, let next = removingPanel(panel, from: dockLayout) else { return }
            dockLayout = next
        } else {
            dockLayout = addingPanelAsTab(panel, into: dockLayout)
        }
    }

    /// Brings `panel` into view: adds it if hidden, then selects its tab so a
    /// menu command always ends with the panel actually on screen — not merely
    /// present behind a sibling tab.
    func revealPanel(_ panel: PanelKind) {
        if !visiblePanels.contains(panel) {
            dockLayout = addingPanelAsTab(panel, into: dockLayout)
        }
        guard let path = pathToTabset(containing: panel, in: dockLayout) else { return }
        dockLayout = updatingSelection(at: path, to: panel, in: dockLayout)
    }

    func resetDockLayout() {
        dockLayout = .defaultLayout
    }

    private func persistDockLayout() {
        guard let data = try? JSONEncoder().encode(dockLayout) else { return }
        UserDefaults.standard.set(data, forKey: dockLayoutKey)
    }
}

/// A named quality-threshold set the user saved for a specific client/show —
/// see AppSettings.deliveryProfiles.
struct DeliveryProfile: Codable, Equatable, Identifiable {
    var name: String
    var thresholds: QualityThresholds
    var id: String { name }
}
