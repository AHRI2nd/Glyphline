// Assigns a small rotating color-slot index to cues that overlap another cue
// in time, so overlapping subtitles can be told apart on the waveform and in
// the cue grid — non-overlapping cues get no assignment (nil), staying in
// their normal, unhighlighted state; distinguishing overlaps is the point, so
// cues nobody clashes with shouldn't be colored at all.
//
// Standard interval-graph greedy coloring: sweep cues in start-time order,
// track which intervals are still "open" (their end hasn't passed the current
// cue's start), and hand out the lowest color slot not already in use by an
// open interval, so distant non-overlapping cues freely reuse slots.
//
// LIMIT: distinctness holds only while at most `paletteSize` cues overlap at
// the same instant. Past that the slot wraps and two simultaneously-visible
// cues do share a color — unavoidable with a fixed palette, and it degrades
// quietly rather than failing. Five slots covers ordinary subtitle work
// (even dense signs/karaoke rarely stacks that deep); see the
// exceeding-the-palette test for the exact pinned behavior.

import Foundation

/// Maps cue id → color slot (0..<paletteSize) for every cue that overlaps at
/// least one other cue. `cues` must be sorted by start ascending (see
/// `sortedCues`).
public func overlapColorSlots(for cues: [Cue], paletteSize: Int) -> [String: Int] {
    guard paletteSize > 0 else { return [:] }
    var result: [String: Int] = [:]
    var active: [(id: String, end: Double, slot: Int)] = []

    for cue in cues {
        active.removeAll { $0.end <= cue.start + 1e-9 }
        let usedSlots = Set(active.map { $0.slot })
        var slot = 0
        while usedSlots.contains(slot) { slot += 1 }
        slot %= paletteSize
        if !active.isEmpty {
            result[cue.id] = slot
            // First time an overlap is detected, retroactively mark every
            // still-open partner too — they may have looked non-overlapping
            // up to now.
            for a in active { result[a.id] = result[a.id] ?? a.slot }
        }
        active.append((id: cue.id, end: cue.end, slot: slot))
    }
    return result
}
