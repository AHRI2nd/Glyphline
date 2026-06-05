// SAMI (.smi) adapter.
//
// Format gotchas:
//  - HTML-like, TAGS ARE CASE-INSENSITIVE (<Sync Start=..>, <SYNC START=..>).
//  - START TIME ONLY (milliseconds). Like LRC, a cue's END is derived from the
//    NEXT <SYNC> start. A blank cue (&nbsp; or empty <P>) means "subtitle off":
//    it is NOT emitted as a cue, only used as the end boundary of the previous one.
//  - Multi-language tracks via <P Class=KRCC|ENCC|...>. First milestone edits the
//    most-populated Class only; the <HEAD>/<STYLE> and Class list are kept in meta
//    so we can round-trip.
//  - <br> -> "\n"; HTML entities decoded (and re-encoded on output).

import { newCueId, emptyDocument, type AssSpan, type SubtitleDocument } from "../types/subtitle";
import { categorizeTag, decodeTags, SMI_REPRESENTABLE, type LossCategory } from "./assTags";
import { assColorToHex } from "../utils/color";

const DEFAULT_TAIL = 3; // seconds, when a final cue has no closing boundary
const SYNC_RE = /<sync\b[^>]*\bstart\s*=\s*["']?(\d+)["']?[^>]*>/gi;
const CLASS_RE = /<p\b[^>]*\bclass\s*=\s*["']?([a-z0-9_-]+)["']?/i;

interface RawSync {
  startMs: number;
  className: string | null;
  text: string; // decoded plain text ("" for a blank/off marker)
}

export function parseSmi(raw: string): SubtitleDocument {
  const doc = emptyDocument("smi");
  const src = raw.replace(/\r\n/g, "\n");

  // Preserve <HEAD> (title + <STYLE>) verbatim for round-trip.
  const headMatch = src.match(/<head\b[^>]*>([\s\S]*?)<\/head>/i);
  if (headMatch) doc.meta.smiHead = headMatch[1].trim();

  // Collect every <SYNC> with its raw inner content.
  const syncs: RawSync[] = [];
  let m: RegExpExecArray | null;
  const matches: { index: number; startMs: number }[] = [];
  SYNC_RE.lastIndex = 0;
  while ((m = SYNC_RE.exec(src)) !== null) {
    matches.push({ index: m.index + m[0].length, startMs: Number(m[1]) });
  }
  for (let i = 0; i < matches.length; i++) {
    const inner = src.slice(matches[i].index, i + 1 < matches.length ? findTagStart(src, matches[i + 1].index) : src.length);
    const classMatch = inner.match(CLASS_RE);
    syncs.push({
      startMs: matches[i].startMs,
      className: classMatch ? classMatch[1] : null,
      text: smiInnerToText(inner),
    });
  }

  // Pick the dominant language Class (most non-blank entries).
  const classCounts = new Map<string, number>();
  for (const s of syncs) {
    if (s.text) classCounts.set(s.className ?? "", (classCounts.get(s.className ?? "") ?? 0) + 1);
  }
  let mainClass: string | null = null;
  let best = -1;
  for (const [cls, count] of classCounts) {
    if (count > best) {
      best = count;
      mainClass = cls || null;
    }
  }
  if (mainClass) doc.meta.smiMainClass = mainClass;
  // Record other classes so the export can keep emitting their P tags if desired.
  const allClasses = [...new Set(syncs.map((s) => s.className).filter(Boolean))] as string[];
  if (allClasses.length) doc.meta.smiClasses = allClasses.join(",");

  // Build cues from the main-class stream; blank entries close the previous cue.
  const stream = syncs.filter((s) => (s.className ?? null) === mainClass || s.className === null);
  for (let i = 0; i < stream.length; i++) {
    const cur = stream[i];
    if (!cur.text) continue; // blank = off marker, handled as a boundary below
    const start = cur.startMs / 1000;
    const next = stream[i + 1];
    const end = next ? next.startMs / 1000 : start + DEFAULT_TAIL;
    doc.cues.push({ id: newCueId(), start, end, text: cur.text });
  }
  return doc;
}

export function serializeSmi(doc: SubtitleDocument): string {
  const cls = doc.meta.smiMainClass ?? "UNKNOWNCC";
  const head =
    doc.meta.smiHead ??
    `<TITLE>Glyphline</TITLE>\n<STYLE TYPE="text/css"><!--\nP { font-family: sans-serif; color: white; }\n.${cls} { Name: Track; lang: ko-KR; }\n--></STYLE>`;

  const body: string[] = [];
  const cues = [...doc.cues].sort((a, b) => a.start - b.start);
  cues.forEach((cue, i) => {
    const startMs = Math.round(cue.start * 1000);
    // ASS cues carry inline override tags in assSpans → convert the representable
    // subset to SMI HTML. Plain cues just get entity-encoded text + <br>.
    const inner = cue.assSpans?.length ? spansToSmiHtml(cue.assSpans).html : textToSmi(cue.text);
    body.push(`<SYNC Start=${startMs}><P Class=${cls}>${inner}`);
    // Insert an off marker at this cue's end unless the next cue starts there.
    const next = cues[i + 1];
    const endMs = Math.round(cue.end * 1000);
    if (!next || Math.round(next.start * 1000) > endMs) {
      body.push(`<SYNC Start=${endMs}><P Class=${cls}>&nbsp;`);
    }
  });

  return `<SAMI>\n<HEAD>\n${head}\n</HEAD>\n<BODY>\n${body.join("\n")}\n</BODY>\n</SAMI>\n`;
}

// Find where the tag that produced `innerStart` actually begins (back up to '<').
function findTagStart(src: string, innerStart: number): number {
  const lt = src.lastIndexOf("<", innerStart);
  return lt === -1 ? innerStart : lt;
}

function smiInnerToText(inner: string): string {
  let t = inner;
  // Stop at the next </SYNC> or trailing tags we don't want.
  t = t.replace(/<\/?(sync|body|sami)\b[^>]*>/gi, "");
  t = t.replace(/<p\b[^>]*>/gi, ""); // opening <P ...>
  t = t.replace(/<\/p>/gi, "");
  t = t.replace(/<br\s*\/?>/gi, "\n");
  t = t.replace(/<[^>]+>/g, ""); // strip any remaining tags
  t = decodeEntities(t);
  return t.trim();
}

function textToSmi(text: string): string {
  return encodeEntities(text).replace(/\n/g, "<br>");
}

// ─── ASS spans -> SMI HTML ─────────────────────────────────────────────────────

interface SmiFormatState {
  b: boolean;
  i: boolean;
  u: boolean;
  s: boolean;
  color: string | null;
  face: string | null;
  size: string | null;
  drawing: boolean;
}

function freshState(): SmiFormatState {
  return { b: false, i: false, u: false, s: false, color: null, face: null, size: null, drawing: false };
}

/**
 * Convert ASS spans to SMI HTML. Representable formatting (bold/italic/underline/
 * strikeout, primary colour, font name/size) becomes HTML tags; everything else
 * (position, animation, karaoke, clip, drawing, …) is dropped and recorded so the
 * caller can warn about the loss. Each text run is wrapped independently to keep
 * the markup well-formed despite ASS's toggle-style tags.
 */
export function spansToSmiHtml(spans: AssSpan[]): { html: string; dropped: Set<LossCategory> } {
  const state = freshState();
  const dropped = new Set<LossCategory>();
  let html = "";

  for (const span of spans) {
    if (span.tags) applyTags(span.tags, state, dropped);
    if (state.drawing) continue; // drawing coordinates are not text
    const txt = encodeEntities(span.text).replace(/\\N/g, "<br>").replace(/\\h/g, "&nbsp;");
    if (!txt) continue;
    html += wrapRun(txt, state);
  }
  return { html, dropped };
}

function applyTags(block: string, state: SmiFormatState, dropped: Set<LossCategory>) {
  for (const { name, arg, known } of decodeTags(block)) {
    switch (name) {
      case "b": state.b = arg !== "0" && arg !== ""; break;
      case "i": state.i = arg !== "0" && arg !== ""; break;
      case "u": state.u = arg !== "0" && arg !== ""; break;
      case "s": state.s = arg !== "0" && arg !== ""; break;
      case "c":
      case "1c": state.color = assColorToHex(arg); break;
      case "fn": state.face = arg || null; break;
      case "fs": state.size = arg || null; break;
      case "p":
        state.drawing = Number(arg) > 0;
        if (state.drawing) dropped.add("drawing"); // the vector shape is lost
        break;
      case "pbo": break; // baseline offset for drawing — ignore quietly
      case "r": Object.assign(state, freshState()); break; // reset formatting
      default:
        if (!known || !SMI_REPRESENTABLE.has(name)) dropped.add(categorizeTag(name));
    }
  }
}

function wrapRun(txt: string, s: SmiFormatState): string {
  const open: string[] = [];
  const close: string[] = [];
  const fontAttrs: string[] = [];
  if (s.color) fontAttrs.push(`color="${s.color}"`);
  if (s.face) fontAttrs.push(`face="${s.face}"`);
  if (s.size) fontAttrs.push(`size="${s.size}"`);
  if (fontAttrs.length) {
    open.push(`<font ${fontAttrs.join(" ")}>`);
    close.unshift("</font>");
  }
  for (const tag of ["b", "i", "u", "s"] as const) {
    if (s[tag]) {
      open.push(`<${tag}>`);
      close.unshift(`</${tag}>`);
    }
  }
  return open.join("") + txt + close.join("");
}

/** Categories of ASS information that would be lost exporting this doc to SMI. */
export function smiExportLoss(doc: SubtitleDocument): LossCategory[] {
  const all = new Set<LossCategory>();
  for (const cue of doc.cues) {
    if (!cue.assSpans?.length) continue;
    for (const c of spansToSmiHtml(cue.assSpans).dropped) all.add(c);
  }
  return [...all];
}

function decodeEntities(s: string): string {
  return s
    .replace(/&nbsp;/gi, " ")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/gi, "&");
}

function encodeEntities(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
