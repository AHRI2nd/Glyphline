// Silence-based auto-spotting: lays down blank cue timing over detected
// speech, so timing a file from scratch starts from "here's where someone
// talks" instead of a blank grid. See AutoSpotting.swift for the algorithm
// and why it's a threshold, not a speech model.

import SwiftUI
import GlyphlineCore

struct AutoSpotPanel: View {
    let document: DocumentModel
    let media: MediaModel
    @Environment(\.dismiss) private var dismiss

    @State private var thresholdDb = "-35"
    @State private var minSilenceMs = "300"
    @State private var minSpeechMs = "200"
    @State private var paddingMs = "100"
    @State private var addedCount: Int?

    private var preview: [SpeechSegment] {
        guard let audio = media.waveformAudio else { return [] }
        return detectSpeechSegments(
            samples: audio.samples, sampleRate: audio.sampleRate,
            thresholdDb: Double(thresholdDb) ?? -35,
            minSilenceSec: max(0, (Double(minSilenceMs) ?? 0)) / 1000,
            minSpeechSec: max(0, (Double(minSpeechMs) ?? 0)) / 1000,
            paddingSec: max(0, (Double(paddingMs) ?? 0)) / 1000
        )
    }

    var body: some View {
        PanelShell(title: t("autoSpot"), width: 420) {
            VStack(alignment: .leading, spacing: 12) {
                if media.waveformAudio == nil {
                    Text(t("autoSpotNeedsWaveform"))
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.amber)
                } else {
                    Text(t("autoSpotHint"))
                        .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)

                    field(t("autoSpotThreshold"), $thresholdDb, "dB")
                    field(t("autoSpotMinSilence"), $minSilenceMs, "ms")
                    field(t("autoSpotMinSpeech"), $minSpeechMs, "ms")
                    field(t("autoSpotPadding"), $paddingMs, "ms")

                    Divider()
                    Text(t("autoSpotPreviewCount", "\(preview.count)"))
                        .font(GlyphFont.data(11))
                        .foregroundStyle(preview.isEmpty ? GlyphColor.quiet : GlyphColor.signal)

                    if let addedCount {
                        Text(t("autoSpotAdded", "\(addedCount)"))
                            .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.good)
                    }
                }
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("autoSpotApply")) {
                addedCount = document.addCuesFromSpeechSegments(preview)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(GlyphColor.accent)
            .disabled(preview.isEmpty)
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ suffix: String) -> some View {
        HStack {
            Text(label).font(GlyphFont.body(12))
            Spacer()
            NumberField(label: "", value: value, suffix: suffix, width: 60)
        }
    }
}
