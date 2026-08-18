// Quit-time unsaved-changes guard (ported from ../../../src/App.tsx's
// CloseConfirmModal, triggered via Tauri's onCloseRequested).
//
// Presented as a real SwiftUI sheet (CloseConfirmPanel), same pattern as every
// other M5/M6 panel — `applicationShouldTerminate` returns `.terminateLater`
// and the panel's buttons call `NSApp.reply(toApplicationShouldTerminate:)`
// once the user decides, which is AppKit's documented mechanism for exactly
// this "confirm before quitting asynchronously" case.

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
        // Checks every open tab, not just the active one — with multiple
        // documents open, unsaved work in a background tab is just as real
        // as unsaved work in the front one.
        guard let state, state.anyTabDirty else { return .terminateNow }
        state.activePanel = .closeConfirm(tabToClose: nil)
        return .terminateLater
    }
}
