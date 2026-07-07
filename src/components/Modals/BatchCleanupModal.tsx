import { useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "./ConfirmModal";
import { MAX_DURATION, MIN_DURATION } from "../../utils/quality";

interface Props {
  onClose: () => void;
}

type CaseMode = "upper" | "lower" | "sentence" | "title";

/**
 * One-stop batch cleanup (Subtitle Edit's Tools menu equivalents): each row is
 * an independent action with its own Apply button; the result count appears
 * next to it. Every action is a single undo step.
 */
export function BatchCleanupModal({ onClose }: Props) {
  const { t } = useI18nStore();
  const hasSelection = useSubtitleStore((s) => s.selectedIds.size > 0);

  // Per-action "n changed" feedback (null = not run yet).
  const [results, setResults] = useState<Record<string, number | null>>({});
  const run = (key: string, fn: () => number) => setResults((r) => ({ ...r, [key]: fn() }));

  const [gapMs, setGapMs] = useState("80");
  const [minDur, setMinDur] = useState(String(MIN_DURATION));
  const [maxDur, setMaxDur] = useState(String(MAX_DURATION));
  const [caseMode, setCaseMode] = useState<CaseMode>("sentence");
  const [caseScope, setCaseScope] = useState<"all" | "selected">("all");

  const s = () => useSubtitleStore.getState();

  return (
    <Backdrop onClick={onClose}>
      <div
        className="w-[520px] rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.batchCleanup}</h3>
          <button className="text-zinc-500 hover:text-zinc-300" onClick={onClose}>✕</button>
        </div>

        <div className="flex flex-col divide-y divide-zinc-800/60 px-5 py-2">
          {/* fix overlaps */}
          <Row
            label={t.fixOverlaps}
            result={results.overlaps}
            onApply={() => run("overlaps", () => s().fixOverlaps())}
            applyLabel={t.apply}
          />

          {/* minimum gap */}
          <Row
            label={t.minGap}
            result={results.gap}
            onApply={() => run("gap", () => s().applyMinGap(Math.max(0, Number(gapMs) || 0) / 1000))}
            applyLabel={t.apply}
          >
            <NumInput value={gapMs} onChange={setGapMs} suffix="ms" width="w-16" />
          </Row>

          {/* duration limits */}
          <Row
            label={t.durationLimits}
            result={results.durations}
            onApply={() =>
              run("durations", () => {
                const min = Math.max(0, Number(minDur) || 0);
                const max = Math.max(min, Number(maxDur) || min);
                return s().applyDurationLimits(min, max);
              })
            }
            applyLabel={t.apply}
          >
            <NumInput value={minDur} onChange={setMinDur} suffix={t.secondsSuffix} width="w-14" />
            <span className="text-zinc-600">–</span>
            <NumInput value={maxDur} onChange={setMaxDur} suffix={t.secondsSuffix} width="w-14" />
          </Row>

          {/* remove empty */}
          <Row
            label={t.removeEmptyCues}
            result={results.empty}
            onApply={() => run("empty", () => s().removeEmptyCues())}
            applyLabel={t.apply}
          />

          {/* change casing */}
          <Row
            label={t.changeCase}
            result={results.casing}
            onApply={() => run("casing", () => s().changeCase(caseMode, caseScope))}
            applyLabel={t.apply}
          >
            <select
              value={caseMode}
              onChange={(e) => setCaseMode(e.target.value as CaseMode)}
              className="rounded border border-zinc-700 bg-zinc-950 px-1.5 py-1 text-xs text-zinc-200 outline-none"
            >
              <option value="sentence">{t.caseSentence}</option>
              <option value="title">{t.caseTitle}</option>
              <option value="upper">{t.caseUpper}</option>
              <option value="lower">{t.caseLower}</option>
            </select>
            <select
              value={caseScope}
              onChange={(e) => setCaseScope(e.target.value as "all" | "selected")}
              className="rounded border border-zinc-700 bg-zinc-950 px-1.5 py-1 text-xs text-zinc-200 outline-none"
            >
              <option value="all">{t.scopeAll}</option>
              <option value="selected" disabled={!hasSelection}>{t.scopeSelected}</option>
            </select>
          </Row>

          {/* hearing impaired */}
          <Row
            label={t.removeHearingImpaired}
            result={results.hi}
            onApply={() => run("hi", () => s().removeHearingImpaired())}
            applyLabel={t.apply}
            hint={t.removeHearingImpairedHint}
          />

          {/* merge duplicates */}
          <Row
            label={t.mergeSameText}
            result={results.sameText}
            onApply={() => run("sameText", () => s().mergeSameText())}
            applyLabel={t.apply}
            hint={t.mergeSameTextHint}
          />
          <Row
            label={t.mergeSameTimecodes}
            result={results.sameTime}
            onApply={() => run("sameTime", () => s().mergeSameTimecodes())}
            applyLabel={t.apply}
            hint={t.mergeSameTimecodesHint}
          />
        </div>

        <div className="flex justify-end border-t border-zinc-800 px-5 py-3">
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={onClose}
          >
            {t.close}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}

function Row({
  label,
  hint,
  children,
  result,
  onApply,
  applyLabel,
}: {
  label: string;
  hint?: string;
  children?: React.ReactNode;
  result: number | null | undefined;
  onApply: () => void;
  applyLabel: string;
}) {
  return (
    <div className="flex items-center gap-2 py-2.5">
      <div className="min-w-0 flex-1">
        <span className="text-sm text-zinc-200">{label}</span>
        {hint && <p className="mt-0.5 text-[11px] leading-tight text-zinc-500">{hint}</p>}
      </div>
      {children}
      {/* result badge: shown after the action ran */}
      {result != null && (
        <span className={`font-mono text-xs ${result > 0 ? "text-emerald-400" : "text-zinc-500"}`}>
          ✓ {result}
        </span>
      )}
      <button
        onClick={onApply}
        className="shrink-0 rounded bg-zinc-700 px-2.5 py-1 text-xs text-white hover:bg-zinc-600"
      >
        {applyLabel}
      </button>
    </div>
  );
}

function NumInput({
  value,
  onChange,
  suffix,
  width,
}: {
  value: string;
  onChange: (v: string) => void;
  suffix: string;
  width: string;
}) {
  return (
    <label className="flex items-center gap-1 text-xs text-zinc-500">
      <input
        type="number"
        value={value}
        min={0}
        step="any"
        onChange={(e) => onChange(e.target.value)}
        className={`${width} rounded border border-zinc-700 bg-zinc-950 px-1.5 py-1 text-right text-xs text-zinc-200 outline-none focus:border-indigo-500`}
      />
      {suffix}
    </label>
  );
}
