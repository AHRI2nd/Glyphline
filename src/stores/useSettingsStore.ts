import { create } from "zustand";
import { persist } from "zustand/middleware";

interface SettingsState {
  autoCheckUpdate: boolean;
  uiScale: number; // 0.7 .. 1.3
  showSpectrogram: boolean;
  setAutoCheckUpdate: (v: boolean) => void;
  setUiScale: (v: number) => void;
  setShowSpectrogram: (v: boolean) => void;
  toggleSpectrogram: () => void;
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
    }),
    { name: "glyphline-settings" },
  ),
);
