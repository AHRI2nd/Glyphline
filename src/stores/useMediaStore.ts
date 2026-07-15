import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export const PLAYBACK_RATES = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

export const VIDEO_EXTS = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ts", "flv", "wmv", "m2ts"];
export const AUDIO_EXTS = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff", "aif"];
export const MEDIA_EXTS = [...VIDEO_EXTS, ...AUDIO_EXTS];

export type MediaKind = "video" | "audio";

function kindFromPath(path: string): MediaKind {
  const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
  return AUDIO_EXTS.includes(ext) ? "audio" : "video";
}
function baseName(path: string): string {
  return path.split(/[\\/]/).pop() ?? path;
}

// ─── Stubs — kept for Waveform compatibility ─────────────────────────────────
let _videoEl: HTMLVideoElement | null = null;
export function bindVideoEl(el: HTMLVideoElement | null) { _videoEl = el; }
export function getVideoEl(): HTMLVideoElement | null { return _videoEl; }

/** Build a media:// URL for Wavesurfer to load audio from any local path. */
export function toMediaUrl(absolutePath: string): string {
  return `media://localhost/?path=${encodeURIComponent(absolutePath)}`;
}

interface MediaState {
  mediaPath: string | null;
  /** media:// URL for the current file. */
  mediaSrc: string | null;
  /**
   * media:// URL of a small downsampled WAV (extracted by mpv) for Wavesurfer.
   * Decoding the original multi-hundred-MB file via WebAudio is impractical, so
   * the backend produces a mono 8 kHz WAV first. null until extraction finishes.
   */
  waveformSrc: string | null;
  /** Incremented when mediaSrc changes so Waveform can re-init. */
  elGeneration: number;
  mediaKind: MediaKind | null;
  mediaName: string | null;
  duration: number;
  currentTime: number;
  isPlaying: boolean;
  playbackRate: number;
  volume: number; // 0–100 (mpv scale, 100 = original)
  muted: boolean;
  /** When set, playback loops within [start, end) — used to repeat the active cue. */
  loopRegion: { start: number; end: number } | null;
  error: string | null;

  loadMedia: (path: string) => Promise<void>;
  closeMedia: () => void;
  setCurrentTime: (t: number) => void;
  togglePlay: () => void;
  seek: (sec: number) => void;
  skip: (delta: number) => void;
  frameStep: (forward: boolean) => void;
  setPlaybackRate: (r: number) => void;
  setVolume: (v: number) => void;
  toggleMute: () => void;
  /** Loop playback over [start, end): seek to start, unpause, and remember the region. */
  playRegion: (start: number, end: number) => void;
  clearLoop: () => void;
}

export const useMediaStore = create<MediaState>((set, get) => ({
  mediaPath: null,
  mediaSrc: null,
  waveformSrc: null,
  elGeneration: 0,
  mediaKind: null,
  mediaName: null,
  duration: 0,
  currentTime: 0,
  isPlaying: false,
  playbackRate: 1,
  volume: 100,
  muted: false,
  loopRegion: null,
  error: null,

  loadMedia: async (path) => {
    const src = toMediaUrl(path);
    set((s) => ({
      mediaPath: path,
      mediaSrc: src,
      waveformSrc: null, // cleared until the downsampled WAV is ready
      elGeneration: s.elGeneration + 1,
      mediaKind: kindFromPath(path),
      mediaName: baseName(path),
      currentTime: 0, duration: 0, isPlaying: false, error: null,
    }));
    try {
      await invoke("mpv_open", { path });
    } catch (e) {
      set({ error: String(e) });
    }
    // Extract a small WAV for the waveform in the background (doesn't block playback).
    invoke<string>("extract_waveform_audio", { path })
      .then((wavPath) => {
        // Ignore if the user already switched to another file.
        if (get().mediaPath === path) set({ waveformSrc: toMediaUrl(wavPath) });
      })
      .catch((e) => console.warn("[waveform]", e));
  },

  closeMedia: () => {
    invoke("mpv_stop").catch(() => {});
    set({
      mediaPath: null, mediaSrc: null, waveformSrc: null, mediaKind: null, mediaName: null,
      currentTime: 0, duration: 0, isPlaying: false, loopRegion: null, error: null,
    });
  },

  setCurrentTime: (currentTime) => set({ currentTime }),

  togglePlay: () => {
    invoke("mpv_play_pause").catch((e) => console.warn("[mpv]", e));
  },

  seek: (sec) => {
    const clamped = Math.max(0, Math.min(sec, get().duration || sec));
    invoke("mpv_seek", { pos: clamped }).catch((e) => console.warn("[mpv]", e));
  },

  skip: (delta) => {
    // A manual skip cancels any active loop so it doesn't yank you back.
    set({ loopRegion: null });
    invoke("mpv_skip", { delta }).catch((e) => console.warn("[mpv]", e));
  },

  frameStep: (forward) => {
    set({ loopRegion: null });
    invoke("mpv_frame_step", { forward }).catch((e) => console.warn("[mpv]", e));
  },

  setPlaybackRate: (speed) => {
    invoke("mpv_set_speed", { speed })
      .then(() => set({ playbackRate: speed }))
      .catch((e) => console.warn("[mpv]", e));
  },

  setVolume: (v) => {
    const volume = Math.max(0, Math.min(130, v));
    // Adjusting volume implicitly unmutes (matches every media player).
    set({ volume, muted: false });
    invoke("mpv_set_volume", { volume }).catch((e) => console.warn("[mpv]", e));
    invoke("mpv_set_mute", { mute: false }).catch(() => {});
  },

  toggleMute: () => {
    const muted = !get().muted;
    set({ muted });
    invoke("mpv_set_mute", { mute: muted }).catch((e) => console.warn("[mpv]", e));
  },

  playRegion: (start, end) => {
    set({ loopRegion: { start, end } });
    invoke("mpv_seek", { pos: Math.max(0, start) }).catch(() => {});
    invoke("mpv_set_pause", { pause: false }).catch(() => {});
  },

  clearLoop: () => set({ loopRegion: null }),
}));

// ─── Subscribe to mpv events from Rust ───────────────────────────────────────
// Called once from main.tsx after the store is created.
export function initMpvListeners() {
  listen<number>("mpv-time-pos", (e) => {
    const t = e.payload;
    useMediaStore.setState({ currentTime: t });
    // Loop playback: when the region end is reached, jump back to its start.
    // (The 80 ms poll granularity means we overshoot by <80 ms — fine for review.)
    const loop = useMediaStore.getState().loopRegion;
    if (loop && t >= loop.end) {
      invoke("mpv_seek", { pos: loop.start }).catch(() => {});
    }
  });
  listen<number>("mpv-duration", (e) => {
    if (e.payload > 0) useMediaStore.setState({ duration: e.payload });
  });
  listen<boolean>("mpv-paused", (e) => {
    useMediaStore.setState({ isPlaying: !e.payload });
  });
}
