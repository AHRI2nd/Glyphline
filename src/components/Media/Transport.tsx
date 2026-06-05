import { useMediaStore, PLAYBACK_RATES } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { formatDisplayTime } from "../../utils/time";

// Playback transport + "add cue at playhead" helper.
export function Transport() {
  const { t } = useI18nStore();
  const isPlaying = useMediaStore((s) => s.isPlaying);
  const currentTime = useMediaStore((s) => s.currentTime);
  const duration = useMediaStore((s) => s.duration);
  const playbackRate = useMediaStore((s) => s.playbackRate);
  const { togglePlay, skip, setPlaybackRate } = useMediaStore();

  const addCueAtPlayhead = () => {
    const end = duration > 0 ? Math.min(currentTime + 2, duration) : currentTime + 2;
    useSubtitleStore.getState().addCueAt(currentTime, end);
  };

  return (
    <div className="flex items-center gap-1.5 border-t border-zinc-800 bg-zinc-900 px-2 py-1.5 text-zinc-300">
      <IconBtn onClick={() => skip(-5)} title="-5s">⏪</IconBtn>
      <IconBtn onClick={() => skip(-1)} title="-1s">⟨</IconBtn>
      <IconBtn onClick={togglePlay} title="Play / Pause">{isPlaying ? "⏸" : "▶"}</IconBtn>
      <IconBtn onClick={() => skip(1)} title="+1s">⟩</IconBtn>
      <IconBtn onClick={() => skip(5)} title="+5s">⏩</IconBtn>

      <span className="ml-2 font-mono text-xs text-zinc-400">
        {formatDisplayTime(currentTime)} / {formatDisplayTime(duration)}
      </span>

      <select
        value={playbackRate}
        onChange={(e) => setPlaybackRate(Number(e.target.value))}
        className="ml-auto rounded bg-zinc-800 px-1 py-0.5 text-xs text-zinc-200 outline-none"
        title="Speed"
      >
        {PLAYBACK_RATES.map((r) => (
          <option key={r} value={r}>
            {r}×
          </option>
        ))}
      </select>

      <button
        onClick={addCueAtPlayhead}
        className="rounded bg-indigo-600 px-2 py-0.5 text-xs text-white hover:bg-indigo-500"
        title={t.addCueAtPlayhead}
      >
        ＋ {t.cueHere}
      </button>
    </div>
  );
}

function IconBtn({ children, onClick, title }: { children: React.ReactNode; onClick: () => void; title: string }) {
  return (
    <button onClick={onClick} title={title} className="rounded px-1.5 py-0.5 text-sm hover:bg-zinc-800">
      {children}
    </button>
  );
}
