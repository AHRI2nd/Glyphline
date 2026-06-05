import { useEffect, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "../Modals/ConfirmModal";
import { assAlpha, assColorToHex, hexToAssColor } from "../../utils/color";
import type { AssStyle } from "../../types/subtitle";

// Alignment numpad layout (ASS \an): 7 8 9 / 4 5 6 / 1 2 3.
const ALIGN_GRID = [7, 8, 9, 4, 5, 6, 1, 2, 3];

export function StyleManagerModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const styles = useSubtitleStore((s) => s.doc.styles ?? []);
  const addStyle = useSubtitleStore((s) => s.addStyle);
  const updateStyle = useSubtitleStore((s) => s.updateStyle);
  const deleteStyle = useSubtitleStore((s) => s.deleteStyle);

  const [selected, setSelected] = useState<string | null>(styles[0]?.name ?? null);
  const current = styles.find((s) => s.name === selected) ?? styles[0] ?? null;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const patch = (p: Partial<AssStyle>) => current && updateStyle(current.name, p);

  return (
    <Backdrop onClick={onClose}>
      <div
        className="flex h-[80vh] w-[760px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="text-sm font-semibold text-zinc-100">{t.styleManager}</h3>
          <button className="rounded px-2 py-1 text-sm text-zinc-400 hover:bg-zinc-800" onClick={onClose}>
            ✕
          </button>
        </div>

        <div className="flex min-h-0 flex-1">
          {/* style list */}
          <div className="flex w-48 shrink-0 flex-col border-r border-zinc-800">
            <div className="ws-scroll flex-1 overflow-y-auto">
              {styles.map((s) => (
                <button
                  key={s.name}
                  onClick={() => setSelected(s.name)}
                  className={`block w-full truncate px-3 py-2 text-left text-sm ${
                    s.name === current?.name ? "bg-indigo-950/60 text-indigo-200" : "text-zinc-300 hover:bg-zinc-800"
                  }`}
                >
                  {s.name}
                </button>
              ))}
              {!styles.length && <p className="px-3 py-4 text-xs text-zinc-500">{t.noStyles}</p>}
            </div>
            <button
              onClick={() => addStyle()}
              className="border-t border-zinc-800 px-3 py-2 text-left text-sm text-indigo-300 hover:bg-zinc-800"
            >
              ＋ {t.addStyle}
            </button>
          </div>

          {/* editor */}
          <div className="ws-scroll flex-1 overflow-y-auto p-5">
            {current ? (
              <div className="flex flex-col gap-4">
                <Field label={t.styleName}>
                  <input
                    value={current.name}
                    onChange={(e) => {
                      const name = e.target.value;
                      patch({ name });
                      setSelected(name);
                    }}
                    className="w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-indigo-500"
                  />
                </Field>

                <div className="flex gap-3">
                  <Field label={t.font} className="flex-1">
                    <input
                      value={current.fontName}
                      onChange={(e) => patch({ fontName: e.target.value })}
                      className="w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-indigo-500"
                    />
                  </Field>
                  <Field label={t.fontSize} className="w-24">
                    <input
                      type="number"
                      value={current.fontSize}
                      onChange={(e) => patch({ fontSize: Number(e.target.value) })}
                      className="w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-indigo-500"
                    />
                  </Field>
                </div>

                <div className="flex gap-4">
                  <ColorField label={t.primaryColour} value={current.primaryColour} onChange={(v) => patch({ primaryColour: v })} />
                  <ColorField label={t.outlineColour} value={current.outlineColour} onChange={(v) => patch({ outlineColour: v })} />
                  <ColorField label={t.backColour} value={current.backColour} onChange={(v) => patch({ backColour: v })} />
                </div>

                <div className="flex gap-4">
                  <label className="flex items-center gap-2 text-sm text-zinc-300">
                    <input type="checkbox" checked={current.bold} onChange={(e) => patch({ bold: e.target.checked })} />
                    {t.bold}
                  </label>
                  <label className="flex items-center gap-2 text-sm text-zinc-300">
                    <input type="checkbox" checked={current.italic} onChange={(e) => patch({ italic: e.target.checked })} />
                    {t.italic}
                  </label>
                </div>

                <div className="flex gap-3">
                  <Field label={t.outlineWidth} className="w-28">
                    <input
                      type="number"
                      step="0.5"
                      value={current.outline}
                      onChange={(e) => patch({ outline: Number(e.target.value) })}
                      className="w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-indigo-500"
                    />
                  </Field>
                  <Field label={t.shadowDepth} className="w-28">
                    <input
                      type="number"
                      step="0.5"
                      value={current.shadow}
                      onChange={(e) => patch({ shadow: Number(e.target.value) })}
                      className="w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-sm text-zinc-100 outline-none focus:border-indigo-500"
                    />
                  </Field>
                </div>

                <Field label={t.alignment}>
                  <div className="grid w-28 grid-cols-3 gap-1">
                    {ALIGN_GRID.map((a) => (
                      <button
                        key={a}
                        onClick={() => patch({ alignment: a })}
                        className={`h-7 rounded text-xs ${
                          current.alignment === a ? "bg-indigo-600 text-white" : "bg-zinc-800 text-zinc-400 hover:bg-zinc-700"
                        }`}
                      >
                        {a}
                      </button>
                    ))}
                  </div>
                </Field>

                <div className="flex items-center gap-3 pt-2">
                  <PreviewSwatch style={current} />
                  <button
                    onClick={() => {
                      deleteStyle(current.name);
                      setSelected(null);
                    }}
                    className="ml-auto rounded border border-red-900 px-3 py-1.5 text-sm text-red-300 hover:bg-red-950/40"
                  >
                    {t.deleteStyle}
                  </button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-zinc-500">{t.noStyles}</p>
            )}
          </div>
        </div>
      </div>
    </Backdrop>
  );
}

function Field({ label, children, className = "" }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <label className={`flex flex-col gap-1 ${className}`}>
      <span className="text-xs text-zinc-500">{label}</span>
      {children}
    </label>
  );
}

function ColorField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const hex = assColorToHex(value);
  return (
    <Field label={label}>
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={hex}
          onChange={(e) => onChange(hexToAssColor(e.target.value, assAlpha(value)))}
          className="h-8 w-10 cursor-pointer rounded border border-zinc-700 bg-zinc-950"
        />
        <span className="font-mono text-[11px] text-zinc-500">{value}</span>
      </div>
    </Field>
  );
}

function PreviewSwatch({ style }: { style: AssStyle }) {
  return (
    <div
      className="flex h-12 items-center rounded px-3"
      style={{
        background: "#222",
        color: assColorToHex(style.primaryColour),
        fontFamily: style.fontName,
        fontWeight: style.bold ? 700 : 400,
        fontStyle: style.italic ? "italic" : "normal",
        textShadow: `0 0 ${Math.max(1, style.outline)}px ${assColorToHex(style.outlineColour)}`,
      }}
    >
      AaBb 가나 12
    </div>
  );
}
