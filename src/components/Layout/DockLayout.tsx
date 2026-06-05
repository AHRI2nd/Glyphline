import { useEffect, useState } from "react";
import { Layout, Model, TabNode, type IJsonModel } from "flexlayout-react";
import "flexlayout-react/style/dark.css";
import "./dock-theme.css"; // zinc/indigo overrides — must import AFTER dark.css
import { useI18nStore } from "../../stores/useI18nStore";
import { MediaPanel } from "../Media/MediaPanel";
import { Waveform } from "../Media/Waveform";
import { CueList } from "../CueList/CueList";

// Bump this when the panel set changes so stale saved layouts are discarded
// (an old layout missing the video/waveform panels would only show subtitles).
const STORAGE_KEY = "glyphline-layout-v2";
const REQUIRED_COMPONENTS = ["video", "waveform", "subtitles"];

// Module hook so the View ▸ Reset Layout menu item can reset from outside React.
let resetRef: (() => void) | null = null;
export function resetDockLayout() {
  resetRef?.();
}

function defaultModel(names: { video: string; waveform: string; subtitles: string }): IJsonModel {
  return {
    global: {
      tabEnableClose: false,
      tabEnableRename: false,
      tabSetEnableMaximize: true,
      tabSetMinWidth: 120,
      tabSetMinHeight: 80,
    },
    borders: [],
    layout: {
      type: "row",
      children: [
        {
          type: "column",
          weight: 45,
          children: [
            { type: "tabset", weight: 60, children: [{ type: "tab", name: names.video, component: "video" }] },
            { type: "tabset", weight: 40, children: [{ type: "tab", name: names.waveform, component: "waveform" }] },
          ],
        },
        {
          type: "tabset",
          weight: 55,
          children: [{ type: "tab", name: names.subtitles, component: "subtitles" }],
        },
      ],
    },
  };
}

function loadModel(fallback: IJsonModel): Model {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved) {
    try {
      // Only trust a saved layout that still contains every required panel,
      // otherwise a partial/stale layout could hide the video & waveform.
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

  // Wire the external reset hook.
  useEffect(() => {
    resetRef = () => {
      localStorage.removeItem(STORAGE_KEY);
      setModel(Model.fromJson(defaultModel(names)));
    };
    return () => {
      resetRef = null;
    };
  }, [t]);

  const factory = (node: TabNode) => {
    switch (node.getComponent()) {
      case "video":
        return <MediaPanel />;
      case "waveform":
        return <Waveform />;
      case "subtitles":
        return <CueList />;
      default:
        return null;
    }
  };

  return (
    <div className="relative min-h-0 flex-1">
      <Layout
        model={model}
        factory={factory}
        realtimeResize
        onModelChange={(m) => localStorage.setItem(STORAGE_KEY, JSON.stringify(m.toJson()))}
      />
    </div>
  );
}
