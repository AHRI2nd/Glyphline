import { useEffect, useRef, useState } from "react";
import type { Cue } from "../../types/subtitle";
import { formatDisplayTime, parseTimestampInput } from "../../utils/time";
import { cps, cueDuration, evaluateCue, hasAnyIssue, type CueQuality } from "../../utils/quality";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { useMediaStore } from "../../stores/useMediaStore";
import { hasOverrideTags } from "../../formats/assTags";

interface Props {
  cue: Cue;
  index: number;
  prev: Cue | null;
  selected: boolean;
  active: boolean;
  styleNames: string[]; // when non-empty, show a per-cue style selector
  showTranslation: boolean; // when true, show the parallel translation column
}

type EditField = "start" | "end" | null;

export function CueRow({ cue, index, prev, selected, active, styleNames, showTranslation }: Props) {
  const { t } = useI18nStore();
  const updateCue = useSubtitleStore((s) => s.updateCue);
  const toggleSelect = useSubtitleStore((s) => s.toggleSelect);

  const [editField, setEditField] = useState<EditField>(null);
  const [editValue, setEditValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const rowRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (editField) inputRef.current?.select();
  }, [editField]);

  // Keep the active row visible (keyboard navigation / find&replace / playback).
  useEffect(() => {
    if (active) rowRef.current?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const q = evaluateCue(cue, prev);
  const issue = hasAnyIssue(q);
  const hasMedia = useMediaStore((s) => s.mediaSrc != null);

  const startEdit = (field: "start" | "end") => {
    setEditField(field);
    setEditValue(formatDisplayTime(cue[field]));
  };
  const commitEdit = () => {
    if (!editField) return;
    const parsed = parseTimestampInput(editValue);
    if (parsed != null) updateCue(cue.id, { [editField]: parsed } as Partial<Cue>);
    setEditField(null);
  };
  // Stamp the current playhead time into start/end (read at click time).
  const capture = (field: "start" | "end") => {
    const tNow = useMediaStore.getState().currentTime;
    updateCue(cue.id, { [field]: tNow } as Partial<Cue>);
  };

  return (
    <div
      ref={rowRef}
      className={[
        "group flex items-stretch border-b border-zinc-800 text-sm",
        selected ? "bg-indigo-950/40" : active ? "bg-zinc-800/40" : "hover:bg-zinc-900/60",
      ].join(" ")}
      onClick={(e) => {
        toggleSelect(cue.id, e.metaKey || e.ctrlKey);
        // Jump the video playhead to this cue when media is loaded.
        if (useMediaStore.getState().mediaSrc) useMediaStore.getState().seek(cue.start);
      }}
    >
      <div className="flex w-10 shrink-0 items-center justify-center py-2 text-xs text-zinc-500">
        {index + 1}
      </div>

      <TimeCell
        editing={editField === "start"}
        value={editField === "start" ? editValue : formatDisplayTime(cue.start)}
        inputRef={editField === "start" ? inputRef : undefined}
        onStart={() => startEdit("start")}
        onChange={setEditValue}
        onCommit={commitEdit}
        onCancel={() => setEditField(null)}
        onCapture={hasMedia ? () => capture("start") : undefined}
        captureTitle={t.setFromPlayhead}
      />
      <TimeCell
        editing={editField === "end"}
        value={editField === "end" ? editValue : formatDisplayTime(cue.end)}
        inputRef={editField === "end" ? inputRef : undefined}
        onStart={() => startEdit("end")}
        onChange={setEditValue}
        onCommit={commitEdit}
        onCancel={() => setEditField(null)}
        danger={q.negativeDuration}
        onCapture={hasMedia ? () => capture("end") : undefined}
        captureTitle={t.setFromPlayhead}
      />

      <div className="flex w-20 shrink-0 flex-col items-center justify-center py-1 text-[10px] leading-tight">
        <span className={q.durationTooShort || q.durationTooLong ? "text-amber-400" : "text-zinc-500"}>
          {cueDuration(cue).toFixed(2)}s
        </span>
        <span className={q.cpsTooHigh ? "text-red-400" : "text-zinc-600"}>
          {cps(cue).toFixed(0)} cps
        </span>
      </div>

      {styleNames.length > 0 && (
        <div className="flex w-28 shrink-0 items-center border-l border-zinc-800/60 px-1" onClick={(e) => e.stopPropagation()}>
          <select
            value={cue.style ?? ""}
            onChange={(e) => updateCue(cue.id, { style: e.target.value || undefined })}
            className="w-full rounded bg-transparent px-1 py-0.5 text-xs text-zinc-300 outline-none focus:bg-zinc-950"
          >
            <option value="">{t.defaultStyle}</option>
            {styleNames.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </div>
      )}

      <div className="relative flex-1 py-1 pr-2">
        {/* Tag editor entry — always available so tags can be APPLIED to any cue;
            dimmed + hover-revealed when the cue has no tags yet. */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            useSubtitleStore.getState().setActiveCue(cue.id);
            useSettingsStore.getState().openTagEditor();
          }}
          className={`absolute right-2 top-1 z-10 select-none rounded px-1 text-[9px] font-semibold transition-all ${
            hasOverrideTags(cue.assSpans)
              ? "bg-fuchsia-900/60 text-fuchsia-200 hover:bg-fuchsia-700/70"
              : "bg-zinc-800/80 text-zinc-500 opacity-0 hover:text-fuchsia-300 group-hover:opacity-100"
          }`}
          title={t.editTags}
        >
          fx
        </button>
        <textarea
          value={cue.text}
          spellCheck={false}
          rows={Math.max(1, cue.text.split("\n").length)}
          onChange={(e) => updateCue(cue.id, { text: e.target.value })}
          onClick={(e) => e.stopPropagation()}
          className="w-full resize-none rounded bg-transparent px-2 py-1 text-zinc-100 outline-none focus:bg-zinc-950"
        />
      </div>

      {showTranslation && (
        <div className="flex-1 border-l border-zinc-800/60 py-1 pr-2">
          <textarea
            value={cue.translation ?? ""}
            spellCheck={false}
            rows={Math.max(1, (cue.translation ?? "").split("\n").length)}
            placeholder={t.translationPlaceholder}
            onChange={(e) => updateCue(cue.id, { translation: e.target.value || undefined })}
            onClick={(e) => e.stopPropagation()}
            className="w-full resize-none rounded bg-transparent px-2 py-1 text-zinc-200 outline-none placeholder:text-zinc-700 focus:bg-zinc-950"
          />
        </div>
      )}

      <div className="flex w-6 shrink-0 items-center justify-center" title={issue ? issueText(q, t) : ""}>
        {issue && <span className="text-red-500">●</span>}
      </div>
    </div>
  );
}

function issueText(q: CueQuality, t: ReturnType<typeof useI18nStore.getState>["t"]): string {
  const msgs: string[] = [];
  if (q.overlapsPrev) msgs.push(t.overlap);
  if (q.cpsTooHigh) msgs.push(t.cpsHigh);
  if (q.durationTooShort) msgs.push(t.tooShort);
  if (q.durationTooLong) msgs.push(t.tooLong);
  return msgs.join(" · ");
}

interface TimeCellProps {
  editing: boolean;
  value: string;
  inputRef?: React.RefObject<HTMLInputElement | null>;
  onStart: () => void;
  onChange: (v: string) => void;
  onCommit: () => void;
  onCancel: () => void;
  danger?: boolean;
  /** Stamp the current playhead time into this field (shown only with media). */
  onCapture?: () => void;
  captureTitle?: string;
}

function TimeCell({ editing, value, inputRef, onStart, onChange, onCommit, onCancel, danger, onCapture, captureTitle }: TimeCellProps) {
  return (
    <div className="group/time relative flex w-24 shrink-0 items-center justify-center border-l border-zinc-800/60 py-1">
      {editing ? (
        <input
          ref={inputRef}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onBlur={onCommit}
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => {
            if (e.key === "Enter") onCommit();
            if (e.key === "Escape") onCancel();
          }}
          className="w-[88px] rounded bg-zinc-950 px-1 py-0.5 text-center font-mono text-xs text-indigo-200 outline-none"
        />
      ) : (
        <>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onStart();
            }}
            className={`font-mono text-xs ${danger ? "text-red-400" : "text-zinc-300"} hover:text-indigo-300`}
          >
            {value}
          </button>
          {onCapture && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onCapture();
              }}
              title={captureTitle}
              className="absolute right-0.5 top-1/2 -translate-y-1/2 rounded px-0.5 text-[10px] text-zinc-600 opacity-0 transition-opacity hover:text-indigo-300 group-hover/time:opacity-100"
            >
              ⌖
            </button>
          )}
        </>
      )}
    </div>
  );
}
