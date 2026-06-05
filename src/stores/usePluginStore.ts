// Plugin registry. A plugin is a named panel that can be opened in the dock.
// "native" plugins are built-in React components; "iframe" plugins load a URL.
import { create } from "zustand";
import { persist } from "zustand/middleware";

export type PluginKind = "iframe" | "native";

export interface PluginDef {
  id: string;
  name: string;
  kind: PluginKind;
  url?: string; // iframe plugins
  nativeComponent?: string; // native plugins: component key
  description?: string;
}

// Built-in plugins shipped with the app.
export const BUILTIN_PLUGINS: PluginDef[] = [
  {
    id: "builtin-quality",
    name: "품질 검사",
    kind: "native",
    nativeComponent: "quality",
    description: "CPS / 겹침 / 표시 시간 전체 검사",
  },
  {
    id: "builtin-translate",
    name: "Google 번역",
    kind: "iframe",
    url: "https://translate.google.com",
    description: "Google Translate (iframe)",
  },
  {
    id: "builtin-deepl",
    name: "DeepL",
    kind: "iframe",
    url: "https://www.deepl.com/translator",
    description: "DeepL Translator (iframe)",
  },
];

interface PluginState {
  userPlugins: PluginDef[];
  addPlugin: (p: Omit<PluginDef, "id">) => void;
  removePlugin: (id: string) => void;
  allPlugins: () => PluginDef[];
}

export const usePluginStore = create<PluginState>()(
  persist(
    (set, get) => ({
      userPlugins: [],
      addPlugin: (p) =>
        set((s) => ({
          userPlugins: [
            ...s.userPlugins,
            { ...p, id: `user-${Date.now().toString(36)}` },
          ],
        })),
      removePlugin: (id) =>
        set((s) => ({ userPlugins: s.userPlugins.filter((p) => p.id !== id) })),
      allPlugins: () => [...BUILTIN_PLUGINS, ...get().userPlugins],
    }),
    { name: "glyphline-plugins", partialize: (s) => ({ userPlugins: s.userPlugins }) },
  ),
);
