import { useI18nStore } from "../../stores/useI18nStore";
import { Backdrop } from "./ConfirmModal";

/** Shown when the window is closed with unsaved changes. */
export function CloseConfirmModal({
  onSaveAndClose,
  onDiscard,
  onCancel,
}: {
  onSaveAndClose: () => void;
  onDiscard: () => void;
  onCancel: () => void;
}) {
  const { t } = useI18nStore();
  return (
    <Backdrop onClick={onCancel}>
      <div
        className="w-[420px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <p className="text-sm text-zinc-200">{t.closeUnsavedMessage}</p>
        <div className="mt-5 flex justify-end gap-2">
          <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onCancel}>
            {t.cancel}
          </button>
          <button
            className="rounded bg-rose-900/70 px-3 py-1.5 text-sm text-rose-200 hover:bg-rose-800/70"
            onClick={onDiscard}
          >
            {t.closeWithoutSaving}
          </button>
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={onSaveAndClose}
          >
            {t.saveAndClose}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}

/** Offered at startup when a crash-recovery autosave exists. */
export function RecoveryModal({
  fileName,
  savedAt,
  onRestore,
  onDiscard,
}: {
  fileName: string | null;
  savedAt: number;
  onRestore: () => void;
  onDiscard: () => void;
}) {
  const { t } = useI18nStore();
  const when = new Date(savedAt).toLocaleString();
  return (
    <Backdrop>
      <div className="w-[440px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl">
        <h3 className="mb-2 text-sm font-semibold text-zinc-100">{t.recoveryTitle}</h3>
        <p className="text-sm text-zinc-300">{t.recoveryMessage}</p>
        <p className="mt-2 font-mono text-xs text-zinc-500">
          {fileName ?? t.recoveryUntitled} · {when}
        </p>
        <div className="mt-5 flex justify-end gap-2">
          <button
            className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800"
            onClick={onDiscard}
          >
            {t.recoveryDiscard}
          </button>
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={onRestore}
          >
            {t.recoveryRestore}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
