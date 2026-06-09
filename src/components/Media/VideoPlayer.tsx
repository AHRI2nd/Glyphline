import { useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useMediaStore } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { serializeAss } from "../../formats/ass";

export function VideoPlayer() {
  const containerRef  = useRef<HTMLDivElement>(null);
  const [mpvAvailable, setMpvAvailable] = useState<boolean>(true);

  const mediaPath   = useMediaStore((s) => s.mediaPath);
  const mediaKind   = useMediaStore((s) => s.mediaKind);
  const mediaName   = useMediaStore((s) => s.mediaName);
  const currentTime = useMediaStore((s) => s.currentTime);
  const error       = useMediaStore((s) => s.error);
  const cues        = useSubtitleStore((s) => s.doc.cues);
  const openSettings = useSettingsStore((s) => s.openSettingsModal);
  const { t }       = useI18nStore();

  const isAudio  = mediaKind === "audio";
  const hasMedia = mediaPath != null;
  // The mpv window should cover the panel only when there's an actual video.
  const showVideo = mpvAvailable && hasMedia && !isAudio && !error;

  // ── Initialise mpv (deferred from Rust setup so the NSWindow is ready) ─────
  // mpv_init records the Tauri parent window and creates the mpv handle.
  // Idempotent — safe to call again on dock re-mount.
  useEffect(() => {
    invoke("mpv_init")
      .then(() => setMpvAvailable(true))
      .catch(() => setMpvAvailable(false));
  }, []);

  // ── Position the video surface over the panel + repaint ────────────────────
  // mpv_set_bounds moves/resizes our GL child window and repaints the current
  // frame. We fire on mount, on media load, on a timer ramp (GL surface is set up
  // asynchronously), and on panel resize. We do NOT track window MOVE: the child
  // window is OS-attached to the parent and follows it automatically — handling
  // move ourselves only fights the OS and caused the old jank.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const sendBounds = () => {
      const r = el.getBoundingClientRect();
      invoke("mpv_set_bounds", {
        x: r.left,
        y: r.top,
        w: r.width,
        h: r.height,
        dpr: window.devicePixelRatio,
        viewportH: window.innerHeight,
      }).catch(() => {});
    };

    sendBounds();
    const timers = [150, 350, 600, 1000, 1600, 2400].map((ms) =>
      window.setTimeout(sendBounds, ms),
    );
    const ro = new ResizeObserver(sendBounds);
    ro.observe(el);
    window.addEventListener("resize", sendBounds);

    return () => {
      timers.forEach(clearTimeout);
      ro.disconnect();
      window.removeEventListener("resize", sendBounds);
    };
  }, [mediaPath]);

  // ── Show/hide the mpv window so React placeholders aren't covered ──────────
  useEffect(() => {
    invoke("mpv_set_window_visible", { visible: showVideo }).catch(() => {});
    return () => {
      // Hide on unmount (dock re-layout) so a stray black window can't linger.
      invoke("mpv_set_window_visible", { visible: false }).catch(() => {});
    };
  }, [showVideo]);

  // ── Push the editing doc to mpv's subtitle renderer ───────────────────────
  // React can't draw on top of the native mpv window, so mpv renders the subs.
  // We serialize the doc to ASS (lossless styling for ASS docs; default style for
  // others) and reload it, debounced, on every cue-timing/text change.
  const subSignature = useMemo(
    () => cues.map((c) => `${c.id}:${c.start.toFixed(3)}:${c.end.toFixed(3)}:${c.text}`).join("\n"),
    [cues],
  );
  useEffect(() => {
    if (!showVideo) return;
    const id = window.setTimeout(() => {
      const ass = serializeAss(useSubtitleStore.getState().doc);
      invoke("mpv_set_subs", { content: ass }).catch(() => {});
    }, 300);
    return () => clearTimeout(id);
  }, [subSignature, showVideo, mediaPath]);

  // ── Active cue → row highlight + waveform region (NOT a video overlay) ─────
  const active = cues.find((c) => currentTime >= c.start && currentTime < c.end) ?? null;
  const lastActiveId = useRef<string | null>(null);
  useEffect(() => {
    if (active?.id !== lastActiveId.current) {
      lastActiveId.current = active?.id ?? null;
      if (active) useSubtitleStore.getState().setActiveCue(active.id);
    }
  }, [active?.id]);

  return (
    // The adopted mpv window floats above this panel and renders the video +
    // subtitles. These children only show through the gaps (when no video is
    // playing) — i.e. the placeholders below.
    <div ref={containerRef} className="relative flex h-full items-center justify-center">

      {/* mpv not installed */}
      {!mpvAvailable && (
        <div className="flex max-w-xs flex-col items-center gap-3 rounded border border-amber-800 bg-amber-950/40 p-4 text-center">
          <span className="text-sm text-amber-300">
            mpv가 설치되어 있지 않아<br />영상을 재생할 수 없습니다.
          </span>
          <button
            onClick={openSettings}
            className="rounded bg-indigo-600 px-3 py-1.5 text-xs text-white transition-colors hover:bg-indigo-500"
          >
            설정에서 mpv 설치
          </button>
        </div>
      )}

      {/* No media loaded */}
      {mpvAvailable && !hasMedia && !error && (
        <div className="px-4 text-center text-xs text-zinc-600">{t.noMedia}</div>
      )}

      {/* Error */}
      {error && (
        <div className="max-w-xs rounded border border-rose-800 bg-rose-950/80 p-4 text-xs text-rose-300 whitespace-pre-wrap">
          {error}
        </div>
      )}

      {/* Audio-only placeholder (mpv window is hidden for audio) */}
      {isAudio && hasMedia && !error && (
        <div className="flex flex-col items-center gap-2 text-zinc-500">
          <span className="text-4xl">♪</span>
          <span className="max-w-[90%] truncate px-4 text-xs">{mediaName}</span>
        </div>
      )}
    </div>
  );
}
