import Testing
import Foundation
@testable import GlyphlineCore

private let mediaExts: Set<String> = ["mp4", "mkv", "mov"]

@Suite("Delivery pairing")
struct DeliveryPairingTests {
    @Test("same directory, same basename pairs correctly")
    func basicPair() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/ep01.srt"],
            candidatePaths: ["/show/ep01.mp4", "/show/ep02.mp4"],
            mediaExts: mediaExts
        )
        #expect(pairs.count == 1)
        #expect(pairs[0].subtitlePath == "/show/ep01.srt")
        #expect(pairs[0].videoPath == "/show/ep01.mp4")
    }

    @Test("a video with the same basename in a DIFFERENT directory is not paired")
    func differentDirectoryNotPaired() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/season1/ep01.srt"],
            candidatePaths: ["/show/season2/ep01.mp4"],
            mediaExts: mediaExts
        )
        #expect(pairs[0].videoPath == nil)
    }

    @Test("no match leaves videoPath nil")
    func noMatch() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/ep01.srt"],
            candidatePaths: ["/show/notes.txt"],
            mediaExts: mediaExts
        )
        #expect(pairs[0].videoPath == nil)
    }

    @Test("two candidate extensions for the same basename resolve deterministically (alphabetical)")
    func ambiguousExtensionIsDeterministic() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/ep01.srt"],
            candidatePaths: ["/show/ep01.mp4", "/show/ep01.mkv"],
            mediaExts: mediaExts
        )
        // "ep01.mkv" < "ep01.mp4" alphabetically
        #expect(pairs[0].videoPath == "/show/ep01.mkv")
    }

    @Test("non-media files sharing the basename are ignored")
    func nonMediaIgnored() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/ep01.srt"],
            candidatePaths: ["/show/ep01.txt", "/show/ep01.mp4"],
            mediaExts: mediaExts
        )
        #expect(pairs[0].videoPath == "/show/ep01.mp4")
    }

    @Test("empty input produces empty output")
    func emptyInput() {
        let pairs = pairSubtitlesWithVideos(subtitlePaths: [], candidatePaths: ["/show/ep01.mp4"], mediaExts: mediaExts)
        #expect(pairs.isEmpty)
    }

    @Test("real on-disk folder scan pairs correctly (exercises FileManager enumeration, not just hand-typed paths)")
    func realFilesystemScan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("delivery-pairing-\(UUID().uuidString)")
        let season = root.appendingPathComponent("season1")
        try FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "1\n00:00:01,000 --> 00:00:03,000\nHello\n".write(to: season.appendingPathComponent("ep01.srt"), atomically: true, encoding: .utf8)
        try "1\n00:00:01,000 --> 00:00:03,000\nNo video\n".write(to: season.appendingPathComponent("ep02.srt"), atomically: true, encoding: .utf8)
        try Data().write(to: season.appendingPathComponent("ep01.mp4"))

        var subtitlePaths: [String] = []
        var allPaths: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            allPaths.append(item.path)
            if item.pathExtension == "srt" { subtitlePaths.append(item.path) }
        }

        let pairs = pairSubtitlesWithVideos(subtitlePaths: subtitlePaths.sorted(), candidatePaths: allPaths, mediaExts: mediaExts)
        #expect(pairs.count == 2)
        let ep01 = pairs.first { $0.subtitlePath.hasSuffix("ep01.srt") }
        let ep02 = pairs.first { $0.subtitlePath.hasSuffix("ep02.srt") }
        #expect(ep01?.videoPath?.hasSuffix("ep01.mp4") == true)
        #expect(ep02?.videoPath == nil)
    }

    @Test("multiple subtitles each resolve independently")
    func multipleSubtitles() {
        let pairs = pairSubtitlesWithVideos(
            subtitlePaths: ["/show/ep01.srt", "/show/ep02.srt", "/show/ep03.srt"],
            candidatePaths: ["/show/ep01.mp4", "/show/ep03.mkv"],
            mediaExts: mediaExts
        )
        #expect(pairs.map(\.videoPath) == ["/show/ep01.mp4", nil, "/show/ep03.mkv"])
    }
}
