import { useEffect } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { Backdrop } from "./ConfirmModal";

const isMac = navigator.platform.toUpperCase().includes("MAC");
const mod = isMac ? "⌘" : "Ctrl";

export function HelpModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const rows: [string, string][] = [
    [`${mod} Z`, t.scUndo],
    [`${mod} ⇧ Z`, t.scRedo],
    [`${mod} S`, t.scSave],
    [`${mod} O`, t.scOpen],
    [`${mod} N`, t.scNew],
    [`${mod} F`, t.findReplace],
    ["↑ ↓", t.scNavCues],
    ["I", t.scTimingIn],
    ["O", t.scTimingOut],
    ["P", t.scTimingChain],
  ];

  return (
    <Backdrop onClick={onClose}>
      <div className="w-[420px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-4 text-sm font-semibold text-zinc-100">{t.shortcuts}</h3>
        <table className="w-full text-sm">
          <tbody>
            {rows.map(([key, desc]) => (
              <tr key={key} className="border-b border-zinc-800 last:border-0">
                <td className="py-2">
                  <span className="rounded border border-zinc-600 bg-zinc-800 px-2 py-0.5 font-mono text-xs text-zinc-200">
                    {key}
                  </span>
                </td>
                <td className="py-2 text-right text-zinc-200">{desc}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="mt-5 flex justify-end">
          <button className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500" onClick={onClose}>
            {t.close}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
