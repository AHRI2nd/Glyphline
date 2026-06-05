// SubRip (.srt) adapter.
//
// Format gotchas:
//  - Time: "HH:MM:SS,mmm --> HH:MM:SS,mmm". Millisecond separator is ',' but we
//    tolerate '.' on input; we always emit ','.
//  - Cue numbers are regenerated on export (1-based), not trusted from input.
//  - Multi-line cue text: line breaks are PRESERVED as "\n" (unlike Lyrical Sync's
//    LRC→SRT path which joined lines with spaces). Subtitle text needs the breaks.
//  - Tokens (word timing) have no SRT representation → dropped on export.

import { newCueId, emptyDocument, type Cue, type SubtitleDocument } from "../types/subtitle";
import { formatSrtTime, parseClockTime } from "../utils/time";

const ARROW_RE = /-->/;

export function parseSrt(raw: string): SubtitleDocument {
  const doc = emptyDocument("srt");
  // Normalize newlines, split into blocks on blank lines.
  const blocks = raw.replace(/\r\n/g, "\n").replace(/^﻿/, "").split(/\n\s*\n/);

  for (const block of blocks) {
    const lines = block.split("\n");
    // Drop a leading numeric index line if present.
    if (lines.length && /^\d+$/.test(lines[0].trim())) lines.shift();
    if (!lines.length) continue;

    const timeLine = lines.shift()!;
    if (!ARROW_RE.test(timeLine)) continue;
    const [startStr, endStr] = timeLine.split(ARROW_RE);
    const start = parseClockTime(startStr.trim());
    const end = parseClockTime(endStr.trim());
    if (start == null || end == null) continue;

    const text = lines.join("\n").trim();
    doc.cues.push({ id: newCueId(), start, end, text });
  }
  return doc;
}

export function serializeSrt(doc: SubtitleDocument): string {
  const cues = sortedCues(doc.cues);
  const out = cues.map((cue, i) => {
    return `${i + 1}\n${formatSrtTime(cue.start)} --> ${formatSrtTime(cue.end)}\n${cue.text}`;
  });
  return out.join("\n\n") + "\n";
}

export function sortedCues(cues: Cue[]): Cue[] {
  return [...cues].sort((a, b) => a.start - b.start || a.end - b.end);
}
