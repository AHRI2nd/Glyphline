import { useEffect, useRef, useState } from "react";
import { Layout, Model, TabNode, Actions, DockLocation, type IJsonModel } from "flexlayout-react";
import "flexlayout-react/style/dark.css";
import "./dock-theme.css"; // zinc/indigo overrides — must import AFTER dark.css
import { Globe } from "lucide-react";
import { useI18nStore } from "../../stores/useI18nStore";
import { MediaPanel } from "../Media/MediaPanel";
import { Waveform } from "../Media/Waveform";
import { CueList } from "../CueList/CueList";
import { QualityPanel } from "../Plugins/QualityPanel";
import { usePluginStore, type PluginDef } from "../../stores/usePluginStore";

const STORAGE_KEY = "glyphline-layout-v2";
const REQUIRED_COMPONENTS = ["video", "waveform", "subtitles"];

// Module hook so View ▸ Reset Layout can reset from outside React.
let resetRef: (() => void) | null = null;
export function resetDockLayout() {
  resetRef?.();
}

// Module hook so App can open a plugin panel from outside React.
let openPluginRef: ((plugin: PluginDef) => void) | null = null;
export function openPluginPanel(plugin: PluginDef) {
  openPluginRef?.(plugin);
}

function defaultModel(names: {
  video: string;
  waveform: string;
  subtitles: string;
}): IJsonModel {
  return {
    global: {
      tabEnableClose: true,
      tabEnableRename: false,
      tabSetEnableMaximize: true,
      tabSetMinWidth: 120,
      tabSetMinHeight: 60,
    },
    borders: [],
    layout: {
      // NOTE: flexlayout has NO "column" type — a nested "row" auto-switches to
      // the perpendicular (vertical) orientation, so video+waveform stack.
      type: "row",
      children: [
        {
          type: "row",
          weight: 42,
          children: [
            {
              type: "tabset",
              weight: 60,
              children: [{ type: "tab", name: names.video, component: "video", enableClose: false }],
            },
            {
              type: "tabset",
              weight: 40,
              children: [{ type: "tab", name: names.waveform, component: "waveform", enableClose: false }],
            },
          ],
        },
        {
          type: "tabset",
          weight: 58,
          children: [{ type: "tab", name: names.subtitles, component: "subtitles", enableClose: false }],
        },
      ],
    },
  };
}

function loadModel(fallback: IJsonModel): Model {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved) {
    try {
      const hasAll = REQUIRED_COMPONENTS.every((c) => saved.includes(`"${c}"`));
      if (hasAll) return Model.fromJson(JSON.parse(saved));
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      localStorage.removeItem(STORAGE_KEY);
    }
  }
  return Model.fromJson(fallback);
}

export function DockLayout() {
  const { t } = useI18nStore();
  const names = { video: t.panelVideo, waveform: t.panelWaveform, subtitles: t.panelSubtitles };
  const [model, setModel] = useState<Model>(() => loadModel(defaultModel(names)));
  const modelRef = useRef(model);
  modelRef.current = model;

  // ── Reset hook ────────────────────────────────────────────────────────────────
  useEffect(() => {
    resetRef = () => {
      localStorage.removeItem(STORAGE_KEY);
      setModel(Model.fromJson(defaultModel(names)));
    };
    return () => { resetRef = null; };
  }, [t]);

  // ── Plugin open hook ──────────────────────────────────────────────────────────
  useEffect(() => {
    openPluginRef = (plugin: PluginDef) => {
      const m = modelRef.current;
      // If a tab with this plugin id already exists, just activate it.
      let found = false;
      m.visitNodes((node) => {
        if (node instanceof TabNode && node.getId() === plugin.id) {
          m.doAction(Actions.selectTab(plugin.id));
          found = true;
        }
      });
      if (found) return;

      // Add a new tab next to the subtitles tabset (or first tabset found).
      let targetTabset: string | null = null;
      m.visitNodes((node) => {
        if (!targetTabset && node.getType() === "tabset") {
          targetTabset = node.getId();
        }
      });
      if (targetTabset) {
        m.doAction(
          Actions.addNode(
            { type: "tab", id: plugin.id, name: plugin.name, component: `plugin:${plugin.id}` },
            targetTabset,
            DockLocation.CENTER,
            -1,
          ),
        );
      }
    };
    return () => { openPluginRef = null; };
  }, []);

  // ── Factory ───────────────────────────────────────────────────────────────────
  const factory = (node: TabNode) => {
    const comp = node.getComponent() ?? "";
    switch (comp) {
      case "video":    return <MediaPanel />;
      case "waveform": return <Waveform />;
      case "subtitles": return <CueList />;
      case "quality":  return <QualityPanel />;
    }
    // plugin:id → look up the plugin definition
    if (comp.startsWith("plugin:")) {
      const id = comp.slice(7);
      const plugin = usePluginStore.getState().allPlugins().find((p) => p.id === id);
      if (plugin?.kind === "iframe" && plugin.url) {
        return (
          <div className="flex h-full w-full flex-col bg-zinc-950">
            <div className="flex shrink-0 items-center gap-1 border-b border-zinc-800 px-3 py-1.5">
              <Globe size={12} className="text-zinc-500" />
              <span className="truncate text-xs text-zinc-500">{plugin.url}</span>
            </div>
            <iframe
              src={plugin.url}
              className="h-full w-full flex-1 border-0"
              sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
              title={plugin.name}
            />
          </div>
        );
      }
      if (plugin?.kind === "native" && plugin.nativeComponent === "quality") {
        return <QualityPanel />;
      }
    }
    return (
      <div className="flex h-full items-center justify-center text-xs text-zinc-600">
        알 수 없는 패널: {comp}
      </div>
    );
  };

  return (
    // flexlayout requires a container with explicit width+height via
    // position:relative + absolute children. flex-1 gives height but NOT width
    // in a flex-col context → must add w-full explicitly.
    <div className="relative min-h-0 w-full flex-1">
      <div className="absolute inset-0">
        <Layout
          model={model}
          factory={factory}
          realtimeResize
          onModelChange={(m) => {
            modelRef.current = m;
            localStorage.setItem(STORAGE_KEY, JSON.stringify(m.toJson()));
          }}
        />
      </div>
    </div>
  );
}
