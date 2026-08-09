import Testing
@testable import GlyphlineCore

@Suite("Destination path disambiguation")
struct DestPathDisambiguationTests {
    @Test("first write in a run gets the plain path")
    func plainFirstWrite() {
        var used = Set<String>()
        let path = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/src/ep01/episode.srt", used: &used)
        #expect(path == "/out/episode.srt")
    }

    @Test("a second write with the same base is prefixed with the source's parent folder name")
    func secondWriteIsPrefixed() {
        var used = Set<String>()
        _ = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/src/ep01/episode.srt", used: &used)
        let second = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/src/ep02/episode.srt", used: &used)
        #expect(second == "/out/ep02_episode.srt")
    }

    @Test("a third collision (same base AND same parent folder name) falls back to a numeric suffix")
    func thirdCollisionIsNumbered() {
        var used = Set<String>()
        _ = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/src/season/episode.srt", used: &used)
        _ = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/other/season/episode.srt", used: &used)
        let third = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/third/season/episode.srt", used: &used)
        #expect(third == "/out/season_episode_2.srt")
    }

    @Test("ext == \"\" produces a directory-style name with no dot")
    func emptyExtProducesFolderName() {
        var used = Set<String>()
        let path = uniqueDestPath(dir: "/out", base: "episode", ext: "", sourcePath: "/src/ep01/episode.srt", used: &used)
        #expect(path == "/out/episode")
        #expect(!path.contains("."))
    }

    @Test("a path already in `used` from re-running conversion of a DIFFERENT source still disambiguates")
    func reRunSameDestDirDisambiguates() {
        var used: Set<String> = ["/out/episode.srt"]
        let path = uniqueDestPath(dir: "/out", base: "episode", ext: "srt", sourcePath: "/src/ep02/episode.srt", used: &used)
        #expect(path == "/out/ep02_episode.srt")
    }
}
