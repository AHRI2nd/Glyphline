// Runs the whole delivery pipeline (DeliveryPipelineRunner.swift) against a
// scanned folder: multi-format export + burn-in review video + QC report +
// font collection, per subtitle/video pair, into one client-ready output
// tree with a manifest. Structured after BatchConvertPanel.swift (the
// closest existing precedent — folder scan, cleanup toggles, encoding
// options, collision-safe naming, BackgroundJob registration) with three
// additions: video pairing, a multi-format selector instead of one Picker,
// and the burn-in/QC/font feature toggles.

import SwiftUI
import UniformTypeIdentifiers
import GlyphlineCore

struct DeliveryPipelinePanel: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    private struct ItemRow: Identifiable {
        let id = UUID()
        let item: DeliveryManifestItem
    }

    @State private var pairs: [SubtitleVideoPair] = []
    @State private var outputFolder: String?
    @State private var formats: Set<SubFormat> = [.srt]
    @State private var fixOverlaps = true
    @State private var removeEmpty = false
    @State private var encodingLabel = "utf-8"
    @State private var crlf = false
    @State private var bom = false
    @State private var burnInEnabled = false
    @State private var qcEnabled = true
    @State private var fontsEnabled = false
    @State private var selectedProfileName = ""
    @State private var isProcessing = false
    @State private var results: [ItemRow] = []

    var body: some View {
        PanelShell(title: t("deliveryPipeline"), width: 520) {
            VStack(alignment: .leading, spacing: 12) {
                inputSection
                Divider()
                formatSection
                Divider()
                cleanupSection
                Divider()
                featuresSection
                if !results.isEmpty {
                    Divider()
                    resultsSection
                }
            }
        } footer: {
            Spacer()
            Button(t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(t("deliveryPipelineRun")) { run() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
                .disabled(pairs.isEmpty || outputFolder == nil || formats.isEmpty || isProcessing)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("deliveryPipelineInput")).font(GlyphFont.body(12))
                Spacer()
                Text(pairs.isEmpty ? t("batchConvertNoFiles") : pairSummary)
                    .font(GlyphFont.data(11))
                    .foregroundStyle(pairs.isEmpty ? GlyphColor.amber : GlyphColor.quiet)
                Button(t("deliveryPipelineChooseFolder")) { chooseFolder() }.controlSize(.small)
            }
            HStack {
                Text(t("deliveryPipelineOutputFolder")).font(GlyphFont.body(12))
                Spacer()
                Text(outputFolder.map { ($0 as NSString).lastPathComponent } ?? t("deliveryPipelineNoOutput"))
                    .font(GlyphFont.data(11)).foregroundStyle(outputFolder == nil ? GlyphColor.amber : GlyphColor.quiet)
                    .lineLimit(1)
                Button(t("choose")) { chooseOutputFolder() }.controlSize(.small)
            }
        }
    }

    private var pairSummary: String {
        let paired = pairs.filter { $0.videoPath != nil }.count
        return t("deliveryPipelinePairCount", "\(pairs.count)", "\(paired)")
    }

    @ViewBuilder
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("deliveryPipelineFormats")).font(GlyphFont.body(12))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(SubFormat.allCases, id: \.self) { format in
                    Toggle(format.rawValue.uppercased(), isOn: Binding(
                        get: { formats.contains(format) },
                        set: { on in if on { formats.insert(format) } else { formats.remove(format) } }
                    ))
                    .toggleStyle(.checkbox).font(GlyphFont.body(11))
                }
            }
            if !formats.subtracting([.stl, .scc]).isEmpty {
                HStack {
                    Text(t("exportEncoding")).font(GlyphFont.body(12))
                    Spacer()
                    Picker("", selection: $encodingLabel) {
                        ForEach(TextEncoding.selectableLabels, id: \.self) { label in
                            Text(TextEncoding.displayName(forLabel: label)).tag(label)
                        }
                    }
                    .labelsHidden().frame(width: 150)
                }
                Toggle(t("exportCRLF"), isOn: $crlf).toggleStyle(.checkbox).font(GlyphFont.body(12))
                Toggle(t("exportBOM"), isOn: $bom).toggleStyle(.checkbox).font(GlyphFont.body(12))
            }
        }
    }

    @ViewBuilder
    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("batchConvertCleanup")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            Toggle(t("fixOverlaps"), isOn: $fixOverlaps).toggleStyle(.checkbox).font(GlyphFont.body(12))
            Toggle(t("removeEmptyCues"), isOn: $removeEmpty).toggleStyle(.checkbox).font(GlyphFont.body(12))
        }
    }

    @ViewBuilder
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("deliveryPipelineFeatures")).font(GlyphFont.display(11)).foregroundStyle(GlyphColor.quiet)
            Toggle(t("deliveryPipelineBurnIn"), isOn: $burnInEnabled).toggleStyle(.checkbox).font(GlyphFont.body(12))
            if burnInEnabled, !BurnInEncoder.ffmpegAvailable {
                Text(t("ffmpegMissing")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.amber)
            }
            HStack(spacing: 8) {
                Toggle(t("deliveryPipelineQC"), isOn: $qcEnabled).toggleStyle(.checkbox).font(GlyphFont.body(12))
                if qcEnabled {
                    Picker("", selection: $selectedProfileName) {
                        Text(t("deliveryProfileChoose")).tag("")
                        ForEach(state.settings.deliveryProfiles) { profile in
                            Text(profile.name).tag(profile.name)
                        }
                    }
                    .labelsHidden().frame(width: 130).controlSize(.small)
                }
            }
            Toggle(t("deliveryPipelineFonts"), isOn: $fontsEnabled).toggleStyle(.checkbox).font(GlyphFont.body(12))
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let failures = results.filter { $0.item.fatalError != nil }
        VStack(alignment: .leading, spacing: 4) {
            Text(t("deliveryPipelineResult", "\(results.count - failures.count)", "\(results.count)"))
                .font(GlyphFont.data(11))
                .foregroundStyle(failures.isEmpty ? GlyphColor.good : GlyphColor.amber)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { row in DeliveryResultRow(item: row.item) }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    // MARK: - File pickers

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let knownSubs = Set(openExtensions())
        var subtitlePaths: [String] = []
        var allPaths: [String] = []
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            allPaths.append(item.path)
            if knownSubs.contains(extensionOf(item.path)) { subtitlePaths.append(item.path) }
        }
        pairs = pairSubtitlesWithVideos(subtitlePaths: subtitlePaths.sorted(), candidatePaths: allPaths, mediaExts: MEDIA_EXTS)
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url.path
    }

    // MARK: - Run

    private func run() {
        guard let outputFolder else { return }
        isProcessing = true
        results = []
        let qcThresholds = state.settings.deliveryProfiles.first { $0.name == selectedProfileName }?.thresholds ?? state.settings.quality
        let config = DeliveryPipelineConfig(
            items: pairs, outputRoot: outputFolder, formats: SubFormat.allCases.filter { formats.contains($0) },
            fixOverlaps: fixOverlaps, removeEmpty: removeEmpty, encodingLabel: encodingLabel, crlf: crlf, bom: bom,
            burnInEnabled: burnInEnabled, qcEnabled: qcEnabled, qcThresholds: qcThresholds, fontsEnabled: fontsEnabled
        )
        Task {
            _ = await DeliveryPipelineRunner.run(config: config, state: state) { item in
                results.append(ItemRow(item: item))
            }
            isProcessing = false
        }
    }
}

private struct DeliveryResultRow: View {
    let item: DeliveryManifestItem

    var body: some View {
        HStack(spacing: 6) {
            if let fatalError = item.fatalError {
                Image(systemName: "xmark").foregroundStyle(GlyphColor.warn)
                Text(item.baseName).font(GlyphFont.body(11)).lineLimit(1)
                Text(fatalError).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet).lineLimit(1)
            } else {
                Image(systemName: "checkmark").foregroundStyle(GlyphColor.good)
                Text(item.baseName).font(GlyphFont.body(11)).lineLimit(1)
                Text(detailSummary).font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet).lineLimit(1)
            }
        }
    }

    private var detailSummary: String {
        var parts = ["\(item.formatsWritten.count)f"]
        switch item.burnIn {
        case .succeeded: parts.append("burn✓")
        case .failed: parts.append("burn✗")
        case .skippedNoVideo, .skippedFFmpegMissing: parts.append("burn–")
        case nil: break
        }
        if let qc = item.qc { parts.append("qc:\(qc.issueCount)") }
        if let fonts = item.fonts, !fonts.notFound.isEmpty { parts.append("font gaps:\(fonts.notFound.count)") }
        return parts.joined(separator: " ")
    }
}
