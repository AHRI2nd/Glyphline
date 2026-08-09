// Manifest for the delivery pipeline — a per-run summary of what got written
// where and what went wrong, written to <outputRoot>/manifest.{json,txt} by
// the orchestration layer (Glyphline/DeliveryPipelineRunner.swift). Purely
// data + serialization here; no file I/O.
//
// JSON is the canonical, round-trippable form (useful for a future "diff
// this delivery against the last one" feature, or an automated intake script
// on the client's side); the plain-text form is derived deterministically
// from the same value so the two can never disagree, and is what a client
// without a JSON viewer actually reads.

import Foundation

public struct DeliveryManifestItem: Codable, Equatable, Sendable {
    public enum BurnInOutcome: Codable, Equatable, Sendable {
        case skippedNoVideo
        case skippedFFmpegMissing
        case succeeded(path: String)
        case failed(String)
    }
    public struct QCOutcome: Codable, Equatable, Sendable {
        public var issueCount: Int
        public var csvPath: String?
        public var htmlPath: String?
        public init(issueCount: Int, csvPath: String? = nil, htmlPath: String? = nil) {
            self.issueCount = issueCount
            self.csvPath = csvPath
            self.htmlPath = htmlPath
        }
    }
    public struct FontsOutcome: Codable, Equatable, Sendable {
        public var copiedCount: Int
        public var notFound: [String]
        public init(copiedCount: Int, notFound: [String]) {
            self.copiedCount = copiedCount
            self.notFound = notFound
        }
    }

    /// The disambiguated per-item folder name actually used (see
    /// `uniqueDestPath` in DestPathDisambiguation.swift) — may differ from
    /// the source file's own basename when two scanned subfolders collide.
    public var baseName: String
    public var sourceSubtitlePath: String
    public var pairedVideoPath: String?
    public var formatsWritten: [SubFormat]
    /// nil ⇔ burn-in was off for this run.
    public var burnIn: BurnInOutcome?
    /// nil ⇔ QC was off for this run.
    public var qc: QCOutcome?
    /// nil ⇔ font collection was off for this run.
    public var fonts: FontsOutcome?
    /// Set only when the source subtitle couldn't even be opened/parsed —
    /// every other field is empty/nil in that case, since there was no
    /// document to work from for any of the later steps.
    public var fatalError: String?

    public init(
        baseName: String, sourceSubtitlePath: String, pairedVideoPath: String? = nil,
        formatsWritten: [SubFormat] = [], burnIn: BurnInOutcome? = nil,
        qc: QCOutcome? = nil, fonts: FontsOutcome? = nil, fatalError: String? = nil
    ) {
        self.baseName = baseName
        self.sourceSubtitlePath = sourceSubtitlePath
        self.pairedVideoPath = pairedVideoPath
        self.formatsWritten = formatsWritten
        self.burnIn = burnIn
        self.qc = qc
        self.fonts = fonts
        self.fatalError = fatalError
    }
}

public struct DeliveryManifestSummary: Codable, Equatable, Sendable {
    public var totalItems: Int
    public var itemsWithFatalErrors: Int
    public var itemsMissingVideo: Int
    public var itemsMissingFfmpeg: Int
    public var itemsWithFontGaps: Int
}

public struct DeliveryManifest: Codable, Equatable, Sendable {
    public var runDate: Date
    public var outputRoot: String
    public var items: [DeliveryManifestItem]
    public var summary: DeliveryManifestSummary
}

/// Pure aggregation — computes `summary` from `items`, no I/O.
public func buildDeliveryManifest(items: [DeliveryManifestItem], outputRoot: String, runDate: Date = Date()) -> DeliveryManifest {
    var itemsWithFatalErrors = 0
    var itemsMissingVideo = 0
    var itemsMissingFfmpeg = 0
    var itemsWithFontGaps = 0
    for item in items {
        if item.fatalError != nil { itemsWithFatalErrors += 1 }
        switch item.burnIn {
        case .skippedNoVideo: itemsMissingVideo += 1
        case .skippedFFmpegMissing: itemsMissingFfmpeg += 1
        default: break
        }
        if let fonts = item.fonts, !fonts.notFound.isEmpty { itemsWithFontGaps += 1 }
    }
    let summary = DeliveryManifestSummary(
        totalItems: items.count,
        itemsWithFatalErrors: itemsWithFatalErrors,
        itemsMissingVideo: itemsMissingVideo,
        itemsMissingFfmpeg: itemsMissingFfmpeg,
        itemsWithFontGaps: itemsWithFontGaps
    )
    return DeliveryManifest(runDate: runDate, outputRoot: outputRoot, items: items, summary: summary)
}

public func serializeDeliveryManifestJSON(_ manifest: DeliveryManifest) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(manifest)
    return String(data: data, encoding: .utf8) ?? ""
}

/// Deterministic plain-text summary derived from the same `DeliveryManifest`
/// value as the JSON form — the human-facing file that ships alongside
/// manifest.json in the delivery folder.
public func serializeDeliveryManifestText(_ manifest: DeliveryManifest) -> String {
    let s = manifest.summary
    var lines = [
        "Delivery Manifest — \(manifest.outputRoot)",
        "Items: \(s.totalItems)  |  Errors: \(s.itemsWithFatalErrors)  |  " +
            "No video: \(s.itemsMissingVideo)  |  No ffmpeg: \(s.itemsMissingFfmpeg)  |  " +
            "Font gaps: \(s.itemsWithFontGaps)",
        "",
    ]
    for item in manifest.items {
        if let fatalError = item.fatalError {
            lines.append("✗ \(item.baseName) — FAILED: \(fatalError)")
            continue
        }
        var parts = ["formats: \(item.formatsWritten.map(\.rawValue).joined(separator: ","))"]
        switch item.burnIn {
        case .succeeded: parts.append("burn-in: ok")
        case .failed(let message): parts.append("burn-in: FAILED (\(message))")
        case .skippedNoVideo: parts.append("burn-in: skipped (no video)")
        case .skippedFFmpegMissing: parts.append("burn-in: skipped (no ffmpeg)")
        case nil: break
        }
        if let qc = item.qc { parts.append("qc: \(qc.issueCount) issue(s)") }
        if let fonts = item.fonts {
            parts.append(fonts.notFound.isEmpty
                ? "fonts: \(fonts.copiedCount) copied"
                : "fonts: \(fonts.copiedCount) copied, missing \(fonts.notFound.joined(separator: ", "))")
        }
        lines.append("✓ \(item.baseName) — " + parts.joined(separator: "; "))
    }
    return lines.joined(separator: "\n") + "\n"
}
