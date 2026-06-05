import { useEffect, useRef, useState } from "react";
import type { Cue } from "../../types/subtitle";
import { formatDisplayTime, parseTimestampInput } from "../../utils/time";
import { cps, cueDuration, evaluateCue, hasAnyIssue, type CueQuality } from "../../utils/quality";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useMediaStore } from "../../stores/useMediaStore";
import { hasOverrideTags } from "../../formats/assTags";

interface Props {
  cue: Cue;
  index: number;
  prev: Cue | null;
  selected: boolean;
  active: boolean;
  styleNames: string[]; // when non-empty, show a per-cue style selector
}

type EditField = "start" | "end" | null;

export function CueRow({ cue, index, prev, selected, active, styleNames }: Props) {
  const { t } = useI18nStore();
  const updateCue = useSubtitleStore((s) => s.updateCue);
  const toggleSelect = useSubtitleStore((s) => s.toggleSelect);

  const [editField, setEditField] = useState<EditField>(null);
  const [editValue, setEditValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (editField) inputRef.current?.select();
  }, [editField]);

  const q = evaluateCue(cue, prev);
  const issue = hasAnyIssue(q);

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

  return (
    <div
      className={[
        "flex items-stretch border-b border-zinc-800 text-sm",
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
        {hasOverrideTags(cue.assSpans) && (
          <span
            className="absolute right-2 top-1 select-none rounded bg-fuchsia-900/60 px-1 text-[9px] font-semibold text-fuchsia-200"
            title="ASS override tags preserved"
          >
            fx
          </span>
        )}
        <textarea
          value={cue.text}
          spellCheck={false}
          rows={Math.max(1, cue.text.split("\n").length)}
          onChange={(e) => updateCue(cue.id, { text: e.target.value })}
          onClick={(e) => e.stopPropagation()}
          className="w-full resize-none rounded bg-transparent px-2 py-1 text-zinc-100 outline-none focus:bg-zinc-950"
        />
      </div>

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
}

function TimeCell({ editing, value, inputRef, onStart, onChange, onCommit, onCancel, danger }: TimeCellProps) {
  return (
    <div className="flex w-24 shrink-0 items-center justify-center border-l border-zinc-800/60 py-1">
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
        <button
          onClick={(e) => {
            e.stopPropagation();
            onStart();
          }}
          className={`font-mono text-xs ${danger ? "text-red-400" : "text-zinc-300"} hover:text-indigo-300`}
        >
          {value}
        </button>
      )}
    </div>
  );
}
