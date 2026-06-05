import { create } from "zustand";
import { convertFileSrc } from "@tauri-apps/api/core";

// The single <video> element is the source of truth for playback (it plays both
// video AND audio-only files; Wavesurfer binds to it too). VideoPlayer registers
// it here on mount; controls and the waveform read it through these accessors.
let videoEl: HTMLVideoElement | null = null;
export function bindVideoEl(el: HTMLVideoElement | null) {
  videoEl = el;
  // Bump a generation counter so the waveform re-binds when the element changes.
  // This matters in the dockable layout: dragging the Video panel remounts the
  // <video>, and the waveform's WaveSurfer instance must follow the new element.
  useMediaStore.setState((s) => ({ elGeneration: s.elGeneration + 1 }));
}
export function getVideoEl(): HTMLVideoElement | null {
  return videoEl;
}

export const PLAYBACK_RATES = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

// Extensions offered in the Open Media dialog. Note: selectable ≠ guaranteed to
// play — macOS WKWebView decodes MP4/MOV/M4V (H.264/HEVC+AAC) and common audio
// codecs reliably; MKV/AVI/TS/WebM may not play even though listed.
export const VIDEO_EXTS = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ts"];
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

interface MediaState {
  mediaPath: string | null;
  mediaSrc: string | null; // asset-protocol URL for streaming (not an in-memory blob)
  mediaKind: MediaKind | null;
  mediaName: string | null;
  duration: number;
  currentTime: number;
  isPlaying: boolean;
  playbackRate: number;
  elGeneration: number; // bumped whenever the <video> element is (re)bound

  loadMedia: (path: string) => void;
  closeMedia: () => void;
  setDuration: (d: number) => void;
  setCurrentTime: (t: number) => void;
  setPlaying: (p: boolean) => void;

  // controls (operate on the bound <video> element)
  togglePlay: () => void;
  seek: (sec: number) => void;
  skip: (delta: number) => void;
  setPlaybackRate: (r: number) => void;
}

export const useMediaStore = create<MediaState>((set, get) => ({
  mediaPath: null,
  mediaSrc: null,
  mediaKind: null,
  mediaName: null,
  duration: 0,
  currentTime: 0,
  isPlaying: false,
  playbackRate: 1,
  elGeneration: 0,

  loadMedia: (path) =>
    set({
      mediaPath: path,
      mediaSrc: convertFileSrc(path),
      mediaKind: kindFromPath(path),
      mediaName: baseName(path),
      currentTime: 0,
      duration: 0,
      isPlaying: false,
    }),
  closeMedia: () => {
    if (videoEl) videoEl.pause();
    set({ mediaPath: null, mediaSrc: null, mediaKind: null, mediaName: null, currentTime: 0, duration: 0, isPlaying: false });
  },

  setDuration: (duration) => set({ duration }),
  setCurrentTime: (currentTime) => set({ currentTime }),
  setPlaying: (isPlaying) => set({ isPlaying }),

  togglePlay: () => {
    if (!videoEl) return;
    if (videoEl.paused) void videoEl.play();
    else videoEl.pause();
  },
  seek: (sec) => {
    if (videoEl) videoEl.currentTime = Math.max(0, Math.min(sec, get().duration || sec));
  },
  skip: (delta) => {
    if (videoEl) videoEl.currentTime = Math.max(0, videoEl.currentTime + delta);
  },
  setPlaybackRate: (r) => {
    if (videoEl) videoEl.playbackRate = r;
    set({ playbackRate: r });
  },
}));
