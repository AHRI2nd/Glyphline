import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useMediaStore } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";

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

  // Check mpv availability once on mount
  useEffect(() => {
    invoke<boolean>("check_mpv").then(setMpvAvailable).catch(() => setMpvAvailable(false));
  }, []);

  // ── Tell Rust where to position the native mpv NSView ──────────────────────
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
    const ro = new ResizeObserver(sendBounds);
    ro.observe(el);
    // Also update on window resize
    window.addEventListener("resize", sendBounds);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", sendBounds);
    };
  }, []);

  // ── Active cue → overlay + row highlight ──────────────────────────────────
  const active = cues.find((c) => currentTime >= c.start && currentTime < c.end) ?? null;
  const lastActiveId = useRef<string | null>(null);
  useEffect(() => {
    if (active?.id !== lastActiveId.current) {
      lastActiveId.current = active?.id ?? null;
      if (active) useSubtitleStore.getState().setActiveCue(active.id);
    }
  }, [active?.id]);

  return (
    // bg-transparent: lets the native mpv NSView render through.
    // The Tauri window has transparent:true, and this div has no background,
    // so WKWebView is see-through here and mpv's NSView (beneath) is visible.
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

      {/* Audio-only placeholder */}
      {isAudio && hasMedia && !error && (
        <div className="flex flex-col items-center gap-2 text-zinc-500">
          <span className="text-4xl">♪</span>
          <span className="max-w-[90%] truncate px-4 text-xs">{mediaName}</span>
        </div>
      )}

      {/* Active subtitle overlay */}
      {active && !isAudio && (
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
