// YouTube SubViewer (.sbv) adapter.
//
// Format: blocks separated by blank lines. First line is "start,end" with
// H:MM:SS.mmm clock times (comma-separated, no arrow); the rest is the text.
//   0:00:01.000,0:00:04.000
//   Hello world
// Tokens/styling have no representation → dropped on export.

import { newCueId, emptyDocument, type SubtitleDocument } from "../types/subtitle";
import { formatVttTime, parseClockTime } from "../utils/time";
import { sortedCues } from "./srt";

export function parseSbv(raw: string): SubtitleDocument {
  const doc = emptyDocument("sbv");
  const blocks = raw.replace(/\r\n/g, "\n").replace(/^﻿/, "").split(/\n\s*\n/);
  for (const block of blocks) {
    const lines = block.split("\n");
    if (!lines.length) continue;
    const timeLine = lines.shift()!.trim();
    const comma = timeLine.indexOf(",");
    if (comma === -1) continue;
    const start = parseClockTime(timeLine.slice(0, comma).trim());
    const end = parseClockTime(timeLine.slice(comma + 1).trim());
    if (start == null || end == null) continue;
    doc.cues.push({ id: newCueId(), start, end, text: lines.join("\n").trim() });
  }
  return doc;
}

export function serializeSbv(doc: SubtitleDocument): string {
  const out = sortedCues(doc.cues).map(
    (cue) => `${formatVttTime(cue.start)},${formatVttTime(cue.end)}\n${cue.text}`,
  );
  return out.join("\n\n") + "\n";
}
