import { useRef, useState } from "react";
import {
  SkipBack,
  Play,
  Pause,
  SkipForward,
  Plus,
  ChevronLeft,
  ChevronRight,
  Repeat,
  Volume2,
  VolumeX,
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
  const volume = useMediaStore((s) => s.volume);
  const muted = useMediaStore((s) => s.muted);
  const looping = useMediaStore((s) => s.loopRegion != null);
  const { togglePlay, skip, frameStep, setPlaybackRate, seek, setVolume, toggleMute, playRegion, clearLoop } =
    useMediaStore();

  const addCueAtPlayhead = () => {
    const end = duration > 0 ? Math.min(currentTime + 2, duration) : currentTime + 2;
    useSubtitleStore.getState().addCueAt(currentTime, end);
  };

  // Loop over the active cue (toggle). Falls back to any single selected cue.
  const toggleLoopActive = () => {
    if (looping) {
      clearLoop();
      return;
    }
    const s = useSubtitleStore.getState();
    const cue = s.doc.cues.find((c) => c.id === s.activeCueId);
    if (cue) playRegion(cue.start, cue.end);
  };

  return (
    <div className="flex flex-col border-t border-zinc-800 bg-zinc-900 text-zinc-300">
      <SeekBar currentTime={currentTime} duration={duration} onSeek={seek} />
      <div className="flex items-center gap-1 px-2 pb-1.5 pt-1">
      <IconBtn onClick={() => skip(-5)} title="-5s"><SkipBack size={14} /></IconBtn>
      <IconBtn onClick={() => frameStep(false)} title={t.frameBack}><ChevronLeft size={14} /></IconBtn>
      <IconBtn
        onClick={togglePlay}
        title="Play / Pause"
        className="rounded bg-zinc-700 p-1.5 hover:bg-zinc-600"
      >
        {isPlaying ? <Pause size={16} /> : <Play size={16} />}
      </IconBtn>
      <IconBtn onClick={() => frameStep(true)} title={t.frameForward}><ChevronRight size={14} /></IconBtn>
      <IconBtn onClick={() => skip(5)} title="+5s"><SkipForward size={14} /></IconBtn>
      <IconBtn
        onClick={toggleLoopActive}
        title={t.loopActiveCue}
        className={`flex items-center justify-center rounded p-1 transition-colors ${
          looping ? "bg-indigo-600 text-white hover:bg-indigo-500" : "hover:bg-zinc-800"
        }`}
      >
        <Repeat size={14} />
      </IconBtn>

      <span className="ml-2 font-mono text-xs text-zinc-400">
        {formatDisplayTime(currentTime)} / {formatDisplayTime(duration)}
      </span>

      {/* volume */}
      <div className="ml-auto flex items-center gap-1" title={`${t.volume} ${Math.round(volume)}%`}>
        <IconBtn onClick={toggleMute} title={t.mute}>
          {muted || volume === 0 ? <VolumeX size={14} /> : <Volume2 size={14} />}
        </IconBtn>
        <input
          type="range"
          min={0}
          max={130}
          value={muted ? 0 : volume}
          onChange={(e) => setVolume(Number(e.target.value))}
          className="h-1 w-16 accent-indigo-500"
        />
      </div>

      <select
        value={playbackRate}
        onChange={(e) => setPlaybackRate(Number(e.target.value))}
        className="rounded bg-zinc-800 px-1 py-0.5 text-xs text-zinc-200 outline-none"
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
    </div>
  );
}

// Clickable / draggable progress bar. Computes the target time from the pointer
// position within the track and seeks mpv (which drives currentTime back).
function SeekBar({
  currentTime,
  duration,
  onSeek,
}: {
  currentTime: number;
  duration: number;
  onSeek: (sec: number) => void;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const rafRef = useRef<number | null>(null);
  const lastXRef = useRef<number>(0);
  // While dragging, show the pointer position — not mpv's (lagging) time-pos.
  // Otherwise the handle visibly fights the 80 ms poll and jumps backwards.
  const [dragFrac, setDragFrac] = useState<number | null>(null);
  const pct =
    dragFrac != null
      ? dragFrac * 100
      : duration > 0
        ? Math.min(100, (currentTime / duration) * 100)
        : 0;

  const fracAtClientX = (clientX: number): number | null => {
    const el = trackRef.current;
    if (!el || duration <= 0) return null;
    const r = el.getBoundingClientRect();
    return Math.max(0, Math.min(1, (clientX - r.left) / r.width));
  };
  const seekToClientX = (clientX: number) => {
    const frac = fracAtClientX(clientX);
    if (frac != null) onSeek(frac * duration);
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (duration <= 0) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    setDragFrac(fracAtClientX(e.clientX));
    seekToClientX(e.clientX);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (e.buttons !== 1) return; // only while dragging
    lastXRef.current = e.clientX;
    setDragFrac(fracAtClientX(e.clientX));
    // RAF throttle: one invoke per animation frame max. Without this, dragging at
    // high speed fires hundreds of mpv_seek calls/sec, flooding IPC and mpv.
    if (rafRef.current != null) return;
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null;
      seekToClientX(lastXRef.current);
    });
  };
  const onPointerUp = (e: React.PointerEvent) => {
    // Final seek at exact release position (cancels any pending RAF seek).
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
    seekToClientX(e.clientX);
    setDragFrac(null);
  };

  return (
    <div
      ref={trackRef}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      className="group relative h-3 w-full cursor-pointer select-none"
      title="탐색"
    >
      {/* track */}
      <div className="absolute inset-x-0 top-1/2 h-1 -translate-y-1/2 bg-zinc-700" />
      {/* fill */}
      <div
        className="absolute left-0 top-1/2 h-1 -translate-y-1/2 bg-indigo-500"
        style={{ width: `${pct}%` }}
      />
      {/* playhead handle */}
      <div
        className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-indigo-400 opacity-0 transition-opacity group-hover:opacity-100"
        style={{ left: `${pct}%` }}
      />
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
