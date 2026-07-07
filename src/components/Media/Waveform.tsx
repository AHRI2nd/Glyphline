import { useEffect, useMemo, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import RegionsPlugin, { type Region } from "wavesurfer.js/dist/plugins/regions.esm.js";
import { useMediaStore } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useI18nStore } from "../../stores/useI18nStore";

const NORMAL_COLOR = "rgba(99,102,241,0.18)";
const ACTIVE_COLOR = "rgba(99,102,241,0.38)";

// Log-scale zoom (same scheme as Lyrical Sync's AudioPlayer): equal slider
// movements give equal zoom *ratios*, and the default sits at the center.
//   level=0 → 10 px/s · level=50 → ~71 px/s (default) · level=100 → 500 px/s
// The waveform stays wider than the panel → it scrolls under a fixed centered
// playhead, instead of squeezing the whole file into the width.
const ZOOM_PX_MIN = 10;
const ZOOM_PX_MAX = 500;
const DEFAULT_ZOOM_LEVEL = 50;
const zoomLevelToPixels = (level: number) =>
  Math.round(ZOOM_PX_MIN * Math.pow(ZOOM_PX_MAX / ZOOM_PX_MIN, level / 100));

// Waveform driven by the media:// URL (independent audio decoder).
// mpv handles actual playback — we keep WaveSurfer muted and sync its cursor
// via mpv's time-pos events so the two stay in lockstep.
export function Waveform() {
  const containerRef = useRef<HTMLDivElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WaveSurfer | null>(null);
  const regionsRef = useRef<RegionsPlugin | null>(null);
  const buildingRef = useRef(false); // suppress region-created during programmatic adds
  const [ready, setReady] = useState(false);
  // Zoom slider level (0–100, log scale — see zoomLevelToPixels). Kept across
  // media loads so reopening a file doesn't reset the user's zoom.
  const [zoomLevel, setZoomLevel] = useState(DEFAULT_ZOOM_LEVEL);
  const zoomLevelRef = useRef(zoomLevel);
  zoomLevelRef.current = zoomLevel;

  const mediaSrc = useMediaStore((s) => s.mediaSrc);
  const waveformSrc = useMediaStore((s) => s.waveformSrc);
  const duration = useMediaStore((s) => s.duration);
  const currentTime = useMediaStore((s) => s.currentTime);
  const cues = useSubtitleStore((s) => s.doc.cues);
  const activeCueId = useSubtitleStore((s) => s.activeCueId);
  const { t } = useI18nStore();

  // Only rebuild regions when cue *timing* changes (not on text edits).
  const timingKey = useMemo(
    () => cues.map((c) => `${c.id}:${c.start.toFixed(3)}:${c.end.toFixed(3)}`).join("|"),
    [cues],
  );
  const cuesRef = useRef(cues);
  cuesRef.current = cues;

  // ── create / destroy ────────────────────────────────────────────────────────
  // WaveSurfer loads the backend-extracted downsampled WAV (waveformSrc), not the
  // original media — decoding a large video via WebAudio is impractical. Volume is
  // muted; mpv is the sole audio/playback source and drives the cursor.
  useEffect(() => {
    if (!containerRef.current || !waveformSrc) return;
    setReady(false);

    const ws = WaveSurfer.create({
      container: containerRef.current,
      url: waveformSrc,
      height: "auto", // fill the panel (taller now that the spectrogram is gone)
      waveColor: "#6366f1",
      progressColor: "#a5b4fc",
      cursorColor: "#f43f5e",
      normalize: true,
      // Zoomed scrolling waveform: render at the current px/s from the start
      // (no fit-then-jump). We scroll it ourselves to keep the playhead centered
      // (autoScroll/autoCenter only fire during real WS playback; here mpv drives
      // the cursor via setTime while WS stays muted/paused).
      minPxPerSec: zoomLevelToPixels(zoomLevelRef.current),
      autoScroll: false,
      autoCenter: false,
    });
    // Hide the horizontal scrollbar (defined in index.css) — wavesurfer scrolls
    // the zoomed waveform inside its own wrapper.
    ws.getWrapper().classList.add("ws-scroll");
    const regions = ws.registerPlugin(RegionsPlugin.create());
    wsRef.current = ws;
    regionsRef.current = regions;

    // Mute WaveSurfer's internal decoder — mpv provides all audio.
    ws.setVolume(0);

    // Click on the waveform → seek mpv there (mpv drives currentTime back).
    ws.on("interaction", (newTime: number) => {
      useMediaStore.getState().seek(newTime);
    });

    // Drag on empty waveform → create a cue.
    regions.enableDragSelection({ color: NORMAL_COLOR });
    regions.on("region-created", (region: Region) => {
      if (buildingRef.current) return; // our own programmatic region
      if (cuesRef.current.some((c) => c.id === region.id)) return;
      const start = region.start;
      const end = region.end ?? region.start + 2;
      region.remove();
      useSubtitleStore.getState().addCueAt(start, end);
    });
    // Click a region → seek mpv + select that cue.
    regions.on("region-clicked", (region: Region, e: MouseEvent) => {
      e.stopPropagation();
      useMediaStore.getState().seek(region.start);
      useSubtitleStore.getState().setActiveCue(region.id);
    });

    ws.on("ready", () => setReady(true));

    return () => {
      ws.destroy(); // also destroys registered plugins
      wsRef.current = null;
      regionsRef.current = null;
      setReady(false);
    };
  }, [waveformSrc]);

  // ── zoom (slider + Cmd/Ctrl+scroll + −/＋ buttons) ─────────────────────────
  // Debounced: dragging the slider fires many changes and ws.zoom() re-renders
  // the peaks each time (same 80 ms debounce as Lyrical Sync).
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws || !ready) return;
    const id = window.setTimeout(() => {
      ws.zoom(zoomLevelToPixels(zoomLevel));
      // Re-center at the new zoom (zoom changes total width → cursor px moves).
      centerOnCursor(useMediaStore.getState().currentTime);
    }, 80);
    return () => window.clearTimeout(id);
  }, [zoomLevel, ready]);

  const zoomStep = (delta: number) =>
    setZoomLevel((l) => Math.max(0, Math.min(100, l + delta)));

  // Scroll the zoomed waveform so the playhead (red cursor) sits at the panel
  // center. Near the start/end the content can't scroll further, so the cursor
  // moves toward the edge instead (clamped scrollLeft) — the requested behavior.
  const centerOnCursor = (time: number) => {
    const ws = wsRef.current;
    if (!ws) return;
    const d = ws.getDuration();
    if (!d) return;
    // scrollContainer = the wrapper's parent (the element wavesurfer overflows).
    const sc = ws.getWrapper().parentElement;
    if (!sc) return;
    const { scrollWidth, clientWidth } = sc;
    const cursorPx = (time / d) * scrollWidth;
    const target = Math.max(0, Math.min(cursorPx - clientWidth / 2, scrollWidth - clientWidth));
    sc.scrollLeft = target;
  };

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    // Native listener with passive:false — Cmd/Ctrl+wheel must preventDefault to
    // stop the page/system zoom gesture. Functional setState needs no ref dance.
    const onWheel = (e: WheelEvent) => {
      if (!(e.metaKey || e.ctrlKey)) return;
      e.preventDefault();
      setZoomLevel((l) => Math.max(0, Math.min(100, l + (e.deltaY < 0 ? 4 : -4))));
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, []);

  // ── keep WaveSurfer cursor in sync with mpv + keep it centered ─────────────
  // currentTime updates every ~80 ms from Rust's mpv poll thread. setTime() moves
  // the cursor; centerOnCursor() scrolls the waveform so the cursor stays centered
  // (or moves toward the edge near start/end). When paused, currentTime doesn't
  // change → this effect doesn't fire → the user can freely scroll/drag.
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws || !ready) return;
    ws.setTime(currentTime);
    centerOnCursor(currentTime);
  }, [currentTime, ready]);

  // ── reconcile regions to match cue timing ─────────────────────────────────────
  useEffect(() => {
    const regions = regionsRef.current;
    if (!regions || !ready) return;
    buildingRef.current = true;
    regions.clearRegions();
    for (const cue of cuesRef.current) {
      const region = regions.addRegion({
        id: cue.id,
        start: cue.start,
        end: cue.end,
        drag: true,
        resize: true,
        color: cue.id === activeCueId ? ACTIVE_COLOR : NORMAL_COLOR,
        content: cue.text.split("\n")[0].slice(0, 24),
      });
      // Commit retiming once, on pointer-up (one undo step per drag).
      region.on("update-end", () => {
        useSubtitleStore.getState().updateCue(cue.id, {
          start: Math.min(region.start, region.end),
          end: Math.max(region.start, region.end),
        });
      });
    }
    buildingRef.current = false;
  }, [timingKey, ready]);

  // ── reflect the active cue (highlight) without a full rebuild ──────────────────
  useEffect(() => {
    const regions = regionsRef.current;
    if (!regions) return;
    for (const r of regions.getRegions()) {
      r.setOptions({ color: r.id === activeCueId ? ACTIVE_COLOR : NORMAL_COLOR });
    }
  }, [activeCueId]);

  if (!mediaSrc) {
    return (
      <div className="flex h-full w-full items-center justify-center bg-zinc-900 text-xs text-zinc-600">
        {t.noMedia}
      </div>
    );
  }

  return (
    <div ref={wrapRef} className="flex h-full w-full flex-col overflow-hidden bg-zinc-900 px-2 py-2">
      <div className="mb-1 flex items-center justify-end gap-1">
        <button
          onClick={() => zoomStep(-10)}
          className="rounded bg-zinc-800 px-2 py-0.5 text-[10px] text-zinc-300 hover:bg-zinc-700"
          title={t.zoomOut}
        >
          −
        </button>
        <input
          type="range"
          min={0}
          max={100}
          value={zoomLevel}
          onChange={(e) => setZoomLevel(Number(e.target.value))}
          className="h-1 w-28 accent-indigo-500"
          title={`${t.zoomIn} / ${t.zoomOut}`}
        />
        <button
          onClick={() => zoomStep(10)}
          className="rounded bg-zinc-800 px-2 py-0.5 text-[10px] text-zinc-300 hover:bg-zinc-700"
          title={t.zoomIn}
        >
          ＋
        </button>
      </div>
      <div ref={containerRef} className="min-h-0 w-full flex-1" />
      <div className="pt-1 text-right font-mono text-[10px] text-zinc-500">
        {currentTime.toFixed(2)}s / {duration.toFixed(2)}s
      </div>
    </div>
  );
}
