// WebVTT (.vtt) adapter.
//
// Format gotchas:
//  - Must start with "WEBVTT". Header text + region/style is preserved in meta.
//  - Time: "HH:MM:SS.mmm --> HH:MM:SS.mmm" (dot separator, hours optional).
//  - Cue settings after the arrow (align, position, line…) are preserved in raw.
//  - NOTE blocks and STYLE blocks are preserved verbatim in meta (round-trip).
//  - Inline timestamps "<00:00:02.000>" split text into timed tokens (karaoke).
//    These map to/from Cue.tokens.

import { newCueId, emptyDocument, type Cue, type SubtitleDocument, type SyncToken } from "../types/subtitle";
import { formatVttTime, parseClockTime } from "../utils/time";
import { sortedCues } from "./srt";

const ARROW_RE = /-->/;
const INLINE_TS_RE = /<(\d{1,2}:)?\d{1,2}:\d{1,2}\.\d{1,3}>/g;

export function parseVtt(raw: string): SubtitleDocument {
  const doc = emptyDocument("vtt");
  const text = raw.replace(/\r\n/g, "\n").replace(/^﻿/, "");
  const blocks = text.split(/\n\s*\n/);

  const preamble: string[] = [];
  for (let bi = 0; bi < blocks.length; bi++) {
    const block = blocks[bi].trim();
    if (!block) continue;

    // Header block (first one) and NOTE/STYLE/REGION blocks are kept in meta.
    if (bi === 0 && block.startsWith("WEBVTT")) {
      preamble.push(block);
      continue;
    }
    if (/^(NOTE|STYLE|REGION)\b/.test(block)) {
      preamble.push(block);
      continue;
    }

    const lines = block.split("\n");
    // Optional cue identifier line (no arrow) precedes the timing line.
    let identifier: string | undefined;
    if (lines.length && !ARROW_RE.test(lines[0])) {
      identifier = lines.shift()!.trim();
    }
    if (!lines.length || !ARROW_RE.test(lines[0])) continue;

    const timeLine = lines.shift()!;
    const arrowIdx = timeLine.search(ARROW_RE);
    const startStr = timeLine.slice(0, arrowIdx).trim();
    const rest = timeLine.slice(arrowIdx + 3).trim();
    const restParts = rest.split(/\s+/);
    const endStr = restParts.shift() ?? "";
    const settings = restParts.join(" ");

    const start = parseClockTime(startStr);
    const end = parseClockTime(endStr);
    if (start == null || end == null) continue;

    const rawText = lines.join("\n");
    const tokens = extractTokens(rawText, start, end);
    const cue: Cue = {
      id: newCueId(),
      start,
      end,
      text: stripInlineTimestamps(rawText).trim(),
    };
    if (identifier) cue.raw = { ...cue.raw, identifier };
    if (settings) cue.raw = { ...cue.raw, settings };
    if (tokens.length) cue.tokens = tokens;
    doc.cues.push(cue);
  }

  if (preamble.length) doc.meta.vttPreamble = preamble.join("\n\n");
  return doc;
}

export function serializeVtt(doc: SubtitleDocument): string {
  const header = doc.meta.vttPreamble ?? "WEBVTT";
  const cues = sortedCues(doc.cues);
  const parts = cues.map((cue) => {
    const id = cue.raw?.identifier ? `${cue.raw.identifier}\n` : "";
    const settings = cue.raw?.settings ? ` ${cue.raw.settings}` : "";
    const body = cue.tokens?.length ? renderTokens(cue) : cue.text;
    return `${id}${formatVttTime(cue.start)} --> ${formatVttTime(cue.end)}${settings}\n${body}`;
  });
  return [header, ...parts].join("\n\n") + "\n";
}

function stripInlineTimestamps(text: string): string {
  return text.replace(INLINE_TS_RE, "");
}

/** Parse "word<00:00:02.000>next" into timed tokens within [start, end]. */
function extractTokens(text: string, start: number, end: number): SyncToken[] {
  if (!INLINE_TS_RE.test(text)) return [];
  INLINE_TS_RE.lastIndex = 0;

  const tokens: SyncToken[] = [];
  let cursor = 0;
  let segStart = start;
  let match: RegExpExecArray | null;
  while ((match = INLINE_TS_RE.exec(text)) !== null) {
    const word = text.slice(cursor, match.index).trim();
    const ts = parseClockTime(match[0].slice(1, -1));
    if (word && ts != null) {
      tokens.push({ text: word, start: segStart, end: ts });
      segStart = ts;
    } else if (ts != null) {
      segStart = ts;
    }
    cursor = match.index + match[0].length;
  }
  const tail = text.slice(cursor).trim();
  if (tail) tokens.push({ text: tail, start: segStart, end });
  return tokens;
}

function renderTokens(cue: Cue): string {
  const toks = cue.tokens!;
  let out = "";
  toks.forEach((tok, i) => {
    if (i > 0) out += `<${formatVttTime(tok.start)}>`;
    out += (i > 0 ? " " : "") + tok.text;
  });
  return out;
}
