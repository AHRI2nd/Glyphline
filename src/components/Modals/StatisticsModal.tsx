import { useMemo } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { sortedCues } from "../../formats/srt";
import { formatDisplayTime } from "../../utils/time";
import { cps, cueDuration, visibleCharCount } from "../../utils/quality";
import { Backdrop } from "./ConfirmModal";

interface Props {
  onClose: () => void;
}

/** Document-wide summary (Subtitle Edit's Statistics). Read-only. */
export function StatisticsModal({ onClose }: Props) {
  const { t } = useI18nStore();
  const cues = useSubtitleStore((s) => s.doc.cues);

  const stats = useMemo(() => {
    const sorted = sortedCues(cues);
    if (!sorted.length) return null;
    let chars = 0;
    let words = 0;
    let lines = 0;
    let shown = 0;
    let cpsSum = 0;
    let cpsMax = 0;
    let durMin = Infinity;
    let durMax = 0;
    let overlaps = 0;
    for (let i = 0; i < sorted.length; i++) {
      const c = sorted[i];
      chars += visibleCharCount(c.text);
      words += c.text.split(/\s+/).filter(Boolean).length;
      lines += c.text.split("\n").length;
      const d = cueDuration(c);
      shown += d;
      durMin = Math.min(durMin, d);
      durMax = Math.max(durMax, d);
      const v = cps(c);
      cpsSum += v;
      cpsMax = Math.max(cpsMax, v);
      if (i > 0 && sorted[i - 1].end > c.start) overlaps++;
    }
    return {
      count: sorted.length,
      span: sorted.at(-1)!.end - sorted[0].start,
      shown,
      chars,
      words,
      lines,
      cpsAvg: cpsSum / sorted.length,
      cpsMax,
      durMin,
      durMax,
      overlaps,
    };
  }, [cues]);

  const rows: Array<[string, string]> = stats
    ? [
        [t.statCueCount, String(stats.count)],
        [t.statSpan, formatDisplayTime(stats.span)],
        [t.statShownTime, formatDisplayTime(stats.shown)],
        [t.statChars, String(stats.chars)],
        [t.statWords, String(stats.words)],
        [t.statLines, String(stats.lines)],
        [t.statAvgCps, stats.cpsAvg.toFixed(1)],
        [t.statMaxCps, stats.cpsMax.toFixed(1)],
        [t.statDurRange, `${stats.durMin.toFixed(2)}s – ${stats.durMax.toFixed(2)}s`],
        [t.statOverlaps, String(stats.overlaps)],
      ]
    : [];

  return (
    <Backdrop onClick={onClose}>
      <div
        className="w-[380px] rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.statistics}</h3>
          <button className="text-zinc-500 hover:text-zinc-300" onClick={onClose}>✕</button>
        </div>

        <div className="px-5 py-4">
          {!stats ? (
            <p className="text-sm text-zinc-500">{t.noCues}</p>
          ) : (
            <table className="w-full text-sm">
              <tbody>
                {rows.map(([label, value]) => (
                  <tr key={label} className="border-b border-zinc-800/60 last:border-0">
                    <td className="py-1.5 text-zinc-400">{label}</td>
                    <td className="py-1.5 text-right font-mono text-zinc-100">{value}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
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
