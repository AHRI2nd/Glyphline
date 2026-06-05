import {
  SkipBack,
  Rewind,
  Play,
  Pause,
  FastForward,
  SkipForward,
  Plus,
} from "lucide-react";
import { useMediaStore, PLAYBACK_RATES } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { formatDisplayTime } from "../../utils/time";

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
    <div className="flex items-center gap-1 border-t border-zinc-800 bg-zinc-900 px-2 py-1.5 text-zinc-300">
      <IconBtn onClick={() => skip(-5)} title="-5s"><SkipBack size={14} /></IconBtn>
      <IconBtn onClick={() => skip(-1)} title="-1s"><Rewind size={14} /></IconBtn>
      <IconBtn
        onClick={togglePlay}
        title="Play / Pause"
        className="rounded bg-zinc-700 p-1.5 hover:bg-zinc-600"
      >
        {isPlaying ? <Pause size={16} /> : <Play size={16} />}
      </IconBtn>
      <IconBtn onClick={() => skip(1)} title="+1s"><FastForward size={14} /></IconBtn>
      <IconBtn onClick={() => skip(5)} title="+5s"><SkipForward size={14} /></IconBtn>

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
          <option key={r} value={r}>{r}×</option>
        ))}
      </select>

      <button
        onClick={addCueAtPlayhead}
        className="ml-1 flex items-center gap-0.5 rounded bg-indigo-600 px-2 py-0.5 text-xs text-white transition-colors hover:bg-indigo-500"
        title={t.addCueAtPlayhead}
      >
        <Plus size={11} strokeWidth={2.5} />
        {t.cueHere}
      </button>
    </div>
  );
}

function IconBtn({
  children,
  onClick,
  title,
  className,
}: {
  children: React.ReactNode;
  onClick: () => void;
  title: string;
  className?: string;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      className={
        className ??
        "flex items-center justify-center rounded p-1 transition-colors hover:bg-zinc-800"
      }
    >
      {children}
    </button>
  );
}
