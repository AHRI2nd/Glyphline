// Quality-check thresholds + mpv status (ported from
// ../../../src/components/Settings/SettingsModal.tsx). Full settings persistence
// (uiScale, autoCheckUpdate, recentFiles…) is M6 scope; this covers the
// self-contained quality-threshold piece.

import SwiftUI
import GlyphlineCore

struct SettingsPanel: View {
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PanelShell(title: t("settings"), width: 380) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t("qualityThresholds")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                        Spacer()
                        Button(t("qPresetDefault")) { settings.quality = DEFAULT_THRESHOLDS }.controlSize(.small)
                        Button(t("qPresetNetflix")) { settings.quality = NETFLIX_THRESHOLDS }.controlSize(.small)
                    }
                    thresholdField(t("qMaxCps"), value: Binding(
                        get: { settings.quality.maxCps }, set: { settings.quality.maxCps = $0 }))
                    thresholdField(t("qMinDuration"), value: Binding(
                        get: { settings.quality.minDuration }, set: { settings.quality.minDuration = $0 }))
                    thresholdField(t("qMaxDuration"), value: Binding(
                        get: { settings.quality.maxDuration }, set: { settings.quality.maxDuration = $0 }))
                    thresholdIntField(t("qMaxLineLength"), value: Binding(
                        get: { settings.quality.maxLineLength }, set: { settings.quality.maxLineLength = $0 }))
                    thresholdIntField(t("qMaxLines"), value: Binding(
                        get: { settings.quality.maxLines }, set: { settings.quality.maxLines = $0 }))
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("mediaEngine")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                    HStack(spacing: 6) {
                        Circle().fill(MPVLibrary.isAvailable ? GlyphColor.good : GlyphColor.warn).frame(width: 8, height: 8)
                        Text(MPVLibrary.isAvailable ? t("mpvInstalled") : t("mpvMissing"))
                            .font(GlyphFont.body(12))
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func thresholdField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(GlyphFont.body(12))
            Spacer()
            TextField("", value: value, format: .number)
                .font(GlyphFont.data(12)).multilineTextAlignment(.trailing)
                .frame(width: 60).textFieldStyle(.roundedBorder)
        }
    }
    private func thresholdIntField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(GlyphFont.body(12))
            Spacer()
            TextField("", value: value, format: .number)
                .font(GlyphFont.data(12)).multilineTextAlignment(.trailing)
                .frame(width: 60).textFieldStyle(.roundedBorder)
        }
    }
}
