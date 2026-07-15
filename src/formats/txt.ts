// Plain text (.txt) adapter — script/transcript extraction.
//
// No timing in the format: on parse, each non-empty line becomes a cue with
// sequential placeholder timing (DEFAULT_DUR each, back-to-back) so the result
// is editable/re-timeable. On export, only the cue text is written (timing is
// dropped) — one cue per block, blank-line separated.

import { newCueId, emptyDocument, type SubtitleDocument } from "../types/subtitle";
import { sortedCues } from "./srt";

const DEFAULT_DUR = 2; // seconds per line when importing untimed text

export function parseTxt(raw: string): SubtitleDocument {
  const doc = emptyDocument("txt");
  const lines = raw.replace(/\r\n/g, "\n").replace(/^﻿/, "").split("\n");
  let t = 0;
  for (const line of lines) {
    const text = line.trim();
    if (!text) continue;
    doc.cues.push({ id: newCueId(), start: t, end: t + DEFAULT_DUR, text });
    t += DEFAULT_DUR;
  }
  return doc;
}

export function serializeTxt(doc: SubtitleDocument): string {
  return sortedCues(doc.cues).map((cue) => cue.text).join("\n\n") + "\n";
}
