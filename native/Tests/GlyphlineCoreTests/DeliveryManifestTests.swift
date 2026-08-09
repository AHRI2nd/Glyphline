import Testing
import Foundation
@testable import GlyphlineCore

@Suite("Delivery manifest")
struct DeliveryManifestTests {
    private func mixedItems() -> [DeliveryManifestItem] {
        [
            DeliveryManifestItem(
                baseName: "clean", sourceSubtitlePath: "/src/clean.srt",
                pairedVideoPath: "/src/clean.mp4", formatsWritten: [.srt, .vtt],
                burnIn: .succeeded(path: "/out/clean/clean_burned.mp4"),
                qc: .init(issueCount: 0), fonts: .init(copiedCount: 2, notFound: [])
            ),
            DeliveryManifestItem(
                baseName: "broken", sourceSubtitlePath: "/src/broken.srt",
                fatalError: "couldn't parse subtitle"
            ),
            DeliveryManifestItem(
                baseName: "noVideo", sourceSubtitlePath: "/src/noVideo.srt",
                formatsWritten: [.srt], burnIn: .skippedNoVideo, qc: .init(issueCount: 3)
            ),
            DeliveryManifestItem(
                baseName: "noFfmpeg", sourceSubtitlePath: "/src/noFfmpeg.srt",
                pairedVideoPath: "/src/noFfmpeg.mp4", formatsWritten: [.srt], burnIn: .skippedFFmpegMissing
            ),
            DeliveryManifestItem(
                baseName: "fontGap", sourceSubtitlePath: "/src/fontGap.srt",
                formatsWritten: [.ass], fonts: .init(copiedCount: 1, notFound: ["Missing Sans"])
            ),
        ]
    }

    @Test("summary counters reflect each condition exactly once")
    func summaryCounts() {
        let manifest = buildDeliveryManifest(items: mixedItems(), outputRoot: "/out")
        #expect(manifest.summary.totalItems == 5)
        #expect(manifest.summary.itemsWithFatalErrors == 1)
        #expect(manifest.summary.itemsMissingVideo == 1)
        #expect(manifest.summary.itemsMissingFfmpeg == 1)
        #expect(manifest.summary.itemsWithFontGaps == 1)
    }

    @Test("JSON round-trips to an equal value")
    func jsonRoundTrip() throws {
        let manifest = buildDeliveryManifest(items: mixedItems(), outputRoot: "/out", runDate: Date(timeIntervalSince1970: 0))
        let json = try serializeDeliveryManifestJSON(manifest)
        let decoded = try JSONDecoder.deliveryManifestDecoder.decode(DeliveryManifest.self, from: Data(json.utf8))
        #expect(decoded == manifest)
    }

    @Test("text summary reports item counts and per-item outcomes")
    func textSummary() {
        let manifest = buildDeliveryManifest(items: mixedItems(), outputRoot: "/out")
        let text = serializeDeliveryManifestText(manifest)
        #expect(text.contains("Items: 5"))
        #expect(text.contains("✗ broken — FAILED: couldn't parse subtitle"))
        #expect(text.contains("burn-in: skipped (no video)"))
        #expect(text.contains("burn-in: skipped (no ffmpeg)"))
        #expect(text.contains("missing Missing Sans"))
        #expect(text.contains("qc: 3 issue(s)"))
    }

    @Test("an all-clean run has zero counters")
    func allCleanRun() {
        let clean = [DeliveryManifestItem(baseName: "a", sourceSubtitlePath: "/a.srt", formatsWritten: [.srt])]
        let manifest = buildDeliveryManifest(items: clean, outputRoot: "/out")
        #expect(manifest.summary.itemsWithFatalErrors == 0)
        #expect(manifest.summary.itemsMissingVideo == 0)
        #expect(manifest.summary.itemsMissingFfmpeg == 0)
        #expect(manifest.summary.itemsWithFontGaps == 0)
    }
}

private extension JSONDecoder {
    static var deliveryManifestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
