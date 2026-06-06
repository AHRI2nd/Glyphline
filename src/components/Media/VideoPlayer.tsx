import { useEffect, useRef } from "react";
import { useMediaStore, bindVideoEl } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";

export function VideoPlayer() {
  const ref = useRef<HTMLVideoElement>(null);
  const mediaSrc = useMediaStore((s) => s.mediaSrc);
  const mediaKind = useMediaStore((s) => s.mediaKind);
  const mediaName = useMediaStore((s) => s.mediaName);
  const currentTime = useMediaStore((s) => s.currentTime);
  const setCurrentTime = useMediaStore((s) => s.setCurrentTime);
  const setDuration = useMediaStore((s) => s.setDuration);
  const setPlaying = useMediaStore((s) => s.setPlaying);
  const cues = useSubtitleStore((s) => s.doc.cues);

  // Register the element as the global playback source.
  useEffect(() => {
    bindVideoEl(ref.current);
    return () => bindVideoEl(null);
  }, []);

  // The cue visible at the current time → overlay + active-row highlight.
  const active = cues.find((c) => currentTime >= c.start && currentTime < c.end) ?? null;
  const lastActiveId = useRef<string | null>(null);
  useEffect(() => {
    if (active?.id !== lastActiveId.current) {
      lastActiveId.current = active?.id ?? null;
      if (active) useSubtitleStore.getState().setActiveCue(active.id);
    }
  }, [active?.id]);

  const { t } = useI18nStore();
  const isAudio = mediaKind === "audio";
  const hasMedia = mediaSrc != null;

  return (
    <div className="relative flex h-full items-center justify-center bg-black">
      {!hasMedia && <div className="px-4 text-center text-xs text-zinc-600">{t.noMedia}</div>}
      {/* Audio-only files: the <video> element still plays + drives the waveform,
          but is hidden; show a placeholder instead of a black rectangle. */}
      {isAudio && (
        <div className="flex flex-col items-center gap-2 text-zinc-500">
          <span className="text-4xl">♪</span>
          <span className="max-w-[90%] truncate px-4 text-xs">{mediaName}</span>
        </div>
      )}
      <video
        ref={ref}
        src={mediaSrc ?? undefined}
        className={isAudio || !hasMedia ? "hidden" : "max-h-full w-full"}
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration)}
        onTimeUpdate={(e) => setCurrentTime(e.currentTarget.currentTime)}
        onSeeking={(e) => setCurrentTime(e.currentTarget.currentTime)}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
      />
      {active && (
        <div className="pointer-events-none absolute inset-x-0 bottom-3 flex justify-center px-4">
          <span
            className="whitespace-pre-wrap rounded bg-black/60 px-3 py-1 text-center text-lg font-medium leading-snug text-white"
            style={{ textShadow: "0 1px 2px rgba(0,0,0,0.9)" }}
          >
            {active.text}
          </span>
        </div>
      )}
    </div>
  );
}
