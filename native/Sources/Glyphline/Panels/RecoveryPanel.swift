// Offered at startup when a crash-recovery autosave exists (ported from
// ../../../src/components/Modals/SafetyModals.tsx's RecoveryModal).

import SwiftUI

struct RecoveryPanel: View {
    let data: AutosaveData
    /// Older snapshots, newest first. Autosave keeps a rolling set so a bad
    /// edit that got autosaved doesn't destroy the good version — the point of
    /// listing them is being able to step back past it.
    let older: [AutosaveData]
    let onRestore: (AutosaveData) -> Void
    let onDiscard: () -> Void

    @State private var selected: Date?

    private var chosen: AutosaveData {
        guard let selected else { return data }
        return ([data] + older).first { $0.savedAt == selected } ?? data
    }

    private static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        PanelShell(title: t("recoveryTitle"), width: 420) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("recoveryMessage")).font(GlyphFont.body(12))

                if older.isEmpty {
                    Text("\(data.fileName ?? t("recoveryUntitled")) · \(Self.when(data.savedAt))")
                        .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                } else {
                    Text(t("recoveryPickHint"))
                        .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                    ForEach([data] + older) { snapshot in
                        let isChosen = snapshot.savedAt == chosen.savedAt
                        Button {
                            selected = snapshot.savedAt
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isChosen ? GlyphColor.accent : GlyphColor.quiet)
                                Text(Self.when(snapshot.savedAt)).font(GlyphFont.data(11))
                                Text(snapshot.fileName ?? t("recoveryUntitled"))
                                    .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("recoveryDiscard")) { onDiscard() }
            Button(t("recoveryRestore")) { onRestore(chosen) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
        }
    }
}
