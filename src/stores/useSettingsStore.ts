import { create } from "zustand";
import { persist } from "zustand/middleware";

interface SettingsState {
  // ── Persisted ─────────────────────────────────────────────────────────────
  autoCheckUpdate: boolean;
  uiScale: number; // 0.7 .. 1.3
  showTranslation: boolean; // dual original/translation editing column
  setAutoCheckUpdate: (v: boolean) => void;
  setUiScale: (v: number) => void;
  toggleTranslation: () => void;

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
      setAutoCheckUpdate: (autoCheckUpdate) => set({ autoCheckUpdate }),
      setUiScale: (uiScale) => set({ uiScale }),
      toggleTranslation: () => set((s) => ({ showTranslation: !s.showTranslation })),

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
      }),
    },
  ),
);
