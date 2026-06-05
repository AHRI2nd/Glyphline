// Format registry. Adding a new external format = one adapter file + one entry.

import type { SubFormat, SubtitleDocument } from "../types/subtitle";
import { NATIVE_EXT } from "../types/subtitle";
import { parseGlyph, serializeGlyph } from "./glyph";
import { parseSrt, serializeSrt } from "./srt";
import { parseVtt, serializeVtt } from "./vtt";
import { parseAss, serializeAss } from "./ass";
import { parseSmi, serializeSmi } from "./smi";

export interface FormatAdapter {
  id: SubFormat;
  label: string;
  extensions: string[]; // first is the canonical/default extension
  parse: (raw: string) => SubtitleDocument;
  serialize: (doc: SubtitleDocument) => string;
}

export const EXTERNAL_ADAPTERS: FormatAdapter[] = [
  { id: "srt", label: "SubRip (.srt)", extensions: ["srt"], parse: parseSrt, serialize: serializeSrt },
  { id: "vtt", label: "WebVTT (.vtt)", extensions: ["vtt"], parse: parseVtt, serialize: serializeVtt },
  { id: "ass", label: "ASS/SSA (.ass)", extensions: ["ass", "ssa"], parse: parseAss, serialize: serializeAss },
  { id: "smi", label: "SAMI (.smi)", extensions: ["smi", "sami"], parse: parseSmi, serialize: serializeSmi },
];

/** Every extension we can open, including the native project file. */
export function openExtensions(): string[] {
  return [NATIVE_EXT, ...EXTERNAL_ADAPTERS.flatMap((a) => a.extensions)];
}

export function extensionOf(path: string): string {
  const dot = path.lastIndexOf(".");
  return dot === -1 ? "" : path.slice(dot + 1).toLowerCase();
}

export function adapterForFormat(format: SubFormat): FormatAdapter {
  const a = EXTERNAL_ADAPTERS.find((x) => x.id === format);
  if (!a) throw new Error(`알 수 없는 포맷: ${format}`);
  return a;
}

function adapterForExtension(ext: string): FormatAdapter | null {
  return EXTERNAL_ADAPTERS.find((a) => a.extensions.includes(ext)) ?? null;
}

/** Detect by extension; returns "glyph" for the native file, else a SubFormat, else null. */
export function detectFormat(path: string): "glyph" | SubFormat | null {
  const ext = extensionOf(path);
  if (ext === NATIVE_EXT) return "glyph";
  return adapterForExtension(ext)?.id ?? null;
}

/** Parse file content based on its path's extension. */
export function parseByPath(path: string, raw: string): SubtitleDocument {
  const fmt = detectFormat(path);
  if (fmt === "glyph") return parseGlyph(raw);
  if (fmt) return adapterForFormat(fmt).parse(raw);
  throw new Error(`지원하지 않는 확장자입니다: ${path}`);
}

export { parseGlyph, serializeGlyph };
