// Orchestrates the delivery pipeline: per subtitle/video pair, cleanup →
// multi-format export → burn-in review video → QC report → font collection
// → one manifest entry — reusing BurnInEncoder, QCReport, FontCollector, and
// SubtitleFileIO exactly as their existing single-file callers do. The whole
// run registers as ONE BackgroundJob (see BackgroundJobs.swift) so its
// progress survives the panel being closed, same as BatchConvertPanel/
// BurnInPanel already do.
//
// Every step past "open the subtitle file" is non-fatal per item: a missing
// paired video only skips burn-in for THAT item, a missing font only shows
// up in that item's manifest entry, and so on — the whole point of a folder-
// wide batch is that one bad file shouldn't stop the other 40 from shipping.
// The one genuinely fatal case is the subtitle itself failing to parse, since
// there's no DocumentModel to do anything else with.

import Foundation
import GlyphlineCore

struct DeliveryPipelineConfig {
    var items: [SubtitleVideoPair]
    var outputRoot: String
    var formats: [SubFormat]
    var fixOverlaps: Bool
    var removeEmpty: Bool
    var encodingLabel: String
    var crlf: Bool
    var bom: Bool
    var burnInEnabled: Bool
    var qcEnabled: Bool
    var qcThresholds: QualityThresholds
    var fontsEnabled: Bool
}

@MainActor
enum DeliveryPipelineRunner {
    /// Runs the whole pipeline as one background job, calling
    /// `onItemFinished` as each item completes so the panel can show live
    /// progress instead of one dump at the very end (burn-in alone can take
    /// tens of seconds per item).
    static func run(
        config: DeliveryPipelineConfig,
        state: AppState,
        onItemFinished: @escaping (DeliveryManifestItem) -> Void
    ) async -> DeliveryManifest {
        guard !config.items.isEmpty else {
            return buildDeliveryManifest(items: [], outputRoot: config.outputRoot)
        }

        let jobId = state.startBackgroundJob(t("deliveryPipeline") + ": \(config.items.count)")
        var usedFolderPaths = Set<String>()
        var manifestItems: [DeliveryManifestItem] = []
        let totalWeight = Double(config.items.count) * stepWeightTotal(config)

        for (index, pair) in config.items.enumerated() {
            // Checked BEFORE starting a new item, not after — an item
            // already in flight (its burn-in in particular) still runs to
            // whatever outcome it reaches on its own; see runOne/runBurnIn,
            // which observe cancellation via BurnInEncoder's own
            // withTaskCancellationHandler and report a clean per-item
            // outcome instead of just vanishing mid-manifest.
            if Task.isCancelled { break }
            let item = await runOne(
                pair, config: config, usedFolderPaths: &usedFolderPaths,
                onProgress: { fraction in
                    let done = Double(index) * stepWeightTotal(config) + fraction * stepWeightTotal(config)
                    state.updateBackgroundJob(jobId, progress: totalWeight > 0 ? done / totalWeight : nil)
                }
            )
            manifestItems.append(item)
            onItemFinished(item)
        }

        let manifest = buildDeliveryManifest(items: manifestItems, outputRoot: config.outputRoot)
        let manifestWritten = writeManifestFiles(manifest, to: config.outputRoot)

        let cancelled = Task.isCancelled
        let failureCount = manifestItems.filter { $0.fatalError != nil }.count
        var message = cancelled ? t("operationCancelled")
            : t("deliveryPipelineResult", "\(manifestItems.count - failureCount)", "\(manifestItems.count)")
        // Every item can have succeeded and this can still fail (a full disk,
        // say) — worth surfacing rather than silently omitting the manifest
        // from an otherwise-complete delivery folder.
        if !manifestWritten { message += " — " + t("deliveryPipelineManifestWriteFailed") }
        state.finishBackgroundJob(jobId, success: !cancelled && failureCount == 0 && manifestWritten, message: message)
        return manifest
    }

    /// Weighted so overall progress reflects wall-clock time rather than raw
    /// step count — burn-in (an ffmpeg encode) dominates a run's duration
    /// when it's on, so it gets most of the weight; export/QC/fonts are
    /// near-instant local I/O and just jump their slice on completion.
    private static func stepWeightTotal(_ config: DeliveryPipelineConfig) -> Double {
        var total = 1.0 // export + cleanup, always present
        if config.burnInEnabled { total += 6 }
        if config.qcEnabled { total += 0.5 }
        if config.fontsEnabled { total += 0.5 }
        return total
    }

    private static func runOne(
        _ pair: SubtitleVideoPair, config: DeliveryPipelineConfig,
        usedFolderPaths: inout Set<String>, onProgress: @escaping (Double) -> Void
    ) async -> DeliveryManifestItem {
        let sourceBase = (pair.subtitlePath as NSString).lastPathComponent
        let base = (sourceBase as NSString).deletingPathExtension
        let weights = stepWeightTotal(config)
        var doneWeight = 0.0
        func reportStepDone(_ weight: Double) {
            doneWeight += weight
            onProgress(min(1, doneWeight / weights))
        }

        let doc = DocumentModel()
        do {
            let parsed = try SubtitleFileIO.open(path: pair.subtitlePath)
            doc.loadParsed(parsed)
        } catch {
            return DeliveryManifestItem(
                baseName: base, sourceSubtitlePath: pair.subtitlePath, pairedVideoPath: pair.videoPath,
                fatalError: String(describing: error))
        }
        if config.fixOverlaps { doc.fixOverlaps() }
        if config.removeEmpty { doc.removeEmptyCues() }

        let itemDir = GlyphlineCore.uniqueDestPath(
            dir: config.outputRoot, base: base, ext: "", sourcePath: pair.subtitlePath, used: &usedFolderPaths)
        try? FileManager.default.createDirectory(atPath: itemDir, withIntermediateDirectories: true)

        // Export — SubtitleFileIO.export already bypasses `options` for STL/
        // SCC internally (raw Latin-1 bytes / literal UTF-8), so every
        // format goes through the same one call here.
        let options = TextOutputOptions(encodingLabel: config.encodingLabel, lineEnding: config.crlf ? .crlf : .lf, writeBOM: config.bom)
        var formatsWritten: [SubFormat] = []
        for format in config.formats {
            let ext = adapterForFormat(format).extensions[0]
            let destPath = (itemDir as NSString).appendingPathComponent("\(base).\(ext)")
            do {
                try SubtitleFileIO.export(doc.doc, format: format, to: destPath, options: options)
                formatsWritten.append(format)
            } catch {
                // One format failing (disk full mid-run, say) doesn't abort
                // the others — formatsWritten simply omits it.
            }
        }
        reportStepDone(1)

        var burnIn: DeliveryManifestItem.BurnInOutcome?
        if config.burnInEnabled {
            burnIn = await runBurnIn(doc: doc.doc, pair: pair, itemDir: itemDir, base: base)
            reportStepDone(6)
        }

        var qc: DeliveryManifestItem.QCOutcome?
        if config.qcEnabled {
            qc = writeQCReport(doc: doc.doc, thresholds: config.qcThresholds, itemDir: itemDir, base: base)
            reportStepDone(0.5)
        }

        var fonts: DeliveryManifestItem.FontsOutcome?
        if config.fontsEnabled {
            let (copiedFonts, notFound) = FontCollector.collectFiles(for: doc.doc, into: "\(itemDir)/Fonts")
            fonts = .init(copiedCount: copiedFonts.count, notFound: notFound)
            reportStepDone(0.5)
        }

        return DeliveryManifestItem(
            baseName: base, sourceSubtitlePath: pair.subtitlePath, pairedVideoPath: pair.videoPath,
            formatsWritten: formatsWritten, burnIn: burnIn, qc: qc, fonts: fonts)
    }

    private static func runBurnIn(
        doc: SubtitleDocument, pair: SubtitleVideoPair, itemDir: String, base: String
    ) async -> DeliveryManifestItem.BurnInOutcome {
        guard BurnInEncoder.ffmpegAvailable else { return .skippedFFmpegMissing }
        guard let videoPath = pair.videoPath else { return .skippedNoVideo }
        let outputPath = "\(itemDir)/\(base)_burned.mp4"
        let duration = await MediaDurationProbe.duration(ofFileAt: videoPath)
        do {
            try await BurnInEncoder.encode(videoPath: videoPath, document: doc, outputPath: outputPath, durationHint: duration) { _ in }
            return .succeeded(path: outputPath)
        } catch is CancellationError {
            return .failed(t("operationCancelled"))
        } catch {
            return .failed(String(describing: error))
        }
    }

    private static func writeQCReport(
        doc: SubtitleDocument, thresholds: QualityThresholds, itemDir: String, base: String
    ) -> DeliveryManifestItem.QCOutcome {
        // No loaded MediaModel in a headless folder scan, so shot-change-
        // crossing checks don't fire here — a documented limitation, not a
        // bug (see the plan file / QualityIssuesPanel, which DOES have
        // media.sceneCuts available in the interactive case).
        let rows = qcReportRows(doc, thresholds: thresholds)
        let csvPath = "\(itemDir)/\(base)_qc.csv"
        let htmlPath = "\(itemDir)/\(base)_qc.html"
        try? generateQCReportCSV(doc, thresholds: thresholds).write(toFile: csvPath, atomically: true, encoding: .utf8)
        try? generateQCReportHTML(doc, thresholds: thresholds, title: base).write(toFile: htmlPath, atomically: true, encoding: .utf8)
        return .init(issueCount: rows.count, csvPath: csvPath, htmlPath: htmlPath)
    }

    private static func writeManifestFiles(_ manifest: DeliveryManifest, to outputRoot: String) -> Bool {
        do {
            let json = try serializeDeliveryManifestJSON(manifest)
            try json.write(toFile: "\(outputRoot)/manifest.json", atomically: true, encoding: .utf8)
            try serializeDeliveryManifestText(manifest).write(toFile: "\(outputRoot)/manifest.txt", atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
