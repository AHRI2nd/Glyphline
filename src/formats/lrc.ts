// LRC (.lrc) lyrics adapter — compatible with the sibling Lyrical Sync app.
//
// Each lyric line is "[mm:ss.xx] text". A cue's end = the next line's start
// (the LRC format has no explicit end); the last line gets a default tail.
// Metadata tags ([ar:], [ti:], [offset:] …) are ignored on parse. Multi-line
// cue text is joined with spaces on export (LRC lines are single-line).

import { newCueId, emptyDocument, type Cue, type SubtitleDocument } from "../types/subtitle";
import { sortedCues } from "./srt";

const LAST_TAIL = 4; // seconds of display for the final line
const TIME_TAG = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

export function parseLrc(raw: string): SubtitleDocument {
  const doc = emptyDocument("lrc");
  const rows: Array<{ start: number; text: string }> = [];
  for (const line of raw.replace(/\r\n/g, "\n").split("\n")) {
    TIME_TAG.lastIndex = 0;
    const tags: number[] = [];
    let m: RegExpExecArray | null;
    while ((m = TIME_TAG.exec(line)) !== null) {
      const frac = m[3] ? Number((m[3] + "00").slice(0, 2)) / 100 : 0;
      tags.push(Number(m[1]) * 60 + Number(m[2]) + frac);
    }
    if (!tags.length) continue; // metadata / blank line
    const text = line.replace(TIME_TAG, "").trim();
    for (const start of tags) rows.push({ start, text }); // one tag may repeat a line
  }
  rows.sort((a, b) => a.start - b.start);
  rows.forEach((row, i) => {
    const end = i + 1 < rows.length ? rows[i + 1].start : row.start + LAST_TAIL;
    doc.cues.push({ id: newCueId(), start: row.start, end, text: row.text });
  });
  return doc;
}

function lrcTime(seconds: number): string {
  const s = Math.max(0, seconds);
  const mm = Math.floor(s / 60);
  const ss = Math.floor(s % 60);
  const cc = Math.round((s - Math.floor(s)) * 100);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `[${pad(mm)}:${pad(ss)}.${pad(cc >= 100 ? 99 : cc)}]`;
}

export function serializeLrc(doc: SubtitleDocument): string {
  const out = sortedCues(doc.cues).map((cue: Cue) => `${lrcTime(cue.start)}${cue.text.replace(/\n/g, " ")}`);
  return out.join("\n") + "\n";
}
