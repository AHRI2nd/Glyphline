import { create } from "zustand";
import { persist } from "zustand/middleware";
import { type Lang, translations, type Translations } from "../i18n/translations";

interface I18nState {
  lang: Lang;
  setLang: (lang: Lang) => void;
  t: Translations;
}

// Lesson from Lyrical Sync: persist ONLY `lang` and recompute `t` on rehydrate.
// Persisting the whole `t` object would surface `undefined` for keys added in a
// newer build but missing from an older cached blob.
export const useI18nStore = create<I18nState>()(
  persist(
    (set) => ({
      lang: "ko",
      t: translations.ko,
      setLang: (lang) => set({ lang, t: translations[lang] }),
    }),
    {
      name: "glyphline-lang",
      partialize: (state) => ({ lang: state.lang }),
      onRehydrateStorage: () => (state) => {
        if (state) state.t = translations[state.lang];
      },
    },
  ),
);
