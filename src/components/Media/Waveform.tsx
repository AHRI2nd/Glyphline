import { useEffect, useMemo, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import RegionsPlugin, { type Region } from "wavesurfer.js/dist/plugins/regions.esm.js";
import SpectrogramPlugin from "wavesurfer.js/dist/plugins/spectrogram.esm.js";
import { useMediaStore } from "../../stores/useMediaStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { useI18nStore } from "../../stores/useI18nStore";

const NORMAL_COLOR = "rgba(99,102,241,0.18)";
const ACTIVE_COLOR = "rgba(99,102,241,0.38)";

// Waveform driven by the media:// URL (independent audio decoder).
// mpv handles actual playback — we keep WaveSurfer muted and sync its cursor
// via mpv's time-pos events so the two stay in lockstep.
export function Waveform() {
  const containerRef = useRef<HTMLDivElement>(null);
  const specContainerRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WaveSurfer | null>(null);
  const regionsRef = useRef<RegionsPlugin | null>(null);
  const specRef = useRef<SpectrogramPlugin | null>(null);
  const buildingRef = useRef(false); // suppress region-created during programmatic adds
  const [ready, setReady] = useState(false);
  const showSpectrogram = useSettingsStore((s) => s.showSpectrogram);
  const toggleSpectrogram = useSettingsStore((s) => s.toggleSpectrogram);

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
      height: 80,
      waveColor: "#52525b",
      progressColor: "#6366f1",
      cursorColor: "#f43f5e",
      normalize: true,
    });
    const regions = ws.registerPlugin(RegionsPlugin.create());
    wsRef.current = ws;
    regionsRef.current = regions;

    // Mute WaveSurfer's internal decoder — mpv provides all audio.
    ws.setVolume(0);

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
      specRef.current = null;
      setReady(false);
    };
  }, [waveformSrc]);

  // ── keep WaveSurfer cursor in sync with mpv ───────────────────────────────
  // currentTime updates every ~80 ms from Rust's mpv poll thread.
  // ws.setTime() repositions the internal media element (no audio playback
  // since volume=0) and redraws the cursor — lightweight enough for 80 ms ticks.
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws || !ready) return;
    ws.setTime(currentTime);
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

  // ── spectrogram (optional, lazily attached) ───────────────────────────────────
  useEffect(() => {
    const ws = wsRef.current;
    if (!ws || !ready) return;
    if (showSpectrogram && !specRef.current && specContainerRef.current) {
      specRef.current = ws.registerPlugin(
        SpectrogramPlugin.create({
          container: specContainerRef.current,
          height: 160,
          labels: true,
          scale: "mel",
          labelsBackground: "rgba(0,0,0,0.6)",
        }),
      );
    } else if (!showSpectrogram && specRef.current) {
      specRef.current.destroy();
      specRef.current = null;
    }
  }, [showSpectrogram, ready]);

  if (!mediaSrc) {
    return (
      <div className="flex h-full w-full items-center justify-center bg-zinc-900 text-xs text-zinc-600">
        {t.noMedia}
      </div>
    );
  }

  return (
    <div className="flex h-full w-full flex-col overflow-auto bg-zinc-900 px-2 py-2">
      <div className="mb-1 flex items-center justify-end">
        <button
          onClick={() => toggleSpectrogram()}
          className={`rounded px-2 py-0.5 text-[10px] ${
            showSpectrogram ? "bg-indigo-600 text-white" : "bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
          }`}
          title={t.spectrogram}
        >
          ▦ {t.spectrogram}
        </button>
      </div>
      <div ref={containerRef} className="w-full" />
      {showSpectrogram && <div ref={specContainerRef} className="mt-1 w-full" />}
      <div className="mt-auto pt-1 text-right font-mono text-[10px] text-zinc-500">
        {currentTime.toFixed(2)}s / {duration.toFixed(2)}s
      </div>
    </div>
  );
}
