// Quit-time unsaved-changes guard (ported from ../../../src/App.tsx's
// CloseConfirmModal, triggered via Tauri's onCloseRequested). SwiftUI's
// WindowGroup doesn't expose a way to block termination directly, so this uses
// the standard AppKit pattern: NSApplicationDelegate.applicationShouldTerminate,
// which can synchronously block quit with a blocking NSAlert.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    /// Glyphline's palette (zinc/indigo) is a fixed dark theme, not adaptive —
    /// same as the original Tauri build. Force dark appearance app-wide so
    /// AppKit-level system colors (NSColor.labelColor in CueGridCoordinator,
    /// native control chrome, sheets) resolve to their dark variants regardless
    /// of the system's Light/Dark setting; SwiftUI views get the same via
    /// `.preferredColorScheme(.dark)` in ContentView.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.document.isDirty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = t("unsavedChangesTitle")
        alert.informativeText = t("closeUnsavedMessage")
        alert.addButton(withTitle: t("saveAndClose"))
        alert.addButton(withTitle: t("closeWithoutSaving"))
        alert.addButton(withTitle: t("cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn: // save & close
            if state.saveDocument() {
                AutosaveService.clear()
                return .terminateNow
            }
            return .terminateCancel // save was cancelled (e.g. no path chosen)
        case .alertSecondButtonReturn: // close without saving
            AutosaveService.clear()
            return .terminateNow
        default: // cancel
            return .terminateCancel
        }
    }
}
