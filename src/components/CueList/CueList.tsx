import { useEffect, useState } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { useMediaStore } from "../../stores/useMediaStore";
import { sortedCues } from "../../formats/srt";
import { CueRow } from "./CueRow";

interface CtxMenu {
  x: number;
  y: number;
  cueId: string;
}

/** True when the event originates from a text-entry control — keyboard
 *  navigation must not fire while the user is typing. */
function isTyping(e: KeyboardEvent): boolean {
  const el = e.target as HTMLElement | null;
  if (!el) return false;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

export function CueList() {
  const { t } = useI18nStore();
  const doc = useSubtitleStore((s) => s.doc);
  const selectedIds = useSubtitleStore((s) => s.selectedIds);
  const activeCueId = useSubtitleStore((s) => s.activeCueId);
  const showTranslation = useSettingsStore((s) => s.showTranslation);

  const cues = sortedCues(doc.cues);
  const styleNames = (doc.styles ?? []).map((s) => s.name);
  const [ctx, setCtx] = useState<CtxMenu | null>(null);

  // Keyboard controls (outside text fields, no modifiers):
  //  ↑/↓  move the active cue (row effect scrolls it into view; seeks with media)
  //  I    live timing: stamp the playhead as the active cue's START
  //  O    live timing: stamp the playhead as the END, then advance to the next cue
  //  P    live timing: like O, but also snap the NEXT cue's start to the same
  //       time (continuous dialogue timing) — one undo step
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (isTyping(e) || e.metaKey || e.ctrlKey || e.altKey) return;

      if (e.key === "ArrowUp" || e.key === "ArrowDown") {
        const s = useSubtitleStore.getState();
        const list = sortedCues(s.doc.cues);
        if (!list.length) return;
        e.preventDefault();
        const idx = list.findIndex((c) => c.id === s.activeCueId);
        const next =
          idx === -1
            ? list[0]
            : list[Math.max(0, Math.min(list.length - 1, idx + (e.key === "ArrowDown" ? 1 : -1)))];
        if (next.id === s.activeCueId) return;
        s.setActiveCue(next.id);
        if (useMediaStore.getState().mediaSrc) useMediaStore.getState().seek(next.start);
        return;
      }

      const key = e.key.toLowerCase();
      if (key !== "i" && key !== "o" && key !== "p") return;
      const media = useMediaStore.getState();
      if (!media.mediaSrc) return; // timing keys only make sense with media
      const s = useSubtitleStore.getState();
      const list = sortedCues(s.doc.cues);
      const idx = list.findIndex((c) => c.id === s.activeCueId);
      if (idx === -1) return;
      e.preventDefault();
      const tNow = media.currentTime;
      const active = list[idx];
      const next = list[idx + 1] ?? null;

      if (key === "i") {
        s.updateCue(active.id, { start: tNow });
      } else if (key === "o") {
        s.updateCue(active.id, { end: tNow });
        if (next) s.setActiveCue(next.id);
      } else {
        // P: end this cue AND start the next at the same instant (one undo).
        const edits: Array<{ id: string; patch: { start?: number; end?: number } }> = [
          { id: active.id, patch: { end: tNow } },
        ];
        if (next) edits.push({ id: next.id, patch: { start: tNow } });
        s.batchUpdateCues(edits);
        if (next) s.setActiveCue(next.id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  if (!cues.length) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 bg-zinc-950 text-zinc-500">
        <p className="text-lg">{t.noCues}</p>
        <p className="text-sm">{t.emptyHint}</p>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col bg-zinc-950">
      {/* header */}
      <div className="flex shrink-0 border-b border-zinc-700 bg-zinc-900 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">
        <div className="w-10 py-2 text-center">{t.cueNumber}</div>
        <div className="w-24 border-l border-zinc-800/60 py-2 text-center">{t.start}</div>
        <div className="w-24 border-l border-zinc-800/60 py-2 text-center">{t.end}</div>
        <div className="w-20 py-2 text-center">{t.duration}</div>
        {styleNames.length > 0 && <div className="w-28 border-l border-zinc-800/60 py-2 pl-2">{t.cueStyle}</div>}
        <div className="flex-1 py-2 pl-2">{t.text}</div>
        {showTranslation && <div className="flex-1 border-l border-zinc-800/60 py-2 pl-2">{t.translation}</div>}
        <div className="w-6" />
      </div>
      {/* rows */}
      <div className="ws-scroll flex-1 overflow-y-auto">
        {cues.map((cue, i) => (
          <CueRow
            key={cue.id}
            cue={cue}
            index={i}
            prev={i > 0 ? cues[i - 1] : null}
            selected={selectedIds.has(cue.id)}
            active={activeCueId === cue.id}
            styleNames={styleNames}
            showTranslation={showTranslation}
            onContextMenu={(e) => {
              e.preventDefault();
              useSubtitleStore.getState().setActiveCue(cue.id);
              setCtx({ x: e.clientX, y: e.clientY, cueId: cue.id });
            }}
          />
        ))}
      </div>
      {ctx && <ContextMenu ctx={ctx} onClose={() => setCtx(null)} />}
    </div>
  );
}

/** Right-click context menu for a cue row. */
function ContextMenu({ ctx, onClose }: { ctx: CtxMenu; onClose: () => void }) {
  const { t } = useI18nStore();
  const hasMedia = useMediaStore((s) => s.mediaSrc != null);
  const selectedCount = useSubtitleStore((s) => s.selectedIds.size);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const run = (fn: () => void) => () => {
    fn();
    onClose();
  };
  const s = () => useSubtitleStore.getState();
  const cue = () => s().doc.cues.find((c) => c.id === ctx.cueId);

  const items: Array<{ label: string; onClick: () => void; disabled?: boolean } | "sep"> = [
    {
      label: t.ctxPlayHere,
      disabled: !hasMedia,
      onClick: run(() => {
        const c = cue();
        if (c) useMediaStore.getState().seek(c.start);
      }),
    },
    "sep",
    { label: t.ctxInsertAfter, onClick: run(() => s().insertCueAfter(ctx.cueId)) },
    {
      label: t.splitCue,
      onClick: run(() => {
        const c = cue();
        if (!c) return;
        // Prefer the playhead as the split point when it falls inside the cue.
        const tNow = useMediaStore.getState().currentTime;
        const at = tNow > c.start && tNow < c.end ? tNow : (c.start + c.end) / 2;
        s().splitCue(ctx.cueId, at);
      }),
    },
    {
      label: t.mergeCues,
      disabled: selectedCount < 2,
      onClick: run(() => s().mergeCues([...s().selectedIds])),
    },
    { label: t.editTags, onClick: run(() => useSettingsStore.getState().openTagEditor()) },
    "sep",
    {
      label: t.deleteCue,
      onClick: run(() => {
        // Delete the whole selection when the clicked cue is part of it.
        const sel = s().selectedIds;
        s().deleteCues(sel.has(ctx.cueId) ? [...sel] : [ctx.cueId]);
      }),
    },
  ];

  return (
    <>
      {/* click-away layer */}
      <div className="fixed inset-0 z-[60]" onClick={onClose} onContextMenu={(e) => { e.preventDefault(); onClose(); }} />
      <div
        className="fixed z-[61] min-w-[160px] rounded-lg border border-zinc-700 bg-zinc-900 py-1 shadow-2xl"
        style={{ left: ctx.x, top: ctx.y }}
      >
        {items.map((item, i) =>
          item === "sep" ? (
            <div key={i} className="my-1 h-px bg-zinc-800" />
          ) : (
            <button
              key={i}
              disabled={item.disabled}
              onClick={item.onClick}
              className="block w-full px-3 py-1.5 text-left text-sm text-zinc-200 transition-colors hover:bg-indigo-600 hover:text-white disabled:cursor-default disabled:text-zinc-600 disabled:hover:bg-transparent"
            >
              {item.label}
            </button>
          ),
        )}
      </div>
    </>
  );
}
