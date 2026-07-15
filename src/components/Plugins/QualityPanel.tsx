import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { evaluateCue, hasAnyIssue, cps, cueDuration } from "../../utils/quality";
import { sortedCues } from "../../formats/srt";
import { formatDisplayTime } from "../../utils/time";

export function QualityPanel() {
  const { t } = useI18nStore();
  const cues = useSubtitleStore((s) => s.doc.cues);
  const setActiveCue = useSubtitleStore((s) => s.setActiveCue);
  const quality = useSettingsStore((s) => s.quality);
  const sorted = sortedCues(cues);
  const issues = sorted
    .map((cue, idx) => ({ cue, q: evaluateCue(cue, idx > 0 ? sorted[idx - 1] : null, quality) }))
    .filter(({ q }) => hasAnyIssue(q));

  if (!issues.length) {
    return (
      <div className="flex h-full items-center justify-center text-xs text-zinc-500">
        ✓ 품질 문제 없음
      </div>
    );
  }

  return (
    <div className="ws-scroll flex h-full flex-col overflow-y-auto">
      <div className="border-b border-zinc-800 px-3 py-2 text-xs text-zinc-400">
        {issues.length}개 항목
      </div>
      {issues.map(({ cue, q }) => (
        <button
          key={cue.id}
          onClick={() => setActiveCue(cue.id)}
          className="w-full border-b border-zinc-800/60 px-3 py-2 text-left transition-colors hover:bg-zinc-800"
        >
          <div className="flex items-center gap-2">
            <span className="shrink-0 font-mono text-[10px] text-zinc-500">
              {sorted.indexOf(cue) + 1}
            </span>
            <span className="truncate text-xs text-zinc-300">{cue.text.split("\n")[0] || "—"}</span>
          </div>
          <div className="mt-0.5 flex flex-wrap gap-1">
            {q.overlapsPrev && <Badge color="red">{t.overlap}</Badge>}
            {q.cpsTooHigh && <Badge color="amber">{t.cpsHigh} ({cps(cue).toFixed(0)})</Badge>}
            {q.durationTooShort && <Badge color="amber">{t.tooShort} ({cueDuration(cue).toFixed(2)}s)</Badge>}
            {q.durationTooLong && <Badge color="amber">{t.tooLong} ({cueDuration(cue).toFixed(2)}s)</Badge>}
            {q.lineTooLong && <Badge color="amber">{t.lineTooLong}</Badge>}
            {q.tooManyLines && <Badge color="amber">{t.tooManyLines}</Badge>}
            {q.negativeDuration && <Badge color="red">{t.negativeDuration}</Badge>}
          </div>
          <div className="mt-0.5 font-mono text-[10px] text-zinc-600">
            {formatDisplayTime(cue.start)} → {formatDisplayTime(cue.end)}
          </div>
        </button>
      ))}
    </div>
  );
}

function Badge({ children, color }: { children: React.ReactNode; color: "red" | "amber" }) {
  return (
    <span
      className={`rounded px-1 py-0.5 text-[10px] ${
        color === "red" ? "bg-red-900/50 text-red-300" : "bg-amber-900/50 text-amber-300"
      }`}
    >
      {children}
    </span>
  );
}
