// Undo history as a list you can jump into.
//
// ⌘Z alone means stepping back blind: you press it until things look right and
// overshoot, and the only way back is redo, pressed just as blindly. A list
// lets you pick the point instead of feeling for it.
//
// Each row shows only its cue count. History holds whole-document snapshots,
// so naming what changed at each step would mean diffing every adjacent pair —
// and a label that guesses wrong is worse than one that just says how big the
// document was.

import SwiftUI
import GlyphlineCore

struct HistoryPanel: View {
    let document: DocumentModel

    var body: some View {
        PanelShell(title: t("historyPanel"), width: 320) {
            let entries = document.historyEntries
            VStack(alignment: .leading, spacing: 2) {
                Text(t("historyHint")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                    .padding(.bottom, 4)
                // Newest first: the step you want is nearly always a recent one.
                ForEach(entries.reversed()) { entry in
                    Button {
                        document.jumpToHistory(stepsBack: entry.stepsBack)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.isCurrent ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(entry.isCurrent ? GlyphColor.signalLight : GlyphColor.quiet)
                            Text(entry.isCurrent ? t("historyCurrent") : t("historyStepsBack", "\(entry.stepsBack)"))
                                .font(GlyphFont.body(11))
                                .foregroundStyle(entry.isCurrent ? GlyphColor.ink : GlyphColor.quiet)
                            Spacer()
                            Text(t("historyCueCount", "\(entry.cueCount)"))
                                .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isCurrent)
                }
            }
        } footer: {
            Spacer()
            PanelCloseButton()
        }
    }
}
