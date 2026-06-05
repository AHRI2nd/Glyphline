// ASS inline override-tag handling.
//
// A Dialogue Text field interleaves override blocks "{...}" with literal text.
// We model it as a sequence of spans (optional tags + the text run that follows),
// which lets us round-trip EVERY tag — known or not — byte-for-byte, while still
// exposing a structured decode for editing/inspection.

import type { AssSpan } from "../types/subtitle";

// Full standard ASS/SSA override tag names. Multi-char and digit-prefixed names
// (e.g. "1c", "alpha") are matched longest-first so "\alpha" wins over "\a".
const KNOWN_TAGS = [
  // font
  "fn", "fs", "fscx", "fscy", "fsp", "fe",
  // rotation / shear
  "frx", "fry", "frz", "fr", "fax", "fay",
  // weight / decoration
  "b", "i", "u", "s",
  // border / shadow / blur
  "xbord", "ybord", "bord", "xshad", "yshad", "shad", "be", "blur",
  // colours / alpha
  "1c", "2c", "3c", "4c", "c", "1a", "2a", "3a", "4a", "alpha",
  // alignment / wrap
  "an", "a", "q",
  // karaoke
  "kf", "ko", "kt", "k", "K",
  // position / movement / origin
  "pos", "move", "org",
  // fade
  "fade", "fad",
  // animation / clip
  "t", "iclip", "clip",
  // drawing
  "pbo", "p",
  // reset
  "r",
].sort((a, b) => b.length - a.length);

const KNOWN_SET = new Set(KNOWN_TAGS);

export interface DecodedTag {
  name: string; // e.g. "pos", "b", "1c"
  arg: string; // raw argument, e.g. "(100,200)", "1", "&H00FF00&"
  known: boolean;
}

const BLOCK_RE = /\{([^}]*)\}/g;

/** Split a Dialogue Text field into override/text spans (lossless). */
export function parseAssText(raw: string): AssSpan[] {
  const matches = [...raw.matchAll(BLOCK_RE)];
  if (matches.length === 0) return [{ text: raw }];

  const spans: AssSpan[] = [];
  // Any literal text before the first override block.
  const firstIdx = matches[0].index ?? 0;
  if (firstIdx > 0) spans.push({ text: raw.slice(0, firstIdx) });

  for (let i = 0; i < matches.length; i++) {
    const tags = matches[i][1];
    const blockStart = matches[i].index ?? 0;
    const textStart = blockStart + matches[i][0].length;
    const textEnd = i + 1 < matches.length ? matches[i + 1].index ?? raw.length : raw.length;
    spans.push({ tags, text: raw.slice(textStart, textEnd) });
  }
  return spans;
}

/** Reconstruct the exact Dialogue Text field from spans. */
export function serializeAssText(spans: AssSpan[]): string {
  return spans.map((s) => (s.tags != null ? `{${s.tags}}` : "") + s.text).join("");
}

/** True while a span list is inside a vector-drawing region (\p1..\p0). */
function drawingAfter(tags: string | undefined, current: boolean): boolean {
  if (!tags) return current;
  // "\p<digits>" toggles drawing (\p1.. on, \p0 off). "\pos"/"\pbo" do NOT match.
  const ms = [...tags.matchAll(/\\p(\d+)/g)];
  if (!ms.length) return current;
  return Number(ms[ms.length - 1][1]) > 0;
}

/**
 * Editable plain text: drop override blocks, drop vector-drawing coordinates
 * (\p regions — those are shape commands, not readable text), normalize hard
 * breaks/spaces.
 */
export function spansToPlain(spans: AssSpan[]): string {
  let drawing = false;
  let out = "";
  for (const s of spans) {
    drawing = drawingAfter(s.tags, drawing);
    if (drawing) continue; // skip drawing-command text
    out += s.text;
  }
  return out.replace(/\\N/g, "\n").replace(/\\h/g, " ");
}

// ─── Tag categorization (for lossy-export warnings) ───────────────────────────

/** Tags SMI can represent as HTML formatting (handled, not dropped). */
export const SMI_REPRESENTABLE = new Set(["b", "i", "u", "s", "c", "1c", "fn", "fs", "r", "p", "pbo"]);

export type LossCategory =
  | "position"
  | "karaoke"
  | "animation"
  | "transform"
  | "borderShadow"
  | "drawing"
  | "clip"
  | "color"
  | "other";

/** Map an override tag name to a loss category for user-facing warnings. */
export function categorizeTag(name: string): LossCategory {
  if (["pos", "move", "org", "an", "a", "q"].includes(name)) return "position";
  if (["k", "kf", "ko", "kt", "K"].includes(name)) return "karaoke";
  if (["t", "fad", "fade"].includes(name)) return "animation";
  if (["frx", "fry", "frz", "fax", "fay", "fscx", "fscy", "fsp"].includes(name)) return "transform";
  if (["bord", "xbord", "ybord", "shad", "xshad", "yshad", "be", "blur"].includes(name)) return "borderShadow";
  if (["p", "pbo"].includes(name)) return "drawing";
  if (["clip", "iclip"].includes(name)) return "clip";
  if (["2c", "3c", "4c", "alpha", "1a", "2a", "3a", "4a"].includes(name)) return "color";
  return "other";
}

/** The opening override block (line-level tags like \pos/\an/\fad), if any. */
export function leadingBlock(spans: AssSpan[] | undefined): string | null {
  return spans && spans[0]?.tags ? spans[0].tags : null;
}

/**
 * Decode one override block's tag string into structured tags. Preserves order
 * and unknown tags (with known=false). For UI/inspection — not used for the
 * lossless round-trip, which reuses the raw block verbatim.
 */
export function decodeTags(block: string): DecodedTag[] {
  const out: DecodedTag[] = [];
  let i = 0;
  while (i < block.length) {
    if (block[i] !== "\\") {
      i++;
      continue;
    }
    i++; // consume backslash
    // Longest-known-prefix match, else read leading letters as an unknown name.
    let name: string | null = null;
    for (const k of KNOWN_TAGS) {
      if (block.startsWith(k, i)) {
        name = k;
        break;
      }
    }
    if (name == null) {
      const m = /^[A-Za-z]+/.exec(block.slice(i));
      name = m ? m[0] : "";
    }
    let j = i + name.length;
    let arg = "";
    if (block[j] === "(") {
      // Parenthesized arg with nesting (e.g. \t(\frz360), \clip(...)).
      let depth = 0;
      let k = j;
      for (; k < block.length; k++) {
        if (block[k] === "(") depth++;
        else if (block[k] === ")") {
          depth--;
          if (depth === 0) {
            k++;
            break;
          }
        }
      }
      arg = block.slice(j, k);
      j = k;
    } else {
      let k = j;
      while (k < block.length && block[k] !== "\\") k++;
      arg = block.slice(j, k);
      j = k;
    }
    out.push({ name, arg, known: KNOWN_SET.has(name) });
    i = j;
  }
  return out;
}

/** Does this span list carry any override tags? (for UI indicators) */
export function hasOverrideTags(spans: AssSpan[] | undefined): boolean {
  return !!spans?.some((s) => s.tags && s.tags.length > 0);
}
