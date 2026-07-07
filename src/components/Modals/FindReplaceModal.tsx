import { useEffect, useMemo, useRef, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { sortedCues } from "../../formats/srt";
import { Backdrop } from "./ConfirmModal";
import type { Cue } from "../../types/subtitle";

interface Props {
  onClose: () => void;
}

type Field = "text" | "translation";
interface Match {
  cueId: string;
  field: Field;
}

/** Escape a literal string for use inside a RegExp. */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Find & Replace over cue text and translation.
 * Matches are listed per cue+field; navigation moves the active cue so the
 * list highlights and scrolls to it. "Replace all" is a single undo step.
 */
export function FindReplaceModal({ onClose }: Props) {
  const { t } = useI18nStore();
  const cues = useSubtitleStore((s) => s.doc.cues);
  const [query, setQuery] = useState("");
  const [replacement, setReplacement] = useState("");
  const [matchCase, setMatchCase] = useState(false);
  const [useRegex, setUseRegex] = useState(false);
  const [cursor, setCursor] = useState(0); // index into matches
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => inputRef.current?.focus(), []);

  // Build the matcher; null = empty query, undefined = invalid regex.
  const regex = useMemo(() => {
    if (!query) return null;
    try {
      const source = useRegex ? query : escapeRegExp(query);
      return new RegExp(source, matchCase ? "g" : "gi");
    } catch {
      return undefined;
    }
  }, [query, matchCase, useRegex]);

  // Matches recompute whenever the doc changes (e.g. after each replace).
  const matches = useMemo<Match[]>(() => {
    if (!regex) return [];
    const out: Match[] = [];
    for (const cue of sortedCues(cues)) {
      regex.lastIndex = 0;
      if (regex.test(cue.text)) out.push({ cueId: cue.id, field: "text" });
      if (cue.translation != null) {
        regex.lastIndex = 0;
        if (regex.test(cue.translation)) out.push({ cueId: cue.id, field: "translation" });
      }
    }
    return out;
  }, [cues, regex]);

  const clampedCursor = matches.length ? Math.min(cursor, matches.length - 1) : 0;
  const current: Match | null = matches[clampedCursor] ?? null;

  // Highlight + scroll the list to the current match.
  useEffect(() => {
    if (current) useSubtitleStore.getState().setActiveCue(current.cueId);
  }, [current?.cueId]);

  const step = (dir: 1 | -1) => {
    if (!matches.length) return;
    setCursor((c) => (Math.min(c, matches.length - 1) + dir + matches.length) % matches.length);
  };

  const replaceIn = (cue: Cue, field: Field): Partial<Omit<Cue, "id">> | null => {
    if (!regex) return null;
    const src = field === "text" ? cue.text : (cue.translation ?? "");
    regex.lastIndex = 0;
    const next = src.replace(regex, replacement);
    if (next === src) return null;
    return field === "text"
      ? { text: next }
      : { translation: next || undefined };
  };

  const replaceCurrent = () => {
    if (!current) return;
    const cue = cues.find((c) => c.id === current.cueId);
    if (!cue) return;
    const patch = replaceIn(cue, current.field);
    if (patch) useSubtitleStore.getState().updateCue(cue.id, patch);
    // matches recompute from the new doc; cursor stays → lands on the next match.
  };

  const replaceAll = () => {
    if (!regex) return;
    const edits: Array<{ id: string; patch: Partial<Omit<Cue, "id">> }> = [];
    for (const cue of cues) {
      const textPatch = replaceIn(cue, "text");
      const trPatch = cue.translation != null ? replaceIn(cue, "translation") : null;
      if (textPatch || trPatch) edits.push({ id: cue.id, patch: { ...textPatch, ...trPatch } });
    }
    if (edits.length) useSubtitleStore.getState().batchUpdateCues(edits);
  };

  const invalid = regex === undefined;
  const counter = invalid
    ? t.invalidRegex
    : !query
      ? ""
      : matches.length
        ? `${clampedCursor + 1} / ${matches.length}`
        : t.noMatches;

  return (
    <Backdrop onClick={onClose}>
      {/* self-start: keep the box near the top so the cue list stays visible */}
      <div
        className="mt-16 w-[440px] self-start rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Escape") onClose();
          if (e.key === "Enter") step(e.shiftKey ? -1 : 1);
        }}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.findReplace}</h3>
          <button className="text-zinc-500 hover:text-zinc-300" onClick={onClose}>✕</button>
        </div>

        <div className="flex flex-col gap-2 px-5 py-4">
          <div className="flex items-center gap-2">
            <input
              ref={inputRef}
              value={query}
              onChange={(e) => { setQuery(e.target.value); setCursor(0); }}
              placeholder={t.findPlaceholder}
              spellCheck={false}
              className={`flex-1 rounded border bg-zinc-950 px-2 py-1.5 text-sm text-zinc-100 outline-none focus:border-indigo-500 ${
                invalid ? "border-rose-500" : "border-zinc-700"
              }`}
            />
            <span className="w-20 shrink-0 text-right font-mono text-[11px] text-zinc-500">{counter}</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              value={replacement}
              onChange={(e) => setReplacement(e.target.value)}
              placeholder={t.replacePlaceholder}
              spellCheck={false}
              className="flex-1 rounded border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-sm text-zinc-100 outline-none focus:border-indigo-500"
            />
            <span className="w-20 shrink-0" />
          </div>

          <div className="mt-1 flex items-center gap-4 text-xs text-zinc-400">
            <label className="flex cursor-pointer items-center gap-1.5">
              <input type="checkbox" checked={matchCase} onChange={(e) => setMatchCase(e.target.checked)} className="accent-indigo-500" />
              {t.matchCase}
            </label>
            <label className="flex cursor-pointer items-center gap-1.5">
              <input type="checkbox" checked={useRegex} onChange={(e) => setUseRegex(e.target.checked)} className="accent-indigo-500" />
              {t.useRegex}
            </label>
          </div>

          <div className="mt-2 flex items-center justify-end gap-2">
            <button
              onClick={() => step(-1)}
              disabled={!matches.length}
              className="rounded bg-zinc-800 px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-700 disabled:opacity-40"
            >
              ← {t.findPrev}
            </button>
            <button
              onClick={() => step(1)}
              disabled={!matches.length}
              className="rounded bg-zinc-800 px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-700 disabled:opacity-40"
            >
              {t.findNext} →
            </button>
            <span className="mx-1 h-4 w-px bg-zinc-700" />
            <button
              onClick={replaceCurrent}
              disabled={!current}
              className="rounded bg-zinc-700 px-3 py-1.5 text-sm text-white hover:bg-zinc-600 disabled:opacity-40"
            >
              {t.replaceOne}
            </button>
            <button
              onClick={replaceAll}
              disabled={!matches.length}
              className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500 disabled:opacity-40"
            >
              {t.replaceAll}
            </button>
          </div>
        </div>
      </div>
    </Backdrop>
  );
}
