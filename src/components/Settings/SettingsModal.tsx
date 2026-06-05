import { useEffect } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { Backdrop } from "../Modals/ConfirmModal";

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const { uiScale, setUiScale, autoCheckUpdate, setAutoCheckUpdate } = useSettingsStore();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <Backdrop onClick={onClose}>
      <div className="w-[420px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-4 text-sm font-semibold text-zinc-100">{t.settings}</h3>

        <div className="mb-5">
          <div className="mb-1 flex justify-between text-sm text-zinc-300">
            <span>{t.uiScale}</span>
            <span className="font-mono text-zinc-400">{uiScale.toFixed(2)}×</span>
          </div>
          <input
            type="range"
            min={0.7}
            max={1.3}
            step={0.05}
            value={uiScale}
            onChange={(e) => setUiScale(Number(e.target.value))}
            className="w-full"
          />
        </div>

        <label className="flex cursor-pointer items-center gap-2 text-sm text-zinc-300">
          <input
            type="checkbox"
            checked={autoCheckUpdate}
            onChange={(e) => setAutoCheckUpdate(e.target.checked)}
          />
          {t.autoCheckUpdate}
        </label>

        <div className="mt-6 flex justify-end">
          <button className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500" onClick={onClose}>
            {t.close}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
