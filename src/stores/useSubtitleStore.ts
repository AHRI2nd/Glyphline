import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import {
  emptyDocument,
  newCueId,
  type AssStyle,
  type Cue,
  type SubFormat,
  type SubtitleDocument,
} from "../types/subtitle";
import {
  adapterForFormat,
  parseByPath,
  serializeGlyph,
} from "../formats";
import { sortedCues } from "../formats/srt";

const MAX_HISTORY = 50;

interface SubtitleState {
  doc: SubtitleDocument;
  filePath: string | null;
  fileName: string | null;
  isDirty: boolean;
  activeCueId: string | null;
  selectedIds: Set<string>;

  _history: SubtitleDocument[];
  _future: SubtitleDocument[];

  canUndo: () => boolean;
  canRedo: () => boolean;

  // file lifecycle
  newDocument: () => void;
  openPath: (path: string) => Promise<void>;
  loadFromRaw: (raw: string, format: SubFormat) => void;
  /** Restore a document from the crash-recovery autosave (stays dirty until saved). */
  restoreDoc: (doc: SubtitleDocument, filePath: string | null, fileName: string | null) => void;
  saveNativePath: (path: string) => Promise<void>;
  /**
   * Write the doc in an external format. `source: "translation"` exports the
   * translation column as the body text (cues without one fall back to the
   * original); ASS spans/tokens are dropped there — they align to the original.
   */
  exportPath: (path: string, format: SubFormat, source?: "text" | "translation") => Promise<void>;
  serializeCurrent: () => string;

  // selection
  setActiveCue: (id: string | null) => void;
  toggleSelect: (id: string, additive: boolean) => void;
  clearSelection: () => void;

  // editing
  updateCue: (id: string, patch: Partial<Omit<Cue, "id">>) => void;
  /** Apply many cue patches as ONE undo step (find&replace "replace all" etc.). */
  batchUpdateCues: (edits: Array<{ id: string; patch: Partial<Omit<Cue, "id">> }>) => void;
  /** Clamp each cue's end to the next cue's start (sorted order). Returns #fixed. */
  fixOverlaps: () => number;
  /** Shrink cue ends so every cue is followed by at least `gapSec` of silence. Returns #changed. */
  applyMinGap: (gapSec: number) => number;
  /** Stretch/shrink each cue's end to sit within [minSec, maxSec] (never past the next cue). Returns #changed. */
  applyDurationLimits: (minSec: number, maxSec: number) => number;
  /** Delete cues whose text (and translation) is blank. Returns #removed. */
  removeEmptyCues: () => number;
  /** Transform cue text casing (all cues, or only the current selection). Returns #changed. */
  changeCase: (mode: "upper" | "lower" | "sentence" | "title", scope: "all" | "selected") => number;
  /** Strip bracket/parenthesis annotations, e.g. "(door slams)", "[music]". Returns #changed. */
  removeHearingImpaired: () => number;
  /**
   * Two-point linear sync: remaps every cue/token timestamp so that `srcA`→`dstA`
   * and `srcB`→`dstB`, linearly interpolating (and extrapolating) everything else.
   * Returns false if the two source points coincide (undefined transform).
   */
  applyPointSync: (srcA: number, dstA: number, srcB: number, dstB: number) => boolean;
  /** Multiply every timestamp by `factor` (framerate conversion etc.). Returns false for factor ≤ 0. */
  changeSpeed: (factor: number) => boolean;
  /** Merge adjacent cues showing the same text with a small gap between them. Returns #cues removed. */
  mergeSameText: () => number;
  /** Merge cues sharing identical start+end (stacked lines) into one, joining text. Returns #cues removed. */
  mergeSameTimecodes: () => number;
  addCue: () => void;
  addCueAt: (start: number, end: number) => void;
  insertCueAfter: (id: string) => void;
  deleteCues: (ids: string[]) => void;
  splitCue: (id: string, atTime: number) => void;
  mergeCues: (ids: string[]) => void;
  shiftTime: (deltaSec: number, scope: "all" | "selected") => void;

  // styles (ASS)
  addStyle: () => void;
  updateStyle: (name: string, patch: Partial<AssStyle>) => void;
  deleteStyle: (name: string) => void;

  undo: () => void;
  redo: () => void;
}

function clone(doc: SubtitleDocument): SubtitleDocument {
  return structuredClone(doc);
}

function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

/** Text transform for changeCase. Sentence/title casing is line-aware. */
function casingTransform(mode: "upper" | "lower" | "sentence" | "title"): (s: string) => string {
  switch (mode) {
    case "upper":
      return (s) => s.toUpperCase();
    case "lower":
      return (s) => s.toLowerCase();
    case "sentence":
      // Capitalize the first letter of each line; lowercase the rest.
      return (s) =>
        s
          .split("\n")
          .map((line) => {
            const lower = line.toLowerCase();
            const i = lower.search(/\p{L}/u);
            return i === -1 ? line : lower.slice(0, i) + lower[i].toUpperCase() + lower.slice(i + 1);
          })
          .join("\n");
    case "title":
      // Capitalize the first letter of every word.
      return (s) => s.toLowerCase().replace(/\p{L}+/gu, (w) => w[0].toUpperCase() + w.slice(1));
  }
}

/**
 * Remove hearing-impaired annotations: bracketed/parenthesized runs like
 * "[music]", "(door slams)", "♪ lyrics ♪", and leading "NAME:" speaker labels.
 * Cleans up leftover whitespace and drops lines that become empty.
 */
function stripHearingImpaired(text: string): string {
  return text
    .split("\n")
    .map((line) =>
      line
        .replace(/\[[^\]]*\]|\([^)]*\)|（[^）]*）|【[^】]*】/g, "") // bracketed SFX
        .replace(/♪[^♪]*♪|♪.*$/g, "") // music lines
        .replace(/^\s*[-–—]?\s*[\p{Lu}][\p{Lu} .'-]{1,20}:\s*/u, "") // "NAME: "
        .replace(/\s{2,}/g, " ")
        .trim(),
    )
    .filter((line) => line !== "")
    .join("\n");
}

function uniqueStyleName(styles: AssStyle[], base: string): string {
  const names = new Set(styles.map((s) => s.name));
  if (!names.has(base)) return base;
  let i = 2;
  while (names.has(`${base} ${i}`)) i++;
  return `${base} ${i}`;
}

export const useSubtitleStore = create<SubtitleState>((set, get) => {
  /** Snapshot current doc into history before a mutation (Lyrical Sync pattern). */
  function pushHistory() {
    const { doc, _history } = get();
    set({
      _history: [..._history.slice(-(MAX_HISTORY - 1)), clone(doc)],
      _future: [],
      isDirty: true,
    });
  }

  /** Replace cues with a fresh array (keeps doc-level fields). */
  function withCues(cues: Cue[]): SubtitleDocument {
    return { ...get().doc, cues };
  }

  /**
   * Shared by fixOverlaps (gapSec=0) and applyMinGap: shrink each cue's end so
   * it's followed by at least `gapSec` before the next cue starts (sorted order).
   * Returns the number of cues changed.
   */
  function applyGapClamps(gapSec: number): number {
    const sorted = sortedCues(get().doc.cues);
    const clamps = new Map<string, number>();
    for (let i = 0; i < sorted.length - 1; i++) {
      const cur = sorted[i];
      const next = sorted[i + 1];
      if (next.start - cur.end < gapSec) {
        clamps.set(cur.id, Math.max(cur.start + 0.001, next.start - gapSec));
      }
    }
    if (!clamps.size) return 0;
    pushHistory();
    set({
      doc: withCues(get().doc.cues.map((c) => (clamps.has(c.id) ? { ...c, end: clamps.get(c.id)! } : c))),
    });
    return clamps.size;
  }

  return {
    doc: emptyDocument("srt"),
    filePath: null,
    fileName: null,
    isDirty: false,
    activeCueId: null,
    selectedIds: new Set(),
    _history: [],
    _future: [],

    canUndo: () => get()._history.length > 0,
    canRedo: () => get()._future.length > 0,

    newDocument: () =>
      set({
        doc: emptyDocument("srt"),
        filePath: null,
        fileName: null,
        isDirty: false,
        activeCueId: null,
        selectedIds: new Set(),
        _history: [],
        _future: [],
      }),

    openPath: async (path) => {
      const raw = await invoke<string>("read_text_file", { path });
      const doc = parseByPath(path, raw);
      set({
        doc,
        filePath: path,
        fileName: baseName(path),
        isDirty: false,
        activeCueId: doc.cues[0]?.id ?? null,
        selectedIds: new Set(),
        _history: [],
        _future: [],
      });
    },

    loadFromRaw: (raw, format) => {
      const doc = adapterForFormat(format).parse(raw);
      pushHistory();
      set({ doc, activeCueId: doc.cues[0]?.id ?? null, selectedIds: new Set() });
    },

    restoreDoc: (doc, filePath, fileName) =>
      set({
        doc,
        filePath,
        fileName,
        isDirty: true, // recovered content is unsaved by definition
        activeCueId: doc.cues[0]?.id ?? null,
        selectedIds: new Set(),
        _history: [],
        _future: [],
      }),

    saveNativePath: async (path) => {
      const content = serializeGlyph(get().doc);
      await invoke("write_text_file", { path, content });
      set({ filePath: path, fileName: baseName(path), isDirty: false });
    },

    exportPath: async (path, format, source = "text") => {
      let doc = get().doc;
      if (source === "translation") {
        doc = {
          ...doc,
          cues: doc.cues.map((c) => ({
            ...c,
            text: c.translation?.trim() ? c.translation : c.text,
            assSpans: undefined, // spans/tokens describe the ORIGINAL text
            tokens: undefined,
          })),
        };
      }
      const content = adapterForFormat(format).serialize(doc);
      await invoke("write_text_file", { path, content });
    },

    serializeCurrent: () => {
      const { doc } = get();
      const fmt = doc.format;
      return adapterForFormat(fmt).serialize(doc);
    },

    setActiveCue: (id) => set({ activeCueId: id }),

    toggleSelect: (id, additive) =>
      set((s) => {
        const next = new Set(additive ? s.selectedIds : []);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        return { selectedIds: next, activeCueId: id };
      }),

    clearSelection: () => set({ selectedIds: new Set() }),

    updateCue: (id, patch) => {
      pushHistory();
      set({ doc: withCues(get().doc.cues.map((c) => (c.id === id ? { ...c, ...patch } : c))) });
    },

    batchUpdateCues: (edits) => {
      if (!edits.length) return;
      pushHistory();
      const byId = new Map(edits.map((e) => [e.id, e.patch]));
      set({
        doc: withCues(
          get().doc.cues.map((c) => {
            const patch = byId.get(c.id);
            return patch ? { ...c, ...patch } : c;
          }),
        ),
      });
    },

    fixOverlaps: () => applyGapClamps(0),
    applyMinGap: (gapSec) => applyGapClamps(gapSec),

    applyDurationLimits: (minSec, maxSec) => {
      const sorted = sortedCues(get().doc.cues);
      const patches = new Map<string, number>(); // id -> new end
      for (let i = 0; i < sorted.length; i++) {
        const cue = sorted[i];
        const next = sorted[i + 1];
        let end = cue.end;
        const dur = end - cue.start;
        if (dur > maxSec) {
          end = cue.start + maxSec;
        } else if (dur < minSec) {
          // Extend toward minSec, but never past (nearly) the next cue's start.
          const cap = next ? Math.max(cue.start + 0.001, next.start - 0.001) : Infinity;
          end = Math.min(cue.start + minSec, cap);
        }
        if (end !== cue.end) patches.set(cue.id, end);
      }
      if (!patches.size) return 0;
      pushHistory();
      set({
        doc: withCues(
          get().doc.cues.map((c) => (patches.has(c.id) ? { ...c, end: patches.get(c.id)! } : c)),
        ),
      });
      return patches.size;
    },

    removeEmptyCues: () => {
      const empty = get().doc.cues.filter(
        (c) => c.text.trim() === "" && (c.translation ?? "").trim() === "",
      );
      if (!empty.length) return 0;
      pushHistory();
      const idSet = new Set(empty.map((c) => c.id));
      set((s) => ({
        doc: withCues(s.doc.cues.filter((c) => !idSet.has(c.id))),
        selectedIds: new Set([...s.selectedIds].filter((id) => !idSet.has(id))),
        activeCueId: s.activeCueId && idSet.has(s.activeCueId) ? null : s.activeCueId,
      }));
      return empty.length;
    },

    changeCase: (mode, scope) => {
      const { selectedIds, doc } = get();
      const targets =
        scope === "selected" ? doc.cues.filter((c) => selectedIds.has(c.id)) : doc.cues;
      if (!targets.length) return 0;
      const transform = casingTransform(mode);
      const idSet = new Set(targets.map((c) => c.id));
      const changed = targets.filter((c) => transform(c.text) !== c.text).length;
      if (!changed) return 0;
      pushHistory();
      set({
        doc: withCues(doc.cues.map((c) => (idSet.has(c.id) ? { ...c, text: transform(c.text) } : c))),
      });
      return changed;
    },

    removeHearingImpaired: () => {
      const { doc } = get();
      const patches = new Map<string, string>();
      for (const cue of doc.cues) {
        const next = stripHearingImpaired(cue.text);
        if (next !== cue.text) patches.set(cue.id, next);
      }
      if (!patches.size) return 0;
      pushHistory();
      set({
        doc: withCues(doc.cues.map((c) => (patches.has(c.id) ? { ...c, text: patches.get(c.id)! } : c))),
      });
      return patches.size;
    },

    applyPointSync: (srcA, dstA, srcB, dstB) => {
      if (srcB === srcA) return false;
      const scale = (dstB - dstA) / (srcB - srcA);
      const remap = (t: number) => dstA + (t - srcA) * scale;
      pushHistory();
      set({
        doc: withCues(
          get().doc.cues.map((c) => ({
            ...c,
            start: Math.max(0, remap(c.start)),
            end: Math.max(0, remap(c.end)),
            tokens: c.tokens?.map((tk) => ({
              ...tk,
              start: Math.max(0, remap(tk.start)),
              end: Math.max(0, remap(tk.end)),
            })),
          })),
        ),
      });
      return true;
    },

    changeSpeed: (factor) => {
      if (!(factor > 0)) return false;
      pushHistory();
      const scale = (t: number) => t * factor;
      set({
        doc: withCues(
          get().doc.cues.map((c) => ({
            ...c,
            start: scale(c.start),
            end: scale(c.end),
            tokens: c.tokens?.map((tk) => ({ ...tk, start: scale(tk.start), end: scale(tk.end) })),
          })),
        ),
      });
      return true;
    },

    mergeSameText: () => {
      // Same trimmed text AND nearly contiguous (≤250 ms gap, Subtitle Edit's
      // default) — a repeat minutes later is intentional and must NOT merge.
      const MAX_GAP = 0.25;
      const sorted = sortedCues(get().doc.cues);
      const removed = new Set<string>();
      const extend = new Map<string, number>(); // survivor id -> new end
      let survivor: Cue | null = null;
      for (const cue of sorted) {
        if (
          survivor &&
          cue.text.trim() === survivor.text.trim() &&
          cue.start - (extend.get(survivor.id) ?? survivor.end) <= MAX_GAP
        ) {
          removed.add(cue.id);
          extend.set(survivor.id, Math.max(extend.get(survivor.id) ?? survivor.end, cue.end));
        } else {
          survivor = cue;
        }
      }
      if (!removed.size) return 0;
      pushHistory();
      set((s) => ({
        doc: withCues(
          s.doc.cues
            .filter((c) => !removed.has(c.id))
            .map((c) => (extend.has(c.id) ? { ...c, end: extend.get(c.id)! } : c)),
        ),
        selectedIds: new Set([...s.selectedIds].filter((id) => !removed.has(id))),
        activeCueId: s.activeCueId && removed.has(s.activeCueId) ? null : s.activeCueId,
      }));
      return removed.size;
    },

    mergeSameTimecodes: () => {
      // Identical start+end (±1 ms): stacked lines → one cue, texts joined.
      const EPS = 0.001;
      const sorted = sortedCues(get().doc.cues);
      const removed = new Set<string>();
      const joined = new Map<string, string>(); // survivor id -> combined text
      let survivor: Cue | null = null;
      for (const cue of sorted) {
        if (
          survivor &&
          Math.abs(cue.start - survivor.start) <= EPS &&
          Math.abs(cue.end - survivor.end) <= EPS
        ) {
          removed.add(cue.id);
          joined.set(survivor.id, `${joined.get(survivor.id) ?? survivor.text}\n${cue.text}`);
        } else {
          survivor = cue;
        }
      }
      if (!removed.size) return 0;
      pushHistory();
      set((s) => ({
        doc: withCues(
          s.doc.cues
            .filter((c) => !removed.has(c.id))
            .map((c) => (joined.has(c.id) ? { ...c, text: joined.get(c.id)! } : c)),
        ),
        selectedIds: new Set([...s.selectedIds].filter((id) => !removed.has(id))),
        activeCueId: s.activeCueId && removed.has(s.activeCueId) ? null : s.activeCueId,
      }));
      return removed.size;
    },

    addCue: () => {
      pushHistory();
      const cues = get().doc.cues;
      const last = sortedCues(cues).at(-1);
      const start = last ? last.end + 0.001 : 0;
      const cue: Cue = { id: newCueId(), start, end: start + 2, text: "" };
      set({ doc: withCues([...cues, cue]), activeCueId: cue.id });
    },

    addCueAt: (start, end) => {
      pushHistory();
      const cue: Cue = { id: newCueId(), start, end: Math.max(end, start + 0.001), text: "" };
      set({ doc: withCues([...get().doc.cues, cue]), activeCueId: cue.id });
    },

    insertCueAfter: (id) => {
      pushHistory();
      const cues = get().doc.cues;
      const ref = cues.find((c) => c.id === id);
      const start = ref ? ref.end + 0.001 : 0;
      const cue: Cue = { id: newCueId(), start, end: start + 2, text: "" };
      const idx = cues.findIndex((c) => c.id === id);
      const next = [...cues];
      next.splice(idx + 1, 0, cue);
      set({ doc: withCues(next), activeCueId: cue.id });
    },

    deleteCues: (ids) => {
      if (!ids.length) return;
      pushHistory();
      const idSet = new Set(ids);
      set((s) => ({
        doc: withCues(s.doc.cues.filter((c) => !idSet.has(c.id))),
        selectedIds: new Set(),
        activeCueId: null,
      }));
    },

    splitCue: (id, atTime) => {
      const cue = get().doc.cues.find((c) => c.id === id);
      if (!cue || atTime <= cue.start || atTime >= cue.end) return;
      pushHistory();
      // Split text at the midpoint line break if multi-line, else by half length.
      const lines = cue.text.split("\n");
      let firstText = cue.text;
      let secondText = "";
      if (lines.length > 1) {
        const mid = Math.ceil(lines.length / 2);
        firstText = lines.slice(0, mid).join("\n");
        secondText = lines.slice(mid).join("\n");
      } else {
        const mid = Math.ceil(cue.text.length / 2);
        firstText = cue.text.slice(0, mid).trim();
        secondText = cue.text.slice(mid).trim();
      }
      const first: Cue = { ...cue, end: atTime, text: firstText, tokens: undefined };
      const second: Cue = { ...cue, id: newCueId(), start: atTime, text: secondText, tokens: undefined };
      const idx = get().doc.cues.findIndex((c) => c.id === id);
      const next = [...get().doc.cues];
      next.splice(idx, 1, first, second);
      set({ doc: withCues(next), activeCueId: second.id });
    },

    mergeCues: (ids) => {
      if (ids.length < 2) return;
      pushHistory();
      const idSet = new Set(ids);
      const targets = sortedCues(get().doc.cues.filter((c) => idSet.has(c.id)));
      const merged: Cue = {
        ...targets[0],
        id: newCueId(),
        start: targets[0].start,
        end: targets.at(-1)!.end,
        text: targets.map((c) => c.text).join("\n"),
        tokens: targets.flatMap((c) => c.tokens ?? []),
      };
      if (!merged.tokens?.length) merged.tokens = undefined;
      const firstIdx = get().doc.cues.findIndex((c) => c.id === targets[0].id);
      const remaining = get().doc.cues.filter((c) => !idSet.has(c.id));
      remaining.splice(Math.min(firstIdx, remaining.length), 0, merged);
      set({ doc: withCues(remaining), selectedIds: new Set([merged.id]), activeCueId: merged.id });
    },

    shiftTime: (deltaSec, scope) => {
      pushHistory();
      const { selectedIds } = get();
      const shiftCue = (c: Cue): Cue => {
        if (scope === "selected" && !selectedIds.has(c.id)) return c;
        return {
          ...c,
          start: Math.max(0, c.start + deltaSec),
          end: Math.max(0, c.end + deltaSec),
          tokens: c.tokens?.map((t) => ({
            ...t,
            start: Math.max(0, t.start + deltaSec),
            end: Math.max(0, t.end + deltaSec),
          })),
        };
      };
      set({ doc: withCues(get().doc.cues.map(shiftCue)) });
    },

    addStyle: () => {
      pushHistory();
      const styles = get().doc.styles ?? [];
      const name = uniqueStyleName(styles, "New Style");
      const style: AssStyle = {
        name,
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
      set({ doc: { ...get().doc, styles: [...styles, style] } });
    },

    updateStyle: (name, patch) => {
      pushHistory();
      const styles = (get().doc.styles ?? []).map((s) => (s.name === name ? { ...s, ...patch } : s));
      // Renaming a style: re-point cues that referenced the old name.
      const renamed = patch.name && patch.name !== name ? patch.name : null;
      const cues = renamed
        ? get().doc.cues.map((c) => (c.style === name ? { ...c, style: renamed } : c))
        : get().doc.cues;
      set({ doc: { ...get().doc, styles, cues } });
    },

    deleteStyle: (name) => {
      pushHistory();
      const styles = (get().doc.styles ?? []).filter((s) => s.name !== name);
      // Cues referencing the removed style fall back to undefined (Default on export).
      const cues = get().doc.cues.map((c) => (c.style === name ? { ...c, style: undefined } : c));
      set({ doc: { ...get().doc, styles, cues } });
    },

    undo: () => {
      const { _history, _future, doc } = get();
      if (!_history.length) return;
      const prev = _history[_history.length - 1];
      set({
        doc: prev,
        _history: _history.slice(0, -1),
        _future: [..._future.slice(-(MAX_HISTORY - 1)), clone(doc)],
        isDirty: true,
      });
    },

    redo: () => {
      const { _history, _future, doc } = get();
      if (!_future.length) return;
      const next = _future[_future.length - 1];
      set({
        doc: next,
        _future: _future.slice(0, -1),
        _history: [..._history.slice(-(MAX_HISTORY - 1)), clone(doc)],
        isDirty: true,
      });
    },
  };
});
