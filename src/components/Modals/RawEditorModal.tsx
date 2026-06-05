import { useEffect, useRef, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { Backdrop } from "./ConfirmModal";

interface Props {
  initialValue: string;
  onApply: (raw: string) => void;
  onClose: () => void;
}

// Serialize -> textarea -> re-parse on apply (MetaEditor pattern from Lyrical Sync).
export function RawEditorModal({ initialValue, onApply, onClose }: Props) {
  const { t } = useI18nStore();
  const [value, setValue] = useState(initialValue);
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    ref.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <Backdrop onClick={onClose}>
      <div className="flex w-[720px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-1 text-sm font-semibold text-zinc-100">{t.rawEdit}</h3>
        <p className="mb-3 text-xs text-zinc-500">{t.rawEditHint}</p>
        <textarea
          ref={ref}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          spellCheck={false}
          className="h-[60vh] w-full resize-none rounded border border-zinc-700 bg-zinc-950 p-3 font-mono text-xs text-zinc-200 outline-none focus:border-indigo-500"
        />
        <div className="mt-4 flex justify-end gap-2">
          <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onClose}>
            {t.cancel}
          </button>
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={() => onApply(value)}
          >
            {t.apply}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
