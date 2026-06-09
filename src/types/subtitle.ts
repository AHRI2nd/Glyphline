// Glyphline canonical data model.
//
// The whole app edits a single in-memory `SubtitleDocument`. External formats
// (SRT/VTT/ASS/SMI) are adapters that parse into / serialize out of this model;
// the native `.glyph` (JSON) format persists it losslessly.

export type SubFormat = "srt" | "vtt" | "ass" | "smi";

/** The native project extension. */
export const NATIVE_EXT = "glyph";

/**
 * Word/character-level timing inside a cue. Reserved for karaoke, enhanced LRC
 * and AI forced-alignment word timing. Only `.glyph` round-trips these losslessly;
 * VTT (inline timestamps) and ASS (\k tags) map partially, SRT/SMI flatten them.
 */
export interface SyncToken {
  text: string; // a word or character
  start: number; // seconds (absolute, not relative to cue.start)
  end: number; // seconds
  confidence?: number; // AI alignment confidence 0..1 (optional)
}

/**
 * One run of the ASS Dialogue text: an optional override block ("{...}" content
 * WITHOUT braces, verbatim) followed by literal text. Preserves every inline tag
 * losslessly, known or not. See src/formats/assTags.ts.
 */
export interface AssSpan {
  tags?: string;
  text: string;
}

export interface Cue {
  id: string;
  start: number; // seconds (internal time is always float seconds)
  end: number; // seconds (required)
  text: string; // may contain "\n" (line breaks preserved)
  translation?: string; // parallel translation text — .glyph-only (external export uses `text`)
  tokens?: SyncToken[]; // word/char sync; when present, keep in sync with start/end
  assSpans?: AssSpan[]; // ASS inline override tags + text runs (lossless round-trip)
  style?: string; // ASS style name
  layer?: number; // ASS layer
  actor?: string; // ASS Name field
  position?: { x: number; y: number } | null;
  raw?: Record<string, string>; // format-specific unparsed fields (round-trip fidelity)
}

export interface AssStyle {
  name: string;
  fontName: string;
  fontSize: number;
  primaryColour: string;
  outlineColour: string;
  backColour: string;
  bold: boolean;
  italic: boolean;
  outline: number;
  shadow: number;
  alignment: number;
  marginL: number;
  marginR: number;
  marginV: number;
  raw?: Record<string, string>; // unparsed style columns
}

/**
 * A file embedded in an ASS script's [Fonts] or [Graphics] section. `data` is the
 * raw UU-encoded payload lines (joined with "\n"), preserved verbatim for lossless
 * round-trip; we never decode it on parse. See src/formats/ass.ts.
 */
export interface AssEmbedded {
  name: string; // the `fontname:` / `filename:` value
  data: string; // raw encoded data lines, verbatim
}

export interface SubtitleDocument {
  format: SubFormat; // original / last external format (export default hint)
  frameRate?: number; // reserved for timecode conversion (unused for now)
  styles?: AssStyle[]; // ASS/SSA only
  fonts?: AssEmbedded[]; // ASS [Fonts] — embedded font files (lossless)
  graphics?: AssEmbedded[]; // ASS [Graphics] — embedded images (lossless)
  cues: Cue[];
  meta: Record<string, string>; // VTT header / ASS [Script Info] / SMI <STYLE> etc.
}

/** Native .glyph wrapper: lossless serialization + version migration. */
export interface GlyphFile {
  schemaVersion: number; // currently 1; load branches on this for migration
  document: SubtitleDocument;
}

export const GLYPH_SCHEMA_VERSION = 1;

let _idCounter = 0;
/** Stable-enough unique id for cues created at runtime. */
export function newCueId(): string {
  _idCounter += 1;
  return `cue-${Date.now().toString(36)}-${_idCounter.toString(36)}`;
}

export function emptyDocument(format: SubFormat = "srt"): SubtitleDocument {
  return { format, cues: [], meta: {} };
}
