import { create } from "zustand";
import { persist } from "zustand/middleware";

interface SettingsState {
  // ── Persisted ─────────────────────────────────────────────────────────────
  autoCheckUpdate: boolean;
  uiScale: number; // 0.7 .. 1.3
  showSpectrogram: boolean;
  setAutoCheckUpdate: (v: boolean) => void;
  setUiScale: (v: number) => void;
  setShowSpectrogram: (v: boolean) => void;
  toggleSpectrogram: () => void;

  // ── Ephemeral (not persisted) ─────────────────────────────────────────────
  // Used by VideoPlayer / any component to request the Settings modal to open.
  settingsModalOpen: boolean;
  openSettingsModal: () => void;
  closeSettingsModal: () => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      autoCheckUpdate: true,
      uiScale: 1.0,
      showSpectrogram: false,
      setAutoCheckUpdate: (autoCheckUpdate) => set({ autoCheckUpdate }),
      setUiScale: (uiScale) => set({ uiScale }),
      setShowSpectrogram: (showSpectrogram) => set({ showSpectrogram }),
      toggleSpectrogram: () => set((s) => ({ showSpectrogram: !s.showSpectrogram })),

      settingsModalOpen: false,
      openSettingsModal: () => set({ settingsModalOpen: true }),
      closeSettingsModal: () => set({ settingsModalOpen: false }),
    }),
    {
      name: "glyphline-settings",
      // Only persist these keys — ephemeral UI state is excluded.
      partialize: (s) => ({
        autoCheckUpdate: s.autoCheckUpdate,
        uiScale: s.uiScale,
        showSpectrogram: s.showSpectrogram,
      }),
    },
  ),
);
