// Advanced SubStation Alpha (.ass / .ssa) adapter.
//
// Format gotchas:
//  - Sections: [Script Info], [V4+ Styles], [Events]. A "Format:" line declares
//    the column order; Style:/Dialogue: rows map positionally to those columns.
//  - Time: "H:MM:SS.cc" (centiseconds).
//  - The Text column is always LAST and may itself contain commas, so we split
//    Dialogue lines into exactly N-1 commas then take the remainder as text.
//  - Karaoke "{\k<cs>}" tags map to/from Cue.tokens (each \k = syllable duration
//    in centiseconds for the text that follows).
//  - [Script Info] lines and any unrecognized sections are preserved in meta.
//  - Unknown style/event columns are preserved in raw for round-trip fidelity.

import {
  newCueId,
  emptyDocument,
  type AssStyle,
  type Cue,
  type SubtitleDocument,
  type SyncToken,
} from "../types/subtitle";
import { formatAssTime, parseAssTime } from "../utils/time";
import { sortedCues } from "./srt";
import { leadingBlock, parseAssText, serializeAssText, spansToPlain } from "./assTags";

const DEFAULT_STYLE_FORMAT = [
  "Name", "Fontname", "Fontsize", "PrimaryColour", "SecondaryColour", "OutlineColour",
  "BackColour", "Bold", "Italic", "Underline", "StrikeOut", "ScaleX", "ScaleY",
  "Spacing", "Angle", "BorderStyle", "Outline", "Shadow", "Alignment",
  "MarginL", "MarginR", "MarginV", "Encoding",
];
const DEFAULT_EVENT_FORMAT = [
  "Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text",
];

export function parseAss(raw: string): SubtitleDocument {
  const doc = emptyDocument("ass");
  doc.styles = [];
  const lines = raw.replace(/\r\n/g, "\n").replace(/^﻿/, "").split("\n");

  let section = "";
  let styleFormat = DEFAULT_STYLE_FORMAT;
  let eventFormat = DEFAULT_EVENT_FORMAT;
  const scriptInfo: string[] = [];
  const otherSections: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    const sectionMatch = trimmed.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      section = sectionMatch[1].toLowerCase();
      if (section !== "script info" && !section.includes("styles") && section !== "events") {
        otherSections.push(line);
      }
      continue;
    }

    if (section === "script info") {
      if (trimmed) scriptInfo.push(line);
      continue;
    }

    if (section.includes("styles")) {
      if (/^Format:/i.test(trimmed)) {
        styleFormat = splitCsv(trimmed.replace(/^Format:/i, ""));
      } else if (/^Style:/i.test(trimmed)) {
        doc.styles.push(parseStyle(trimmed.replace(/^Style:/i, ""), styleFormat));
      }
      continue;
    }

    if (section === "events") {
      if (/^Format:/i.test(trimmed)) {
        eventFormat = splitCsv(trimmed.replace(/^Format:/i, ""));
      } else if (/^Dialogue:/i.test(trimmed)) {
        const cue = parseDialogue(trimmed.replace(/^Dialogue:/i, ""), eventFormat);
        if (cue) doc.cues.push(cue);
      } else if (trimmed) {
        // Comment: or other event lines — preserve verbatim.
        otherSections.push(line);
      }
      continue;
    }
  }

  if (scriptInfo.length) doc.meta.assScriptInfo = scriptInfo.join("\n");
  if (otherSections.length) doc.meta.assExtra = otherSections.join("\n");
  doc.meta.assStyleFormat = styleFormat.join(", ");
  doc.meta.assEventFormat = eventFormat.join(", ");
  return doc;
}

export function serializeAss(doc: SubtitleDocument): string {
  const styleFormat = (doc.meta.assStyleFormat?.split(/\s*,\s*/) ?? DEFAULT_STYLE_FORMAT);
  const eventFormat = (doc.meta.assEventFormat?.split(/\s*,\s*/) ?? DEFAULT_EVENT_FORMAT);
  const styles = doc.styles?.length ? doc.styles : [defaultStyle()];

  const parts: string[] = [];
  parts.push("[Script Info]");
  parts.push(doc.meta.assScriptInfo ?? "ScriptType: v4.00+");
  parts.push("");
  parts.push("[V4+ Styles]");
  parts.push(`Format: ${styleFormat.join(", ")}`);
  for (const st of styles) parts.push(`Style: ${serializeStyle(st, styleFormat)}`);
  parts.push("");
  parts.push("[Events]");
  parts.push(`Format: ${eventFormat.join(", ")}`);
  for (const cue of sortedCues(doc.cues)) {
    parts.push(`Dialogue: ${serializeDialogue(cue, eventFormat)}`);
  }
  if (doc.meta.assExtra) parts.push(doc.meta.assExtra);
  return parts.join("\n") + "\n";
}

// ─── Styles ─────────────────────────────────────────────────────────────────
function parseStyle(line: string, format: string[]): AssStyle {
  const cols = splitCsv(line);
  const get = (key: string) => cols[format.indexOf(key)] ?? "";
  const rawCols: Record<string, string> = {};
  format.forEach((key, i) => (rawCols[key] = cols[i] ?? ""));
  return {
    name: get("Name"),
    fontName: get("Fontname"),
    fontSize: Number(get("Fontsize")) || 0,
    primaryColour: get("PrimaryColour"),
    outlineColour: get("OutlineColour"),
    backColour: get("BackColour"),
    bold: get("Bold") === "-1",
    italic: get("Italic") === "-1",
    outline: Number(get("Outline")) || 0,
    shadow: Number(get("Shadow")) || 0,
    alignment: Number(get("Alignment")) || 2,
    marginL: Number(get("MarginL")) || 0,
    marginR: Number(get("MarginR")) || 0,
    marginV: Number(get("MarginV")) || 0,
    raw: rawCols,
  };
}

function serializeStyle(st: AssStyle, format: string[]): string {
  const known: Record<string, string> = {
    Name: st.name,
    Fontname: st.fontName,
    Fontsize: String(st.fontSize),
    PrimaryColour: st.primaryColour,
    OutlineColour: st.outlineColour,
    BackColour: st.backColour,
    Bold: st.bold ? "-1" : "0",
    Italic: st.italic ? "-1" : "0",
    Outline: String(st.outline),
    Shadow: String(st.shadow),
    Alignment: String(st.alignment),
    MarginL: String(st.marginL),
    MarginR: String(st.marginR),
    MarginV: String(st.marginV),
  };
  return format.map((key) => known[key] ?? st.raw?.[key] ?? "").join(",");
}

function defaultStyle(): AssStyle {
  return {
    name: "Default",
    fontName: "Arial",
    fontSize: 48,
    primaryColour: "&H00FFFFFF",
    outlineColour: "&H00000000",
    backColour: "&H00000000",
    bold: false,
    italic: false,
    outline: 2,
    shadow: 0,
    alignment: 2,
    marginL: 10,
    marginR: 10,
    marginV: 10,
  };
}

// ─── Events ─────────────────────────────────────────────────────────────────
function parseDialogue(line: string, format: string[]): Cue | null {
  // Text is the last column and may contain commas; split only N-1 times.
  const n = format.length;
  const cols = splitN(line, n);
  const get = (key: string) => cols[format.indexOf(key)] ?? "";

  const start = parseAssTime(get("Start"));
  const end = parseAssTime(get("End"));
  if (start == null || end == null) return null;

  const rawText = get("Text");
  const spans = parseAssText(rawText);
  const tokens = extractKaraoke(rawText, start);
  const cue: Cue = {
    id: newCueId(),
    start,
    end,
    text: spansToPlain(spans),
    assSpans: spans, // every inline override tag preserved verbatim
    layer: Number(get("Layer")) || 0,
    style: get("Style") || undefined,
    actor: get("Name") || undefined,
  };
  if (tokens.length) cue.tokens = tokens;

  // Preserve margins/effect for fidelity (text fidelity is handled by assSpans).
  const raw: Record<string, string> = {};
  for (const key of ["MarginL", "MarginR", "MarginV", "Effect"]) {
    const v = get(key);
    if (v) raw[key] = v;
  }
  if (Object.keys(raw).length) cue.raw = raw;
  return cue;
}

function serializeDialogue(cue: Cue, format: string[]): string {
  const text = dialogueText(cue);
  const known: Record<string, string> = {
    Layer: String(cue.layer ?? 0),
    Start: formatAssTime(cue.start),
    End: formatAssTime(cue.end),
    Style: cue.style ?? "Default",
    Name: cue.actor ?? "",
    MarginL: cue.raw?.MarginL ?? "0",
    MarginR: cue.raw?.MarginR ?? "0",
    MarginV: cue.raw?.MarginV ?? "0",
    Effect: cue.raw?.Effect ?? "",
    Text: text,
  };
  return format.map((key) => known[key] ?? "").join(",");
}

/**
 * Choose the Text field for a Dialogue line. Priority:
 *  1. assSpans whose plain text is unchanged → reconstruct verbatim. This is the
 *     lossless path: ALL inline override tags (known or not) survive exactly.
 *  2. tokens (karaoke) for cues that have timing but no spans (e.g. converted
 *     from VTT) → render \k tags.
 *  3. Edited text → keep the opening override block (line-level \pos/\an/\fad…)
 *     and append the edited text. Mid-text inline blocks can't be re-anchored to
 *     edited text and are dropped.
 */
function dialogueText(cue: Cue): string {
  const spans = cue.assSpans;
  if (spans && spansToPlain(spans) === cue.text) return serializeAssText(spans);
  if (cue.tokens?.length) return renderKaraoke(cue);
  const lead = leadingBlock(spans);
  return (lead ? `{${lead}}` : "") + plainToAssText(cue.text);
}

// ASS uses "\N" for hard line breaks within the Text field.
function plainToAssText(text: string): string {
  return text.replace(/\n/g, "\\N");
}

/** Parse "{\k50}Ka{\k30}ra" karaoke into tokens starting at cue start. */
function extractKaraoke(text: string, start: number): SyncToken[] {
  if (!/\{\\k/i.test(text)) return [];
  const tokens: SyncToken[] = [];
  const re = /\{\\k(\d+)\}([^{]*)/gi;
  let cursor = start;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const durCs = Number(m[1]);
    const syl = m[2].replace(/\\N/g, "\n");
    const end = cursor + durCs / 100;
    if (syl) tokens.push({ text: syl, start: cursor, end });
    cursor = end;
  }
  return tokens;
}

function renderKaraoke(cue: Cue): string {
  return cue
    .tokens!.map((tok) => {
      const cs = Math.round((tok.end - tok.start) * 100);
      return `{\\k${cs}}${tok.text.replace(/\n/g, "\\N")}`;
    })
    .join("");
}

// ─── CSV helpers ──────────────────────────────────────────────────────────────
function splitCsv(s: string): string[] {
  return s.split(",").map((x) => x.trim());
}
/** Split into at most n fields; the final field keeps any remaining commas. */
function splitN(s: string, n: number): string[] {
  const out: string[] = [];
  let rest = s;
  for (let i = 0; i < n - 1; i++) {
    const idx = rest.indexOf(",");
    if (idx === -1) {
      out.push(rest.trim());
      rest = "";
      continue;
    }
    out.push(rest.slice(0, idx).trim());
    rest = rest.slice(idx + 1);
  }
  out.push(rest); // last field: do not trim (leading spaces may be intentional)
  return out;
}
