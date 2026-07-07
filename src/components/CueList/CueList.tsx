import { useEffect } from "react";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { useMediaStore } from "../../stores/useMediaStore";
import { sortedCues } from "../../formats/srt";
import { CueRow } from "./CueRow";

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

  // ↑/↓ move the active cue (outside text fields). The row effect scrolls it
  // into view; with media loaded, also seek the playhead to the cue start.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
      if (isTyping(e) || e.metaKey || e.ctrlKey || e.altKey) return;
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
          />
        ))}
      </div>
    </div>
  );
}
