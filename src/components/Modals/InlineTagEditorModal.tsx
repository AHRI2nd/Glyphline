import { useEffect, useMemo, useRef, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "./ConfirmModal";
import { decodeTags, parseAssText, serializeAssText, spansToPlain } from "../../formats/assTags";
import { hexToAssColor } from "../../utils/color";

// Edit the ASS override tags of the active cue. The textarea holds the raw tagged
// Dialogue text; a toolbar inserts/wraps common tags; on apply we re-parse into
// assSpans (lossless for every tag) and recompute the plain text.
export function InlineTagEditorModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const activeCueId = useSubtitleStore((s) => s.activeCueId);
  const cue = useSubtitleStore((s) => s.doc.cues.find((c) => c.id === s.activeCueId) ?? null);

  const initial = useMemo(() => {
    if (!cue) return "";
    return cue.assSpans?.length ? serializeAssText(cue.assSpans) : cue.text;
  }, [cue?.id]);

  const [value, setValue] = useState(initial);
  const taRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  if (!cue || !activeCueId) {
    return (
      <Backdrop onClick={onClose}>
        <div className="w-[420px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
          <p className="text-sm text-zinc-300">{t.noActiveCue}</p>
          <div className="mt-4 flex justify-end">
            <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onClose}>
              {t.close}
            </button>
          </div>
        </div>
      </Backdrop>
    );
  }

  // ── editing helpers ───────────────────────────────────────────────────────────
  const replaceSelection = (transform: (sel: string) => string) => {
    const ta = taRef.current;
    if (!ta) return;
    const s = ta.selectionStart;
    const e = ta.selectionEnd;
    const next = value.slice(0, s) + transform(value.slice(s, e)) + value.slice(e);
    setValue(next);
  };
  const wrap = (open: string, close: string) => replaceSelection((sel) => `${open}${sel}${close}`);
  const insert = (text: string) => replaceSelection((sel) => `${text}${sel}`);

  const apply = () => {
    const spans = parseAssText(value);
    useSubtitleStore.getState().updateCue(activeCueId, { assSpans: spans, text: spansToPlain(spans) });
    onClose();
  };

  const detected = parseAssText(value)
    .filter((sp) => sp.tags)
    .flatMap((sp) => decodeTags(sp.tags!));
  const plain = spansToPlain(parseAssText(value));

  return (
    <Backdrop onClick={onClose}>
      <div className="flex w-[640px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-3 text-sm font-semibold text-zinc-100">{t.inlineTagEditor}</h3>

        {/* toolbar */}
        <div className="mb-2 flex flex-wrap items-center gap-1">
          <TBtn onClick={() => wrap("{\\b1}", "{\\b0}")}>B</TBtn>
          <TBtn onClick={() => wrap("{\\i1}", "{\\i0}")} italic>i</TBtn>
          <TBtn onClick={() => wrap("{\\u1}", "{\\u0}")} underline>U</TBtn>
          <label className="ml-1 flex cursor-pointer items-center gap-1 rounded bg-zinc-800 px-2 py-1 text-xs text-zinc-200 hover:bg-zinc-700">
            🎨 {t.tagColor}
            <input
              type="color"
              className="h-4 w-4 cursor-pointer border-0 bg-transparent p-0"
              onChange={(e) => wrap(`{\\1c${hexToAssColor(e.target.value)}}`, "{\\1c&HFFFFFF&}")}
            />
          </label>
          <span className="mx-1 h-4 w-px bg-zinc-700" />
          <TBtn onClick={() => insert("{\\pos(960,540)}")}>{"{\\pos}"}</TBtn>
          <TBtn onClick={() => insert("{\\fad(200,200)}")}>{"{\\fad}"}</TBtn>
          <TBtn onClick={() => insert("{\\an8}")}>{"{\\an8}"}</TBtn>
          <TBtn onClick={() => insert("{\\r}")}>{"{\\r}"}</TBtn>
        </div>

        <textarea
          ref={taRef}
          value={value}
          spellCheck={false}
          onChange={(e) => setValue(e.target.value)}
          className="h-28 w-full resize-none rounded border border-zinc-700 bg-zinc-950 p-2 font-mono text-xs text-zinc-200 outline-none focus:border-indigo-500"
        />

        {/* live feedback */}
        <div className="mt-2 text-xs text-zinc-500">{t.preview}:</div>
        <div className="mb-2 whitespace-pre-wrap rounded bg-zinc-950 p-2 text-sm text-zinc-100">{plain || "—"}</div>

        {detected.length > 0 && (
          <div className="mb-3 flex flex-wrap gap-1">
            {detected.map((d, i) => (
              <span
                key={i}
                className={`rounded px-1.5 py-0.5 text-[11px] ${
                  d.known ? "bg-emerald-900/50 text-emerald-200" : "bg-amber-900/50 text-amber-200"
                }`}
                title={d.known ? "known tag" : "unknown tag (preserved)"}
              >
                \{d.name}
                {d.arg}
              </span>
            ))}
          </div>
        )}

        <div className="flex justify-end gap-2">
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

function TBtn({
  children,
  onClick,
  italic,
  underline,
}: {
  children: React.ReactNode;
  onClick: () => void;
  italic?: boolean;
  underline?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className="rounded bg-zinc-800 px-2 py-1 text-xs text-zinc-200 hover:bg-zinc-700"
      style={{ fontStyle: italic ? "italic" : undefined, textDecoration: underline ? "underline" : undefined, fontWeight: 600 }}
    >
      {children}
    </button>
  );
}
