// Quit-time unsaved-changes confirmation (ported from
// ../../../src/components/Modals/SafetyModals.tsx's CloseConfirmModal).
//
// A proper SwiftUI sheet like every other M5/M6 panel — made possible by
// AppDelegate returning `.terminateLater` from `applicationShouldTerminate`
// and replying asynchronously via `NSApp.reply(toApplicationShouldTerminate:)`
// once one of these buttons resolves the decision, instead of the blocking
// `NSAlert` this replaces (SwiftUI sheets can't synchronously block quit, but
// `.terminateLater` exists precisely for that).

import SwiftUI
import AppKit

struct CloseConfirmPanel: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PanelShell(title: t("unsavedChangesTitle"), width: 380) {
            Text(t("closeUnsavedMessage"))
                .font(GlyphFont.body(12))
        } footer: {
            Button(t("cancel")) { resolve(false) }.keyboardShortcut(.cancelAction)
            Spacer()
            Button(t("closeWithoutSaving")) {
                AutosaveService.clear()
                resolve(true)
            }
            Button(t("saveAndClose")) {
                // Every dirty tab, not just the active one — quitting with an
                // unsaved background tab used to lose that tab's changes
                // with no warning, since only the foreground document ever
                // got written.
                if state.saveAllTabs() {
                    AutosaveService.clear()
                    resolve(true)
                } else {
                    resolve(false) // a Save As somewhere was cancelled — don't quit
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(GlyphColor.accent)
        }
    }

    private func resolve(_ shouldTerminate: Bool) {
        dismiss()
        NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
