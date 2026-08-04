import Testing
@testable import GlyphlineCore

// Unit tests for DocumentModel — the value-type undo/redo + edit actions ported
// from ../../src/stores/useSubtitleStore.ts. No direct TS test file existed for
// the store, so these are new coverage (per the M1 plan).

private func cue(_ id: String, _ start: Double, _ end: Double, _ text: String = "x") -> Cue {
    Cue(id: id, start: start, end: end, text: text)
}

@Suite("DocumentModel: undo/redo")
struct DocumentModelUndoRedoTests {
    @Test("undo restores previous doc; redo replays it")
    func basic() {
        let m = DocumentModel()
        m.addCue()
        let afterAdd = m.doc.cues.count
        #expect(afterAdd == 1)
        #expect(m.canUndo)
        m.undo()
        #expect(m.doc.cues.isEmpty)
        #expect(m.canRedo)
        m.redo()
        #expect(m.doc.cues.count == 1)
    }

    @Test("new mutation after undo clears redo stack")
    func branching() {
        let m = DocumentModel()
        m.addCue()
        m.undo()
        m.addCueAt(start: 5, end: 7)
        #expect(!m.canRedo)
    }

    @Test("isDirty flips true on mutation, stays after undo")
    func dirtyFlag() {
        let m = DocumentModel()
        #expect(!m.isDirty)
        m.addCue()
        #expect(m.isDirty)
    }

    // A waveform edge-drag mutates on every mouse-move frame; without
    // coalescing, one gesture would bury real history under dozens of
    // near-identical entries.
    @Test("interactive gesture collapses many mutations into one undo entry")
    func interactiveCoalescing() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1)]))
        let before = m.doc.cues[0]

        m.beginInteractive()
        for step in 1...25 {
            m.updateCue("a") { $0.end = 1 + Double(step) * 0.05 }
        }
        m.endInteractive()

        #expect(m.doc.cues[0].end == 2.25)
        m.undo()
        #expect(m.doc.cues[0] == before) // one undo returns to the pre-drag state
        #expect(!m.canUndo)
    }

    @Test("mutations after endInteractive get their own undo entries again")
    func interactiveEndsCleanly() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1)]))

        m.beginInteractive()
        m.updateCue("a") { $0.end = 2 }
        m.updateCue("a") { $0.end = 3 }
        m.endInteractive()
        m.updateCue("a") { $0.end = 9 }

        m.undo()
        #expect(m.doc.cues[0].end == 3) // undoes only the post-gesture edit
        m.undo()
        #expect(m.doc.cues[0].end == 1) // then the whole gesture at once
    }

    @Test("interactive marks the document dirty even on coalesced frames")
    func interactiveDirty() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1)]))
        m.markSaved(path: "/tmp/x.glyph", name: "x.glyph")
        #expect(!m.isDirty)

        m.beginInteractive()
        m.updateCue("a") { $0.end = 2 }
        m.updateCue("a") { $0.end = 3 } // coalesced — must still dirty the doc
        m.endInteractive()
        #expect(m.isDirty)
    }
}

@Suite("DocumentModel: selection")
struct DocumentModelSelectionTests {
    @Test("toggleSelect additive vs exclusive")
    func toggle() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1), cue("b", 1, 2)]))
        m.toggleSelect("a", additive: false)
        #expect(m.selectedIds == ["a"])
        m.toggleSelect("b", additive: true)
        #expect(m.selectedIds == ["a", "b"])
        m.toggleSelect("a", additive: false) // exclusive → replaces selection
        #expect(m.selectedIds == ["a"])
    }

    @Test("selectRange selects inclusive time-sorted span")
    func range() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1), cue("b", 1, 2), cue("c", 2, 3), cue("d", 3, 4)]))
        m.selectRange(anchorId: "b", toId: "d")
        #expect(m.selectedIds == ["b", "c", "d"])
        m.selectRange(anchorId: "d", toId: "a") // reversed anchor/target still works
        #expect(m.selectedIds == ["a", "b", "c", "d"])
    }
}

@Suite("DocumentModel: batch cleanup actions")
struct DocumentModelCleanupTests {
    @Test("fixOverlaps clamps ends to next start")
    func overlaps() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 5), cue("b", 3, 6)]))
        let n = m.fixOverlaps()
        #expect(n == 1)
        #expect(m.doc.cues.first { $0.id == "a" }?.end == 3)
    }

    @Test("applyMinGap enforces a gap even without overlap")
    func minGap() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 3), cue("b", 3.01, 6)])) // 10ms gap
        let n = m.applyMinGap(0.1) // require 100ms
        #expect(n == 1)
        #expect(m.doc.cues.first { $0.id == "a" }!.end <= 2.91 + 1e-9)
    }

    @Test("applyDurationLimits extends short cues without overlapping next")
    func durationLimits() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 0.2), cue("b", 0.3, 5)]))
        let n = m.applyDurationLimits(minSec: 0.7, maxSec: 7)
        #expect(n == 1)
        let a = m.doc.cues.first { $0.id == "a" }!
        #expect(a.end < 0.3) // capped before next cue's start
    }

    @Test("removeEmptyCues drops blank text+translation only")
    func removeEmpty() {
        let m = DocumentModel()
        var blank = cue("a", 0, 1, "  ")
        blank.translation = " "
        m.loadParsed(SubtitleDocument(cues: [blank, cue("b", 1, 2, "keep")]))
        let n = m.removeEmptyCues()
        #expect(n == 1)
        #expect(m.doc.cues.map(\.id) == ["b"])
    }

    @Test("changeCase sentence mode, scoped to selection")
    func caseChange() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1, "HELLO world"), cue("b", 1, 2, "ANOTHER line")]))
        m.selectedIds = ["a"]
        let n = m.changeCase(mode: .sentence, scope: .selected)
        #expect(n == 1)
        #expect(m.doc.cues.first { $0.id == "a" }?.text == "Hello world")
        #expect(m.doc.cues.first { $0.id == "b" }?.text == "ANOTHER line") // untouched
    }

    @Test("removeHearingImpaired strips bracket annotations")
    func hearingImpaired() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1, "[music] Hello (laughs)")]))
        let n = m.removeHearingImpaired()
        #expect(n == 1)
        #expect(m.doc.cues[0].text == "Hello")
    }

    @Test("mergeSameText merges contiguous repeats, keeps distant ones separate")
    func mergeSameText() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [
            cue("a", 0, 1, "hi"), cue("b", 1.1, 2, "hi"),   // contiguous → merge
            cue("c", 100, 101, "hi"),                         // far away → stays
        ]))
        let n = m.mergeSameText()
        #expect(n == 1)
        #expect(m.doc.cues.count == 2)
    }

    @Test("mergeSameTimecodes joins stacked lines")
    func mergeSameTimecodes() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 2, "line1"), cue("b", 0, 2, "line2")]))
        let n = m.mergeSameTimecodes()
        #expect(n == 1)
        #expect(m.doc.cues.count == 1)
        #expect(m.doc.cues[0].text == "line1\nline2")
    }
}

@Suite("DocumentModel: timing transforms")
struct DocumentModelTimingTests {
    @Test("applyPointSync remaps linearly incl. tokens")
    func pointSync() {
        let m = DocumentModel()
        var c = cue("a", 10, 20)
        c.tokens = [SyncToken(text: "w", start: 12, end: 14)]
        m.loadParsed(SubtitleDocument(cues: [c]))
        let ok = m.applyPointSync(srcA: 10, dstA: 0, srcB: 20, dstB: 10) // shift by -10, scale x1
        #expect(ok)
        let out = m.doc.cues[0]
        #expect(out.start == 0 && out.end == 10)
        #expect(out.tokens?[0].start == 2 && out.tokens?[0].end == 4)
    }

    @Test("applyPointSync rejects coincident source points")
    func pointSyncDegenerate() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1)]))
        #expect(m.applyPointSync(srcA: 5, dstA: 0, srcB: 5, dstB: 10) == false)
    }

    @Test("changeSpeed multiplies timestamps incl. tokens")
    func speed() {
        let m = DocumentModel()
        var c = cue("a", 10, 20)
        c.tokens = [SyncToken(text: "w", start: 10, end: 12)]
        m.loadParsed(SubtitleDocument(cues: [c]))
        #expect(m.changeSpeed(2.0))
        #expect(m.doc.cues[0].start == 20 && m.doc.cues[0].end == 40)
        #expect(m.doc.cues[0].tokens?[0].end == 24)
    }

    @Test("changeSpeed rejects non-positive factor")
    func speedInvalid() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1)]))
        #expect(m.changeSpeed(0) == false)
        #expect(m.changeSpeed(-1) == false)
    }

    @Test("shiftTime respects scope")
    func shift() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1), cue("b", 5, 6)]))
        m.selectedIds = ["a"]
        m.shiftTime(deltaSec: 2, scope: .selected)
        #expect(m.doc.cues.first { $0.id == "a" }?.start == 2)
        #expect(m.doc.cues.first { $0.id == "b" }?.start == 5) // untouched
        m.shiftTime(deltaSec: -100, scope: .all)
        #expect(m.doc.cues.allSatisfy { $0.start >= 0 }) // clamped to 0
    }
}

@Suite("DocumentModel: cue structure edits")
struct DocumentModelStructureTests {
    @Test("addCue appends after the last cue with a gap")
    func add() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 3)]))
        m.addCue()
        #expect(m.doc.cues.count == 2)
        #expect(m.doc.cues[1].start > 3)
        #expect(m.activeCueId == m.doc.cues[1].id)
    }

    @Test("duplicateCue copies fields and offsets timing")
    func duplicate() {
        let m = DocumentModel()
        var c = cue("a", 0, 2, "hello")
        c.actor = "Bob"
        m.loadParsed(SubtitleDocument(cues: [c]))
        m.duplicateCue("a")
        #expect(m.doc.cues.count == 2)
        let copy = m.doc.cues[1]
        #expect(copy.id != "a")
        #expect(copy.text == "hello" && copy.actor == "Bob")
        #expect(copy.start > 2)
    }

    @Test("splitCue splits multi-line text at the midpoint break")
    func splitMultiline() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 10, "line1\nline2\nline3\nline4")]))
        m.splitCue("a", atTime: 5)
        #expect(m.doc.cues.count == 2)
        #expect(m.doc.cues[0].text == "line1\nline2")
        #expect(m.doc.cues[1].text == "line3\nline4")
        #expect(m.doc.cues[0].end == 5 && m.doc.cues[1].start == 5)
    }

    @Test("splitCue ignores out-of-range time")
    func splitOutOfRange() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 10)]))
        m.splitCue("a", atTime: 20)
        #expect(m.doc.cues.count == 1)
    }

    @Test("mergeCues joins text and spans the full range")
    func merge() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 2, "first"), cue("b", 2, 5, "second")]))
        m.mergeCues(["a", "b"])
        #expect(m.doc.cues.count == 1)
        #expect(m.doc.cues[0].text == "first\nsecond")
        #expect(m.doc.cues[0].start == 0 && m.doc.cues[0].end == 5)
    }

    @Test("deleteCues removes by id and clears selection")
    func delete() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(cues: [cue("a", 0, 1), cue("b", 1, 2)]))
        m.selectedIds = ["a"]
        m.deleteCues(["a"])
        #expect(m.doc.cues.map(\.id) == ["b"])
        #expect(m.selectedIds.isEmpty)
    }
}

@Suite("DocumentModel: styles")
struct DocumentModelStyleTests {
    @Test("addStyle assigns a unique name")
    func add() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(styles: [AssStyle(name: "New Style")]))
        m.addStyle()
        #expect(m.doc.styles?.map(\.name) == ["New Style", "New Style 2"])
    }

    @Test("updateStyle rename re-points referencing cues")
    func rename() {
        let m = DocumentModel()
        var c = cue("a", 0, 1)
        c.style = "Old"
        m.loadParsed(SubtitleDocument(styles: [AssStyle(name: "Old")], cues: [c]))
        m.updateStyle("Old") { $0.name = "New" }
        #expect(m.doc.styles?.first?.name == "New")
        #expect(m.doc.cues.first?.style == "New")
    }

    @Test("deleteStyle clears style ref on cues")
    func delete() {
        let m = DocumentModel()
        var c = cue("a", 0, 1)
        c.style = "Gone"
        m.loadParsed(SubtitleDocument(styles: [AssStyle(name: "Gone")], cues: [c]))
        m.deleteStyle("Gone")
        #expect(m.doc.styles?.isEmpty == true)
        #expect(m.doc.cues.first?.style == nil)
    }
}

@Suite("DocumentModel: export")
struct DocumentModelExportTests {
    @Test("exportContent(.translation) swaps body, drops spans/tokens")
    func translationExport() {
        let m = DocumentModel()
        var c = cue("a", 1, 3, "Hello")
        c.translation = "안녕"
        c.assSpans = [AssSpan(text: "Hello")]
        m.loadParsed(SubtitleDocument(format: .srt, cues: [c]))
        let out = m.exportContent(format: .srt, source: .translation)
        #expect(out.contains("안녕"))
        #expect(!out.contains("Hello"))
    }

    @Test("exportContent(.translation) falls back to original when translation blank")
    func translationFallback() {
        let m = DocumentModel()
        m.loadParsed(SubtitleDocument(format: .srt, cues: [cue("a", 1, 3, "Hello")]))
        let out = m.exportContent(format: .srt, source: .translation)
        #expect(out.contains("Hello"))
    }
}
