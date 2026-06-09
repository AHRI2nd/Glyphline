import { useEffect, useMemo, useRef, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { Backdrop } from "./ConfirmModal";
import {
  decodeTags,
  parseAssText,
  serializeAssText,
  spansToPlain,
  type DecodedTag,
} from "../../formats/assTags";
import { assColorToHex, hexToAssColor } from "../../utils/color";

// Edit the ASS override tags of the active cue. Two modes over a single source of
// truth (`value`, the raw tagged Dialogue text):
//   • Structured: edit the first override block's tags with per-category controls.
//   • Raw: free-form textarea + insert toolbar (power users).
// On apply we re-parse into assSpans (lossless for every tag) and recompute text.
export function InlineTagEditorModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const activeCueId = useSubtitleStore((s) => s.activeCueId);
  const cue = useSubtitleStore((s) => s.doc.cues.find((c) => c.id === s.activeCueId) ?? null);

  const initial = useMemo(() => {
    if (!cue) return "";
    return cue.assSpans?.length ? serializeAssText(cue.assSpans) : cue.text;
  }, [cue?.id]);

  const [value, setValue] = useState(initial);
  const [raw, setRaw] = useState(false);
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

  // ── structured model: tags of the first override block ────────────────────────
  const spans = parseAssText(value);
  const leadIdx = spans.findIndex((s) => s.tags != null);
  const decoded = leadIdx >= 0 ? decodeTags(spans[leadIdx].tags!) : [];

  // Rewrite the first override block from an edited tag list (re-parses `value`
  // fresh so concurrent text edits aren't lost).
  const commitTags = (tags: DecodedTag[]) => {
    const block = tags.map((d) => `\\${d.name}${d.arg}`).join("");
    const next = parseAssText(value);
    const i = next.findIndex((s) => s.tags != null);
    if (i >= 0) {
      next[i] = block ? { ...next[i], tags: block } : { text: next[i].text };
    } else if (block) {
      next.unshift({ tags: block, text: "" });
    }
    setValue(serializeAssText(next));
  };
  const editTag = (idx: number, arg: string) =>
    commitTags(decoded.map((d, i) => (i === idx ? { ...d, arg } : d)));
  const removeTag = (idx: number) => commitTags(decoded.filter((_, i) => i !== idx));
  const addTag = (name: string) =>
    commitTags([...decoded, { name, arg: defaultArg(name), known: true }]);

  // ── raw helpers (toolbar) ─────────────────────────────────────────────────────
  const replaceSelection = (transform: (sel: string) => string) => {
    const ta = taRef.current;
    if (!ta) return;
    const s = ta.selectionStart;
    const e = ta.selectionEnd;
    setValue(value.slice(0, s) + transform(value.slice(s, e)) + value.slice(e));
  };
  const wrap = (open: string, close: string) => replaceSelection((sel) => `${open}${sel}${close}`);
  const insert = (text: string) => replaceSelection((sel) => `${text}${sel}`);

  const apply = () => {
    const spans2 = parseAssText(value);
    useSubtitleStore.getState().updateCue(activeCueId, { assSpans: spans2, text: spansToPlain(spans2) });
    onClose();
  };

  const plain = spansToPlain(parseAssText(value));
  const detected = decoded; // chips mirror the structured (leading) block

  return (
    <Backdrop onClick={onClose}>
      <div className="flex w-[640px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-3 flex items-center justify-between">
          <h3 className="text-sm font-semibold text-zinc-100">{t.inlineTagEditor}</h3>
          {/* mode toggle */}
          <div className="flex rounded border border-zinc-700 text-xs">
            <button
              className={`px-2 py-0.5 ${!raw ? "bg-indigo-600 text-white" : "text-zinc-400 hover:bg-zinc-800"}`}
              onClick={() => setRaw(false)}
            >
              {t.tagStructured}
            </button>
            <button
              className={`px-2 py-0.5 ${raw ? "bg-indigo-600 text-white" : "text-zinc-400 hover:bg-zinc-800"}`}
              onClick={() => setRaw(true)}
            >
              {t.tagRaw}
            </button>
          </div>
        </div>

        {raw ? (
          <>
            {/* raw toolbar */}
            <div className="mb-2 flex flex-wrap items-center gap-1">
              <TBtn onClick={() => wrap("{\\b1}", "{\\b0}")}>B</TBtn>
              <TBtn onClick={() => wrap("{\\i1}", "{\\i0}")} italic>i</TBtn>
              <TBtn onClick={() => wrap("{\\u1}", "{\\u0}")} underline>U</TBtn>
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
          </>
        ) : (
          <div className="rounded border border-zinc-800 bg-zinc-950/60 p-2">
            {decoded.length === 0 && (
              <p className="px-1 py-2 text-xs text-zinc-600">{t.noTags}</p>
            )}
            <div className="flex flex-col gap-1.5">
              {decoded.map((d, i) => (
                <TagRow
                  key={i}
                  tag={d}
                  onChange={(arg) => editTag(i, arg)}
                  onRemove={() => removeTag(i)}
                />
              ))}
            </div>
            {/* add-tag */}
            <div className="mt-2 flex items-center gap-2">
              <span className="text-[11px] text-zinc-500">{t.addTag}:</span>
              <select
                value=""
                onChange={(e) => { if (e.target.value) addTag(e.target.value); }}
                className="rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 text-xs text-zinc-200 outline-none"
              >
                <option value="">＋</option>
                {ADDABLE.map((n) => (
                  <option key={n} value={n}>{`\\${n}`}</option>
                ))}
              </select>
            </div>
          </div>
        )}

        {/* live feedback */}
        <div className="mt-3 text-xs text-zinc-500">{t.preview}:</div>
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
                {`\\${d.name}${d.arg}`}
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

// ─── per-tag control ─────────────────────────────────────────────────────────
type Ctl = "toggle" | "color" | "pos" | "align" | "scalar" | "raw";

const TOGGLE = new Set(["b", "i", "u", "s"]);
const COLOR = new Set(["c", "1c", "2c", "3c", "4c"]);
const POS = new Set(["pos", "move", "org"]);
const ALIGN = new Set(["an", "a"]);
const SCALAR = new Set([
  "fs", "fsp", "fscx", "fscy", "frx", "fry", "frz", "fr", "fax", "fay",
  "bord", "xbord", "ybord", "shad", "xshad", "yshad", "be", "blur",
  "k", "kf", "ko", "kt", "K",
]);

const ADDABLE = ["b", "i", "u", "s", "1c", "fs", "fscx", "fscy", "frz", "bord", "shad", "blur", "pos", "an", "fad", "r"];

function ctlFor(name: string): Ctl {
  if (TOGGLE.has(name)) return "toggle";
  if (COLOR.has(name)) return "color";
  if (POS.has(name)) return "pos";
  if (ALIGN.has(name)) return "align";
  if (SCALAR.has(name)) return "scalar";
  return "raw";
}

function defaultArg(name: string): string {
  const k = ctlFor(name);
  if (k === "toggle") return "1";
  if (k === "color") return "&H0000FF"; // red-ish placeholder
  if (k === "pos") return name === "move" ? "(0,0,0,0)" : "(960,540)";
  if (k === "align") return "8";
  if (k === "scalar") return "0";
  if (name === "fad" || name === "fade") return "(200,200)";
  return "";
}

function TagRow({
  tag,
  onChange,
  onRemove,
}: {
  tag: DecodedTag;
  onChange: (arg: string) => void;
  onRemove: () => void;
}) {
  const kind = ctlFor(tag.name);
  return (
    <div className="flex items-center gap-2">
      <span
        className={`w-14 shrink-0 rounded px-1 py-0.5 text-center font-mono text-[11px] ${
          tag.known ? "bg-zinc-800 text-zinc-200" : "bg-amber-900/40 text-amber-200"
        }`}
        title={tag.known ? "known" : "unknown (preserved)"}
      >
        {`\\${tag.name}`}
      </span>

      <div className="flex flex-1 items-center gap-1">
        {kind === "toggle" && (
          <label className="flex items-center gap-1 text-xs text-zinc-300">
            <input
              type="checkbox"
              checked={tag.arg.trim() === "1"}
              onChange={(e) => onChange(e.target.checked ? "1" : "0")}
            />
            on
          </label>
        )}

        {kind === "color" && (
          <input
            type="color"
            value={assColorToHex(tag.arg)}
            onChange={(e) => onChange(hexToAssColor(e.target.value))}
            className="h-6 w-10 cursor-pointer rounded border border-zinc-700 bg-transparent p-0"
          />
        )}

        {kind === "pos" && (
          <PosInputs arg={tag.arg} onChange={onChange} />
        )}

        {kind === "align" && (
          <select
            value={tag.arg.trim()}
            onChange={(e) => onChange(e.target.value)}
            className="rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 text-xs text-zinc-200 outline-none"
          >
            {[7, 8, 9, 4, 5, 6, 1, 2, 3].map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        )}

        {kind === "scalar" && (
          <input
            type="number"
            value={tag.arg}
            onChange={(e) => onChange(e.target.value)}
            className="w-20 rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 text-xs text-zinc-200 outline-none"
          />
        )}

        {kind === "raw" && (
          <input
            type="text"
            value={tag.arg}
            spellCheck={false}
            onChange={(e) => onChange(e.target.value)}
            className="w-full rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 font-mono text-xs text-zinc-200 outline-none"
          />
        )}
      </div>

      <button
        onClick={onRemove}
        className="shrink-0 rounded px-1.5 py-0.5 text-xs text-zinc-500 hover:bg-rose-900/40 hover:text-rose-300"
        title="remove"
      >
        ✕
      </button>
    </div>
  );
}

// Parse "(a,b[,c,d])" into numeric inputs and rebuild on change.
function PosInputs({ arg, onChange }: { arg: string; onChange: (arg: string) => void }) {
  const inner = arg.replace(/^\(/, "").replace(/\)$/, "");
  const parts = inner.length ? inner.split(",") : ["0", "0"];
  const set = (i: number, v: string) => {
    const next = parts.slice();
    next[i] = v;
    onChange(`(${next.join(",")})`);
  };
  return (
    <div className="flex items-center gap-1">
      {parts.map((p, i) => (
        <input
          key={i}
          type="number"
          value={p.trim()}
          onChange={(e) => set(i, e.target.value)}
          className="w-16 rounded border border-zinc-700 bg-zinc-900 px-1.5 py-0.5 text-xs text-zinc-200 outline-none"
        />
      ))}
    </div>
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
