// General settings + quality-check thresholds + mpv status (ported from
// ../../../src/components/Settings/SettingsModal.tsx).

import SwiftUI
import GlyphlineCore

struct SettingsPanel: View {
    let settings: AppSettings
    let media: MediaModel
    let document: DocumentModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSaveProfile = false
    @State private var newProfileName = ""

    /// Frame rate section: the picker sets an override, and the line under it
    /// says what's actually in force — otherwise "From video" gives no way to
    /// tell whether anything was detected at all.
    @ViewBuilder
    private var frameRateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t("frameRate")).font(GlyphFont.body(12))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.frameRateOverride },
                    set: { settings.frameRateOverride = $0 }
                )) {
                    Text(t("frameRateAuto")).tag(0.0)
                    ForEach(COMMON_FRAME_RATES, id: \.self) { fps in
                        Text(frameRateLabel(fps)).tag(fps)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            if settings.frameRateOverride == 0 {
                if let detected = media.detectedFrameRate {
                    Text(t("frameRateDetected", frameRateLabel(detected)))
                        .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                } else {
                    Text(t("frameRateNone"))
                        .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.amber)
                }
            }
            Text(t("frameRateHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

            Divider().padding(.vertical, 2)
            broadcastTimecodeControls
        }
    }

    /// Per-document, not app-wide (see DropFrameTimecode.swift) — every
    /// broadcast master this project touches may want a different house start.
    @ViewBuilder
    private var broadcastTimecodeControls: some View {
        let fps = settings.effectiveFrameRate(detected: media.detectedFrameRate)
        HStack {
            Text(t("tcStartOffset")).font(GlyphFont.body(12))
            Spacer()
            TextField("00:00:00:00", text: Binding(
                get: {
                    guard let fps else { return formatDisplayTime(document.doc.timecodeStartOffsetSec) }
                    return formatFrameTimecode(document.doc.timecodeStartOffsetSec, fps: fps)
                },
                set: { text in
                    let v = fps.flatMap { parseFrameTimecode(text, fps: $0) } ?? parseTimestampInput(text)
                    if let v { document.setTimecodeStartOffsetSec(v) }
                }
            ))
            .font(GlyphFont.data(12)).textFieldStyle(.roundedBorder).frame(width: 110)
        }
        Toggle(t("tcDropFrame"), isOn: Binding(
            get: { document.doc.timecodeDropFrame },
            set: { document.setTimecodeDropFrame($0) }
        ))
        .toggleStyle(.checkbox).font(GlyphFont.body(12))
        .disabled(!(fps.map(isDropFrameCandidate) ?? false))
        Text(fps.map(isDropFrameCandidate) == true ? t("tcDropFrameHint") : t("tcDropFrameUnavailable"))
            .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
    }

    /// Delivery-format options. Grouped because they're chosen together for a
    /// target ("this client wants CP949 + CRLF") rather than one at a time.
    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("outputOptions")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            HStack {
                Text(t("exportEncoding")).font(GlyphFont.body(12))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.exportEncoding }, set: { settings.exportEncoding = $0 }
                )) {
                    ForEach(TextEncoding.selectableLabels, id: \.self) { label in
                        Text(TextEncoding.displayName(forLabel: label)).tag(label)
                    }
                }
                .labelsHidden().frame(width: 150)
            }
            Toggle(t("exportCRLF"), isOn: Binding(
                get: { settings.exportCRLF }, set: { settings.exportCRLF = $0 }
            )).toggleStyle(.checkbox).font(GlyphFont.body(12))
            Toggle(t("exportBOM"), isOn: Binding(
                get: { settings.exportBOM }, set: { settings.exportBOM = $0 }
            )).toggleStyle(.checkbox).font(GlyphFont.body(12))
            Text(t("outputOptionsHint"))
                .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
        }
    }

    var body: some View {
        PanelShell(title: t("settings"), width: 380) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t("uiScale")).font(GlyphFont.body(12))
                        Slider(value: Binding(
                            get: { settings.uiScale }, set: { settings.uiScale = $0 }
                        ), in: 0.7...1.3, step: 0.05)
                        .tint(GlyphColor.accentHover)
                        Text("\(Int(settings.uiScale * 100))%")
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle(t("autoCheckUpdate"), isOn: Binding(
                        get: { settings.autoCheckUpdate }, set: { settings.autoCheckUpdate = $0 }
                    )).toggleStyle(.checkbox).font(GlyphFont.body(12))
                    if let version = settings.availableUpdateVersion {
                        Text("\(t("updateAvailable")): \(version)")
                            .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.accent)
                    }
                }

                Divider()

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
                    deliveryProfileControls
                }

                Divider()
                outputSection
                Divider()
                frameRateSection
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("mediaEngine")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
                    HStack(spacing: 6) {
                        Circle().fill(MPVLibrary.isAvailable ? GlyphColor.good : GlyphColor.warn).frame(width: 8, height: 8)
                        Text(MPVLibrary.isAvailable ? t("mpvInstalled") : t("mpvMissing"))
                            .font(GlyphFont.body(12))
                    }
                    // The install command moved out of mpvMissing (it was being
                    // printed twice in the video pane's empty state, which pairs
                    // that title with mpvMissingDesc) — show it here instead, so
                    // Settings still answers "then how do I install it?".
                    if !MPVLibrary.isAvailable {
                        Text(t("mpvMissingDesc"))
                            .font(GlyphFont.body(11))
                            .foregroundStyle(GlyphColor.quiet)
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    /// Save the CURRENT threshold values (whatever's in the fields above,
    /// including manual tweaks) under a client/show name, and switch between
    /// saved ones — the picker only needs a name; the numbers ride along.
    @ViewBuilder
    private var deliveryProfileControls: some View {
        HStack {
            Picker(t("deliveryProfile"), selection: Binding(
                get: { "" },
                set: { name in
                    guard let profile = settings.deliveryProfiles.first(where: { $0.name == name }) else { return }
                    settings.quality = profile.thresholds
                }
            )) {
                Text(t("deliveryProfileChoose")).tag("")
                ForEach(settings.deliveryProfiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            .labelsHidden().frame(width: 140)
            Button(t("deliveryProfileSave")) { showingSaveProfile = true }.controlSize(.small)
            if !settings.deliveryProfiles.isEmpty {
                Menu(t("deliveryProfileDelete")) {
                    ForEach(settings.deliveryProfiles) { profile in
                        Button(profile.name) { settings.deleteDeliveryProfile(name: profile.name) }
                    }
                }
                .menuStyle(.borderlessButton).frame(width: 90).controlSize(.small)
            }
        }
        .popover(isPresented: $showingSaveProfile) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("deliveryProfileSavePrompt")).font(GlyphFont.body(12))
                TextField(t("deliveryProfileName"), text: $newProfileName)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                HStack {
                    Spacer()
                    Button(t("save")) {
                        settings.saveDeliveryProfile(name: newProfileName, thresholds: settings.quality)
                        newProfileName = ""
                        showingSaveProfile = false
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
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
