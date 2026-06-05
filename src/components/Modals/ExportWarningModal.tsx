import { useEffect } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { Backdrop } from "./ConfirmModal";
import type { LossCategory } from "../../formats/assTags";

const LABEL_KEY: Record<LossCategory, keyof ReturnType<typeof useI18nStore.getState>["t"]> = {
  position: "lossPosition",
  karaoke: "lossKaraoke",
  animation: "lossAnimation",
  transform: "lossTransform",
  borderShadow: "lossBorderShadow",
  drawing: "lossDrawing",
  clip: "lossClip",
  color: "lossColor",
  other: "lossOther",
};

interface Props {
  categories: LossCategory[];
  onConfirm: () => void;
  onCancel: () => void;
}

export function ExportWarningModal({ categories, onConfirm, onCancel }: Props) {
  const { t } = useI18nStore();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
      if (e.key === "Enter") onConfirm();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onConfirm, onCancel]);

  return (
    <Backdrop onClick={onCancel}>
      <div className="w-[460px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-2 flex items-center gap-2 text-sm font-semibold text-amber-300">
          <span>⚠</span> {t.exportLossTitle}
        </h3>
        <p className="mb-3 text-sm text-zinc-300">{t.exportLossDesc}</p>
        <ul className="mb-3 space-y-1">
          {categories.map((c) => (
            <li key={c} className="flex items-center gap-2 text-sm text-zinc-200">
              <span className="text-amber-400">•</span>
              {t[LABEL_KEY[c]]}
            </li>
          ))}
        </ul>
        <p className="mb-5 rounded bg-zinc-800/60 px-3 py-2 text-xs text-zinc-400">{t.exportLossKeepHint}</p>
        <div className="flex justify-end gap-2">
          <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onCancel}>
            {t.cancel}
          </button>
          <button
            className="rounded bg-amber-600 px-3 py-1.5 text-sm text-white hover:bg-amber-500"
            onClick={onConfirm}
          >
            {t.continueExport}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
