import { create } from "zustand";
import { persist } from "zustand/middleware";
import { DEFAULT_THRESHOLDS, type QualityThresholds } from "../utils/quality";

interface SettingsState {
  // ── Persisted ─────────────────────────────────────────────────────────────
  autoCheckUpdate: boolean;
  uiScale: number; // 0.7 .. 1.3
  showTranslation: boolean; // dual original/translation editing column
  showActor: boolean; // per-cue actor/speaker column
  quality: QualityThresholds; // configurable quality-check thresholds
  recentFiles: string[]; // most-recent-first subtitle paths (max 8)
  setAutoCheckUpdate: (v: boolean) => void;
  setUiScale: (v: number) => void;
  toggleTranslation: () => void;
  toggleActor: () => void;
  setQuality: (patch: Partial<QualityThresholds>) => void;
  resetQuality: (preset: QualityThresholds) => void;
  addRecentFile: (path: string) => void;
  clearRecentFiles: () => void;

  // ── Ephemeral (not persisted) ─────────────────────────────────────────────
  // Used by VideoPlayer / any component to request the Settings modal to open.
  settingsModalOpen: boolean;
  openSettingsModal: () => void;
  closeSettingsModal: () => void;

  // Inline ASS tag editor — opened from the menu or a cue's "fx" badge.
  tagEditorOpen: boolean;
  openTagEditor: () => void;
  closeTagEditor: () => void;

  // True while any modal/overlay is open. The mpv video window is an opaque
  // native child window drawn ABOVE the web view, so it would occlude any modal
  // that overlaps the video panel. VideoPlayer hides the mpv window while this
  // is set so modals are visible.
  overlayOpen: boolean;
  setOverlayOpen: (v: boolean) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      autoCheckUpdate: true,
      uiScale: 1.0,
      showTranslation: false,
      showActor: false,
      quality: DEFAULT_THRESHOLDS,
      recentFiles: [],
      setAutoCheckUpdate: (autoCheckUpdate) => set({ autoCheckUpdate }),
      setUiScale: (uiScale) => set({ uiScale }),
      toggleTranslation: () => set((s) => ({ showTranslation: !s.showTranslation })),
      toggleActor: () => set((s) => ({ showActor: !s.showActor })),
      setQuality: (patch) => set((s) => ({ quality: { ...s.quality, ...patch } })),
      resetQuality: (preset) => set({ quality: { ...preset } }),
      addRecentFile: (path) =>
        set((s) => ({ recentFiles: [path, ...s.recentFiles.filter((p) => p !== path)].slice(0, 8) })),
      clearRecentFiles: () => set({ recentFiles: [] }),

      settingsModalOpen: false,
      openSettingsModal: () => set({ settingsModalOpen: true }),
      closeSettingsModal: () => set({ settingsModalOpen: false }),

      tagEditorOpen: false,
      openTagEditor: () => set({ tagEditorOpen: true }),
      closeTagEditor: () => set({ tagEditorOpen: false }),

      overlayOpen: false,
      setOverlayOpen: (overlayOpen) => set({ overlayOpen }),
    }),
    {
      name: "glyphline-settings",
      // Only persist these keys — ephemeral UI state is excluded.
      partialize: (s) => ({
        autoCheckUpdate: s.autoCheckUpdate,
        uiScale: s.uiScale,
        showTranslation: s.showTranslation,
        showActor: s.showActor,
        quality: s.quality,
        recentFiles: s.recentFiles,
      }),
    },
  ),
);
