// Unsaved-changes confirmation — shared by quit (ported from
// ../../../src/components/Modals/SafetyModals.tsx's CloseConfirmModal) and by
// closing a single dirty tab, which used to get a bare NSAlert with no save
// option at all (see DocumentTabs.swift's old closeTab).
//
// A proper SwiftUI sheet like every other M5/M6 panel — for the quit case,
// made possible by AppDelegate returning `.terminateLater` from
// `applicationShouldTerminate` and replying asynchronously via
// `NSApp.reply(toApplicationShouldTerminate:)` once one of these buttons
// resolves the decision, instead of a blocking `NSAlert` (SwiftUI sheets
// can't synchronously block quit, but `.terminateLater` exists precisely for
// that). The tab-close case has no such constraint — it just resolves directly.

import SwiftUI
import AppKit

struct CloseConfirmPanel: View {
    let state: AppState
    /// nil = quitting the app; a tab id = closing just that one tab (see
    /// ActivePanel.closeConfirm).
    let tabToClose: UUID?
    @Environment(\.dismiss) private var dismiss

    private var tabName: String? {
        guard let tabToClose else { return nil }
        if tabToClose == state.activeTabId { return state.document.fileName }
        return state.tabs.first { $0.id == tabToClose }?.fileName
    }

    var body: some View {
        PanelShell(title: t("unsavedChangesTitle"), width: 380) {
            Text(tabName.map { t("closeTabUnsavedMessage", $0) } ?? t("closeUnsavedMessage"))
                .font(GlyphFont.body(12))
        } footer: {
            Button(t("cancel")) { cancel() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button(t("closeWithoutSaving")) { discardAndClose() }
            Button(t("saveAndClose")) { saveAndClose() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
    }

    private func cancel() {
        dismiss()
        if tabToClose == nil { NSApp.reply(toApplicationShouldTerminate: false) }
    }

    private func discardAndClose() {
        dismiss()
        if let tabToClose {
            AutosaveService.clearGroup(tabId: tabToClose)
            state.forceCloseTab(tabToClose)
        } else {
            AutosaveService.clear()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func saveAndClose() {
        dismiss()
        guard let tabToClose else {
            // Quit flow: every dirty tab, not just the active one —
            // quitting with an unsaved background tab used to lose that
            // tab's changes with no warning, since only the foreground
            // document ever got written.
            if state.saveAllTabs() {
                AutosaveService.clear()
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.reply(toApplicationShouldTerminate: false) // a Save As somewhere was cancelled
            }
            return
        }
        // Closing one specific (possibly background) tab: switch to it to
        // save (only the active DocumentModel can be written — see
        // DocumentTabs.swift), then switch back before removing it so the
        // user doesn't see their view jump to the tab they just closed.
        let originalActive = state.activeTabId
        if tabToClose != originalActive { state.switchToTab(tabToClose) }
        guard state.saveDocument() else { return } // Save As cancelled — leave the tab open, dirty
        AutosaveService.clearGroup(tabId: tabToClose)
        if tabToClose != originalActive, state.tabs.contains(where: { $0.id == originalActive }) {
            state.switchToTab(originalActive)
        }
        state.forceCloseTab(tabToClose)
    }
}
