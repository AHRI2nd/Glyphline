import { useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "./ConfirmModal";

interface Props {
  onClose: () => void;
}

// factor = fromFps / toFps: content authored at `from` fps but played at `to`
// fps runs faster/slower, so timestamps scale by the inverse ratio.
const PRESETS: Array<{ label: string; factor: number }> = [
  { label: "23.976 → 25", factor: 23.976 / 25 },
  { label: "25 → 23.976", factor: 25 / 23.976 },
  { label: "24 → 25", factor: 24 / 25 },
  { label: "25 → 24", factor: 25 / 24 },
];

/** Multiply all timestamps by a ratio (framerate conversion / speed change). */
export function ChangeSpeedModal({ onClose }: Props) {
  const { t } = useI18nStore();
  const [factorStr, setFactorStr] = useState("1.0");
  const [error, setError] = useState(false);

  const apply = (factor: number) => {
    if (!useSubtitleStore.getState().changeSpeed(factor)) {
      setError(true);
      return;
    }
    onClose();
  };

  return (
    <Backdrop onClick={onClose}>
      <div
        className="w-[400px] rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.changeSpeed}</h3>
          <button className="text-zinc-500 hover:text-zinc-300" onClick={onClose}>✕</button>
        </div>

        <div className="flex flex-col gap-4 px-5 py-4">
          <p className="text-xs leading-relaxed text-zinc-500">{t.changeSpeedHint}</p>

          {/* framerate presets */}
          <div className="grid grid-cols-2 gap-2">
            {PRESETS.map((p) => (
              <button
                key={p.label}
                onClick={() => apply(p.factor)}
                className="rounded border border-zinc-700 bg-zinc-800 px-3 py-2 text-sm text-zinc-200 transition-colors hover:border-indigo-500 hover:bg-zinc-700"
              >
                {p.label} <span className="ml-1 font-mono text-[10px] text-zinc-500">fps</span>
              </button>
            ))}
          </div>

          {/* custom multiplier */}
          <div className="flex items-center gap-2">
            <span className="text-xs text-zinc-400">{t.customFactor}</span>
            <input
              type="number"
              step="any"
              min={0}
              value={factorStr}
              onChange={(e) => { setFactorStr(e.target.value); setError(false); }}
              className={`w-24 rounded border bg-zinc-950 px-2 py-1 text-right font-mono text-sm text-zinc-100 outline-none focus:border-indigo-500 ${
                error ? "border-rose-500" : "border-zinc-700"
              }`}
            />
            <span className="text-xs text-zinc-500">×</span>
            <button
              onClick={() => apply(Number(factorStr))}
              className="ml-auto rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            >
              {t.apply}
            </button>
          </div>
          {error && <p className="-mt-2 text-xs text-rose-400">{t.changeSpeedInvalid}</p>}
        </div>
      </div>
    </Backdrop>
  );
}
