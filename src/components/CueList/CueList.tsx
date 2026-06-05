import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { sortedCues } from "../../formats/srt";
import { CueRow } from "./CueRow";

export function CueList() {
  const { t } = useI18nStore();
  const doc = useSubtitleStore((s) => s.doc);
  const selectedIds = useSubtitleStore((s) => s.selectedIds);
  const activeCueId = useSubtitleStore((s) => s.activeCueId);

  const cues = sortedCues(doc.cues);
  const styleNames = (doc.styles ?? []).map((s) => s.name);

  if (!cues.length) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 text-zinc-500">
        <p className="text-lg">{t.noCues}</p>
        <p className="text-sm">{t.emptyHint}</p>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {/* header */}
      <div className="flex shrink-0 border-b border-zinc-700 bg-zinc-900 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">
        <div className="w-10 py-2 text-center">{t.cueNumber}</div>
        <div className="w-24 border-l border-zinc-800/60 py-2 text-center">{t.start}</div>
        <div className="w-24 border-l border-zinc-800/60 py-2 text-center">{t.end}</div>
        <div className="w-20 py-2 text-center">{t.duration}</div>
        {styleNames.length > 0 && <div className="w-28 border-l border-zinc-800/60 py-2 pl-2">{t.cueStyle}</div>}
        <div className="flex-1 py-2 pl-2">{t.text}</div>
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
          />
        ))}
      </div>
    </div>
  );
}
