// Convert a whole folder of subtitle files at once — format, encoding, and
// (optionally) the same overlap/gap/empty-cue cleanup BatchCleanupPanel does
// per file, but here applied uniformly across every file in one pass. This is
// the tool for "the client just handed me 40 SRTs and wants STL" instead of
// opening, converting, and closing each one by hand.

import SwiftUI
import UniformTypeIdentifiers
import GlyphlineCore

struct BatchConvertPanel: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    private struct FileResult: Identifiable {
        let id = UUID()
        let name: String
        let outcome: Outcome
        enum Outcome { case success(String); case failure(String) }
    }

    @State private var inputPaths: [String] = []
    @State private var outputFormat: SubFormat = .srt
    @State private var outputFolder: String?
    @State private var fixOverlaps = true
    @State private var removeEmpty = false
    @State private var encodingLabel = "utf-8"
    @State private var crlf = false
    @State private var bom = false
    @State private var isProcessing = false
    @State private var results: [FileResult] = []
    @State private var runningTask: Task<Void, Never>?

    var body: some View {
        PanelShell(title: t("batchConvert"), width: 460) {
            VStack(alignment: .leading, spacing: 12) {
                inputSection
                Divider()
                outputSection
                Divider()
                cleanupSection
                if !results.isEmpty {
                    Divider()
                    resultsSection
                }
            }
        } footer: {
            Spacer()
            if isProcessing {
                Button(t("stopRunning")) { runningTask?.cancel() }
            }
            // "Cancel" only before a run has started — once running (or
            // finished), this only closes the panel; the run itself keeps
            // going in the background regardless (Stop actually stops it,
            // above), so the label stops implying it aborts anything.
            Button(isProcessing || !results.isEmpty ? t("close") : t("cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(t("batchConvertRun")) { run() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(GlyphColor.accent)
                .disabled(inputPaths.isEmpty || isProcessing)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var inputSection: some View {
        HStack {
            Text(t("batchConvertFiles")).font(GlyphFont.body(12))
            Spacer()
            Text(inputPaths.isEmpty ? t("batchConvertNoFiles") : t("batchConvertFileCount", "\(inputPaths.count)"))
                .font(GlyphFont.data(11))
                .foregroundStyle(inputPaths.isEmpty ? GlyphColor.amber : GlyphColor.quiet)
            Button(t("batchConvertChooseFolder")) { chooseFolder() }.controlSize(.small)
            Button(t("batchConvertChooseFiles")) { chooseFiles() }.controlSize(.small)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("exportAs")).font(GlyphFont.body(12))
                Spacer()
                Picker("", selection: $outputFormat) {
                    ForEach(SubFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue.uppercased()).tag(fmt)
                    }
                }
                .labelsHidden().frame(width: 120)
            }
            HStack {
                Text(t("batchConvertOutputFolder")).font(GlyphFont.body(12))
                Spacer()
                Text(outputFolder.map { ($0 as NSString).lastPathComponent } ?? t("batchConvertSameFolder"))
                    .font(GlyphFont.data(11)).foregroundStyle(GlyphColor.quiet)
                    .lineLimit(1)
                Button(t("choose")) { chooseOutputFolder() }.controlSize(.small)
                if outputFolder != nil {
                    Button(t("batchConvertUseSameFolder")) { outputFolder = nil }.controlSize(.small)
                }
            }
            if outputFormat != .stl, outputFormat != .scc {
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
            } else {
                Text(t("batchConvertBinaryFormatNote"))
                    .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
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
    private var resultsSection: some View {
        let failures = results.filter { if case .failure = $0.outcome { return true }; return false }
        VStack(alignment: .leading, spacing: 4) {
            Text(t("batchConvertResult", "\(results.count - failures.count)", "\(results.count)"))
                .font(GlyphFont.data(11))
                .foregroundStyle(failures.isEmpty ? GlyphColor.good : GlyphColor.amber)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { r in
                        HStack(spacing: 6) {
                            switch r.outcome {
                            case .success: Image(systemName: "checkmark").foregroundStyle(GlyphColor.good)
                            case .failure: Image(systemName: "xmark").foregroundStyle(GlyphColor.warn)
                            }
                            Text(r.name).font(GlyphFont.body(11)).lineLimit(1)
                            switch r.outcome {
                            case .failure(let msg):
                                Text(msg).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                            case .success(let destPath):
                                let destName = (destPath as NSString).lastPathComponent
                                // Only shown when it actually differs from the
                                // source name — i.e. a same-name collision from
                                // another subfolder got disambiguated. Silent
                                // otherwise, since restating "wrote X.ext" for
                                // every ordinary file would just be noise.
                                if (destName as NSString).deletingPathExtension != (r.name as NSString).deletingPathExtension {
                                    Text("→ \(destName)").font(GlyphFont.data(10)).foregroundStyle(GlyphColor.amber)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    // MARK: - File pickers

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let known = Set(openExtensions())
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        var found: [String] = []
        while let item = enumerator?.nextObject() as? URL {
            if known.contains(extensionOf(item.path)) { found.append(item.path) }
        }
        inputPaths = found.sorted()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = openExtensions().compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        inputPaths = panel.urls.map(\.path).sorted()
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url.path
    }

    // MARK: - Processing

    private func run() {
        isProcessing = true
        results = []
        let ext = adapterForFormat(outputFormat).extensions[0]
        let options = TextOutputOptions(encodingLabel: encodingLabel, lineEnding: crlf ? .crlf : .lf, writeBOM: bom)
        let jobId = state.startBackgroundJob(t("batchConvert") + ": \(inputPaths.count)")

        runningTask = Task {
            // "폴더 선택…" scans recursively, so two inputs from DIFFERENT
            // source subfolders routinely share a filename (every episode
            // folder having its own "subtitle.srt" is completely normal).
            // Funneled into ONE chosen output folder, that used to mean the
            // second one silently overwrote the first with no error and no
            // sign anything was lost — this tracks every destination this
            // run has already written and disambiguates a repeat instead.
            var usedDestPaths = Set<String>()

            for path in inputPaths {
                if Task.isCancelled { break }
                let name = (path as NSString).lastPathComponent
                do {
                    let opened = try SubtitleFileIO.open(path: path)
                    let doc = DocumentModel()
                    doc.loadParsed(opened)
                    if fixOverlaps { doc.fixOverlaps() }
                    if removeEmpty { doc.removeEmptyCues() }

                    let base = (name as NSString).deletingPathExtension
                    let destDir = outputFolder ?? (path as NSString).deletingLastPathComponent
                    let destPath = GlyphlineCore.uniqueDestPath(dir: destDir, base: base, ext: ext, sourcePath: path, used: &usedDestPaths)
                    // SubtitleFileIO.export already bypasses `options` for
                    // STL/SCC internally (raw Latin-1 bytes / literal UTF-8),
                    // so every format goes through this one call.
                    try SubtitleFileIO.export(doc.doc, format: outputFormat, to: destPath, options: options)
                    results.append(FileResult(name: name, outcome: .success(destPath)))
                } catch {
                    results.append(FileResult(name: name, outcome: .failure(error.localizedDescription)))
                }
                state.updateBackgroundJob(jobId, progress: Double(results.count) / Double(inputPaths.count))
                await Task.yield() // keeps the UI responsive and cancellation checkable on a large batch
            }
            isProcessing = false
            let cancelled = Task.isCancelled
            let failureCount = results.filter { if case .failure = $0.outcome { return true }; return false }.count
            state.finishBackgroundJob(
                jobId, success: !cancelled && failureCount == 0,
                message: cancelled ? t("operationCancelled")
                    : t("batchConvertResult", "\(results.count - failureCount)", "\(results.count)"))
        }
    }

}
