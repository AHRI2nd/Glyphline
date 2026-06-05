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
  saveNativePath: (path: string) => Promise<void>;
  exportPath: (path: string, format: SubFormat) => Promise<void>;
  serializeCurrent: () => string;

  // selection
  setActiveCue: (id: string | null) => void;
  toggleSelect: (id: string, additive: boolean) => void;
  clearSelection: () => void;

  // editing
  updateCue: (id: string, patch: Partial<Omit<Cue, "id">>) => void;
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

    saveNativePath: async (path) => {
      const content = serializeGlyph(get().doc);
      await invoke("write_text_file", { path, content });
      set({ filePath: path, fileName: baseName(path), isDirty: false });
    },

    exportPath: async (path, format) => {
      const content = adapterForFormat(format).serialize(get().doc);
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
