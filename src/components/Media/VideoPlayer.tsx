import { useEffect, useRef } from "react";
import { useMediaStore, bindVideoEl } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";

export function VideoPlayer() {
  const ref = useRef<HTMLVideoElement>(null);
  const mediaSrc = useMediaStore((s) => s.mediaSrc);
  const mediaKind = useMediaStore((s) => s.mediaKind);
  const mediaName = useMediaStore((s) => s.mediaName);
  const currentTime = useMediaStore((s) => s.currentTime);
  const setCurrentTime = useMediaStore((s) => s.setCurrentTime);
  const setDuration = useMediaStore((s) => s.setDuration);
  const setPlaying = useMediaStore((s) => s.setPlaying);
  const isTranscoding = useMediaStore((s) => s.isTranscoding);
  const transcodeError = useMediaStore((s) => s.transcodeError);
  const ffmpegMissing = useMediaStore((s) => s.ffmpegMissing);
  const openSettings = useSettingsStore((s) => s.openSettingsModal);
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
  const hasMedia = mediaSrc != null || isTranscoding;

  return (
    <div className="relative flex h-full items-center justify-center bg-black">
      {/* No media */}
      {!hasMedia && !transcodeError && (
        <div className="px-4 text-center text-xs text-zinc-600">{t.noMedia}</div>
      )}

      {/* FFmpeg transcoding in progress */}
      {isTranscoding && (
        <div className="flex flex-col items-center gap-3">
          <div className="h-7 w-7 animate-spin rounded-full border-2 border-zinc-700 border-t-indigo-400" />
          <span className="text-xs text-zinc-400">변환 중…</span>
        </div>
      )}

      {/* FFmpeg not installed */}
      {ffmpegMissing && (
        <div className="flex max-w-xs flex-col items-center gap-3 rounded border border-amber-800 bg-amber-950/40 p-4 text-center">
          <span className="text-sm text-amber-300">FFmpeg가 설치되어 있지 않아<br />이 형식을 재생할 수 없습니다.</span>
          <button
            onClick={openSettings}
            className="rounded bg-indigo-600 px-3 py-1.5 text-xs text-white hover:bg-indigo-500 transition-colors"
          >
            설정에서 FFmpeg 설치
          </button>
        </div>
      )}

      {/* Transcoding / playback error */}
      {transcodeError && (
        <div className="max-w-xs rounded border border-rose-800 bg-rose-950/50 p-4 text-xs text-rose-300 whitespace-pre-wrap">
          {transcodeError}
        </div>
      )}

      {/* Audio-only placeholder (show while media is ready, not while transcoding) */}
      {isAudio && mediaSrc && !isTranscoding && (
        <div className="flex flex-col items-center gap-2 text-zinc-500">
          <span className="text-4xl">♪</span>
          <span className="max-w-[90%] truncate px-4 text-xs">{mediaName}</span>
        </div>
      )}

      {/* The <video> element — always mounted so VideoPlayer can register it as
          the playback source. Hidden for audio and when there is no src yet. */}
      <video
        ref={ref}
        src={mediaSrc ?? undefined}
        className={isAudio || !mediaSrc ? "hidden" : "max-h-full w-full"}
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration)}
        onTimeUpdate={(e) => setCurrentTime(e.currentTarget.currentTime)}
        onSeeking={(e) => setCurrentTime(e.currentTarget.currentTime)}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
      />

      {/* Active cue overlay */}
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
