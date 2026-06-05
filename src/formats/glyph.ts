// Native .glyph format — lossless JSON serialization of SubtitleDocument.
//
// This is the canonical save format. Everything in the model (cues, tokens,
// styles, meta) round-trips exactly. External formats are lossy "exports".

import {
  GLYPH_SCHEMA_VERSION,
  type GlyphFile,
  type SubtitleDocument,
  emptyDocument,
} from "../types/subtitle";

export function serializeGlyph(doc: SubtitleDocument): string {
  const file: GlyphFile = {
    schemaVersion: GLYPH_SCHEMA_VERSION,
    document: doc,
  };
  return JSON.stringify(file, null, 2);
}

export function parseGlyph(raw: string): SubtitleDocument {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    throw new Error(`.glyph 파싱 실패: ${(e as Error).message}`);
  }

  const file = parsed as Partial<GlyphFile>;
  if (!file || typeof file !== "object" || !file.document) {
    throw new Error(".glyph 형식이 올바르지 않습니다 (document 누락).");
  }

  return migrate(file.schemaVersion ?? 1, file.document);
}

/**
 * Apply forward migrations. Unknown fields on the document are preserved as-is
 * (we never strip data we don't recognize). Add cases here as the schema grows.
 */
function migrate(version: number, doc: SubtitleDocument): SubtitleDocument {
  // v1 is the current schema — no transforms yet.
  if (version > GLYPH_SCHEMA_VERSION) {
    // File written by a newer app version. Load defensively rather than fail.
    console.warn(
      `.glyph schemaVersion ${version} is newer than supported ${GLYPH_SCHEMA_VERSION}; loading as-is.`,
    );
  }
  return {
    ...emptyDocument(doc.format ?? "srt"),
    ...doc,
    cues: Array.isArray(doc.cues) ? doc.cues : [],
    meta: doc.meta ?? {},
  };
}
