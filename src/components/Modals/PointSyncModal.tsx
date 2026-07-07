import { useMemo, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useMediaStore } from "../../stores/useMediaStore";
import { sortedCues } from "../../formats/srt";
import { formatDisplayTime, parseTimestampInput } from "../../utils/time";
import { Backdrop } from "./ConfirmModal";

interface Props {
  onClose: () => void;
}

/**
 * Two-point linear sync (Subtitle Edit's "Point sync"): give the current and
 * corrected time of two anchor points; every timestamp is remapped linearly
 * (fixes both constant offset AND progressive drift / framerate mismatch).
 */
export function PointSyncModal({ onClose }: Props) {
  const { t } = useI18nStore();
  const cues = useSubtitleStore((s) => s.doc.cues);
  const hasMedia = useMediaStore((s) => s.mediaSrc != null);

  // Sensible defaults: point A = first cue, point B = last cue.
  const sorted = useMemo(() => sortedCues(cues), [cues]);
  const first = sorted[0]?.start ?? 0;
  const last = sorted.at(-1)?.start ?? 0;

  const [srcA, setSrcA] = useState(formatDisplayTime(first));
  const [dstA, setDstA] = useState(formatDisplayTime(first));
  const [srcB, setSrcB] = useState(formatDisplayTime(last));
  const [dstB, setDstB] = useState(formatDisplayTime(last));
  const [error, setError] = useState<string | null>(null);

  const apply = () => {
    const a = parseTimestampInput(srcA);
    const a2 = parseTimestampInput(dstA);
    const b = parseTimestampInput(srcB);
    const b2 = parseTimestampInput(dstB);
    if (a == null || a2 == null || b == null || b2 == null) {
      setError(t.pointSyncInvalidTime);
      return;
    }
    if (!useSubtitleStore.getState().applyPointSync(a, a2, b, b2)) {
      setError(t.pointSyncSamePoints);
      return;
    }
    onClose();
  };

  return (
    <Backdrop onClick={onClose}>
      <div
        className="w-[460px] rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.pointSync}</h3>
          <button className="text-zinc-500 hover:text-zinc-300" onClick={onClose}>✕</button>
        </div>

        <div className="flex flex-col gap-4 px-5 py-4">
          <p className="text-xs leading-relaxed text-zinc-500">{t.pointSyncHint}</p>

          <PointRow
            label={t.pointA}
            src={srcA} setSrc={setSrcA}
            dst={dstA} setDst={setDstA}
            hasMedia={hasMedia}
            t={t}
          />
          <PointRow
            label={t.pointB}
            src={srcB} setSrc={setSrcB}
            dst={dstB} setDst={setDstB}
            hasMedia={hasMedia}
            t={t}
          />

          {error && <p className="text-xs text-rose-400">{error}</p>}
        </div>

        <div className="flex justify-end gap-2 border-t border-zinc-800 px-5 py-3">
          <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onClose}>
            {t.cancel}
          </button>
          <button className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500" onClick={apply}>
            {t.apply}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}

function PointRow({
  label, src, setSrc, dst, setDst, hasMedia, t,
}: {
  label: string;
  src: string; setSrc: (v: string) => void;
  dst: string; setDst: (v: string) => void;
  hasMedia: boolean;
  t: ReturnType<typeof useI18nStore.getState>["t"];
}) {
  const useActiveCue = () => {
    const s = useSubtitleStore.getState();
    const cue = s.doc.cues.find((c) => c.id === s.activeCueId);
    if (cue) setSrc(formatDisplayTime(cue.start));
  };
  const usePlayhead = () => setDst(formatDisplayTime(useMediaStore.getState().currentTime));

  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs font-semibold uppercase tracking-wide text-zinc-500">{label}</span>
      <div className="flex items-center gap-2">
        <TimeInput value={src} onChange={setSrc} title={t.pointSrcTime} />
        <button
          onClick={useActiveCue}
          title={t.useActiveCue}
          className="rounded bg-zinc-800 px-2 py-1 text-[11px] text-zinc-300 hover:bg-zinc-700"
        >
          {t.useActiveCue}
        </button>
        <span className="text-zinc-600">→</span>
        <TimeInput value={dst} onChange={setDst} title={t.pointDstTime} />
        {hasMedia && (
          <button
            onClick={usePlayhead}
            title={t.usePlayhead}
            className="rounded bg-zinc-800 px-2 py-1 text-[11px] text-indigo-300 hover:bg-zinc-700"
          >
            ⌖ {t.usePlayhead}
          </button>
        )}
      </div>
    </div>
  );
}

function TimeInput({ value, onChange, title }: { value: string; onChange: (v: string) => void; title: string }) {
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      title={title}
      spellCheck={false}
      className="w-[110px] rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-center font-mono text-xs text-zinc-100 outline-none focus:border-indigo-500"
    />
  );
}
