import { useEffect } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "../Modals/ConfirmModal";
import { embeddedByteSize } from "../../formats/ass";
import type { AssEmbedded } from "../../types/subtitle";

// Lists the fonts/graphics embedded in the current ASS document ([Fonts] /
// [Graphics] sections). These are preserved losslessly through the model; here we
// just surface them (name + decoded size) so the user knows what the file carries.
export function EmbeddedAssetsModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const fonts = useSubtitleStore((s) => s.doc.fonts ?? []);
  const graphics = useSubtitleStore((s) => s.doc.graphics ?? []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const empty = fonts.length === 0 && graphics.length === 0;

  return (
    <Backdrop onClick={onClose}>
      <div className="flex w-[520px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.embeddedAssets}</h3>
          <button className="rounded px-2 py-0.5 text-sm text-zinc-400 hover:bg-zinc-800" onClick={onClose}>✕</button>
        </div>

        <div className="max-h-[60vh] overflow-y-auto px-5 py-4">
          {empty ? (
            <p className="py-6 text-center text-sm text-zinc-500">{t.embeddedEmpty}</p>
          ) : (
            <>
              <Section title={t.embeddedFonts} items={fonts} />
              <Section title={t.embeddedGraphics} items={graphics} />
            </>
          )}
        </div>
      </div>
    </Backdrop>
  );
}

function Section({ title, items }: { title: string; items: AssEmbedded[] }) {
  if (!items.length) return null;
  return (
    <div className="mb-4 last:mb-0">
      <div className="mb-1.5 flex items-baseline gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-zinc-400">{title}</span>
        <span className="text-[11px] text-zinc-600">{items.length}</span>
      </div>
      <ul className="flex flex-col gap-1">
        {items.map((f, i) => (
          <li
            key={i}
            className="flex items-center justify-between gap-3 rounded border border-zinc-800 bg-zinc-950/60 px-2.5 py-1.5"
          >
            <span className="truncate font-mono text-xs text-zinc-200" title={f.name}>{f.name}</span>
            <span className="shrink-0 font-mono text-[11px] text-zinc-500">{formatBytes(embeddedByteSize(f.data))}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}
