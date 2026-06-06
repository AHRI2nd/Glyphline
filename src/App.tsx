import { useEffect, useRef, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { useI18nStore } from "./stores/useI18nStore";
import { useSettingsStore } from "./stores/useSettingsStore";
import { useSubtitleStore } from "./stores/useSubtitleStore";
import { useMediaStore, MEDIA_EXTS } from "./stores/useMediaStore";
import { adapterForFormat, openExtensions } from "./formats";
import { NATIVE_EXT, type SubFormat } from "./types/subtitle";
import { checkForUpdate } from "./utils/updateCheck";
import { installAppMenu, type MenuHandlers } from "./menu/appMenu";
import { Toolbar } from "./components/Toolbar/Toolbar";
import { DockLayout, resetDockLayout, openPluginPanel } from "./components/Layout/DockLayout";
import { PluginManagerModal } from "./components/Plugins/PluginManagerModal";
import { ConfirmModal, Backdrop } from "./components/Modals/ConfirmModal";
import { ExportWarningModal } from "./components/Modals/ExportWarningModal";
import { smiExportLoss } from "./formats/smi";
import type { LossCategory } from "./formats/assTags";
import { RawEditorModal } from "./components/Modals/RawEditorModal";
import { HelpModal } from "./components/Modals/HelpModal";
import { SettingsModal } from "./components/Settings/SettingsModal";
import { StyleManagerModal } from "./components/Settings/StyleManagerModal";
import { InlineTagEditorModal } from "./components/Modals/InlineTagEditorModal";

export default function App() {
  const { t, lang } = useI18nStore();
  const { uiScale } = useSettingsStore();
  const autoCheckUpdate = useSettingsStore((s) => s.autoCheckUpdate);

  const [showHelp, setShowHelp] = useState(false);
  const showSettings = useSettingsStore((s) => s.settingsModalOpen);
  const setShowSettings = useSettingsStore((s) => s.closeSettingsModal);
  const [showNewConfirm, setShowNewConfirm] = useState(false);
  const [showRawEditor, setShowRawEditor] = useState(false);
  const [showShift, setShowShift] = useState(false);
  const [showStyles, setShowStyles] = useState(false);
  const [showTagEditor, setShowTagEditor] = useState(false);
  const [showPluginManager, setShowPluginManager] = useState(false);
  const [pendingExport, setPendingExport] = useState<{ format: SubFormat; categories: LossCategory[] } | null>(null);
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);

  // ─── File actions ───────────────────────────────────────────────────────────
  const doOpen = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "Subtitles", extensions: openExtensions() }],
    });
    if (typeof selected === "string") {
      try {
        await useSubtitleStore.getState().openPath(selected);
      } catch (e) {
        alert((e as Error).message);
      }
    }
  };

  const doSaveNative = async () => {
    const base = (useSubtitleStore.getState().fileName ?? "untitled").replace(/\.[^.]+$/, "");
    const path = await save({
      defaultPath: `${base}.${NATIVE_EXT}`,
      filters: [{ name: "Glyphline Project", extensions: [NATIVE_EXT] }],
    });
    if (path) await useSubtitleStore.getState().saveNativePath(path);
  };

  // Run the file dialog + write. Assumes any loss was already confirmed.
  const performExport = (format: SubFormat) => {
    void (async () => {
      const adapter = adapterForFormat(format);
      const base = (useSubtitleStore.getState().fileName ?? "untitled").replace(/\.[^.]+$/, "");
      const path = await save({
        defaultPath: `${base}.${adapter.extensions[0]}`,
        filters: [{ name: adapter.label, extensions: adapter.extensions }],
      });
      if (path) await useSubtitleStore.getState().exportPath(path, format);
    })();
  };

  const doExport = (format: SubFormat) => {
    // Warn before a lossy ASS->SMI export when override tags would be dropped.
    const loss = format === "smi" ? smiExportLoss(useSubtitleStore.getState().doc) : [];
    if (loss.length) {
      setPendingExport({ format, categories: loss });
      return;
    }
    performExport(format);
  };

  const doNew = () => {
    setShowNewConfirm(false);
    useSubtitleStore.getState().newDocument();
  };

  const doSplit = () => {
    const s = useSubtitleStore.getState();
    const id = s.activeCueId;
    const cue = id ? s.doc.cues.find((c) => c.id === id) : null;
    // Prefer the video playhead as the split point when it falls inside the cue.
    if (id && cue) {
      const t = useMediaStore.getState().currentTime;
      const at = t > cue.start && t < cue.end ? t : (cue.start + cue.end) / 2;
      s.splitCue(id, at);
    }
  };

  const doOpenMedia = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "Media", extensions: MEDIA_EXTS }],
    });
    if (typeof selected === "string") await useMediaStore.getState().loadMedia(selected);
  };

  // ─── Native macOS menu bar ────────────────────────────────────────────────────
  // Handlers go through a ref so menu actions always see the latest closures.
  const handlersRef = useRef<MenuHandlers>(null!);
  handlersRef.current = {
    onNew: () => setShowNewConfirm(true),
    onOpen: () => void doOpen(),
    onOpenMedia: () => void doOpenMedia(),
    onCloseMedia: () => useMediaStore.getState().closeMedia(),
    onSave: () => void doSaveNative(),
    onExport: doExport,
    onTogglePlay: () => useMediaStore.getState().togglePlay(),
    onSkip: (d) => useMediaStore.getState().skip(d),
    onUndo: () => useSubtitleStore.getState().undo(),
    onRedo: () => useSubtitleStore.getState().redo(),
    onAddCue: () => useSubtitleStore.getState().addCue(),
    onSplit: doSplit,
    onMerge: () => {
      const s = useSubtitleStore.getState();
      s.mergeCues([...s.selectedIds]);
    },
    onDelete: () => {
      const s = useSubtitleStore.getState();
      s.deleteCues([...s.selectedIds]);
    },
    onShift: () => setShowShift(true),
    onStyles: () => setShowStyles(true),
    onEditTags: () => setShowTagEditor(true),
    onRawEdit: () => setShowRawEditor(true),
    onSettings: () => useSettingsStore.getState().openSettingsModal(),
    onHelp: () => setShowHelp(true),
    onResetLayout: () => resetDockLayout(),
    onToggleSpectrogram: () => useSettingsStore.getState().toggleSpectrogram(),
    onPlugins: () => setShowPluginManager(true),
    onSetLang: (l) => useI18nStore.getState().setLang(l),
  };

  // Rebuild on language change so labels + the language checkmarks stay in sync.
  useEffect(() => {
    // Indirect through the ref so each rebuild captures live handlers.
    const stable: MenuHandlers = {
      onNew: () => handlersRef.current.onNew(),
      onOpen: () => handlersRef.current.onOpen(),
      onOpenMedia: () => handlersRef.current.onOpenMedia(),
      onCloseMedia: () => handlersRef.current.onCloseMedia(),
      onSave: () => handlersRef.current.onSave(),
      onExport: (f) => handlersRef.current.onExport(f),
      onTogglePlay: () => handlersRef.current.onTogglePlay(),
      onSkip: (d) => handlersRef.current.onSkip(d),
      onUndo: () => handlersRef.current.onUndo(),
      onRedo: () => handlersRef.current.onRedo(),
      onAddCue: () => handlersRef.current.onAddCue(),
      onSplit: () => handlersRef.current.onSplit(),
      onMerge: () => handlersRef.current.onMerge(),
      onDelete: () => handlersRef.current.onDelete(),
      onShift: () => handlersRef.current.onShift(),
      onStyles: () => handlersRef.current.onStyles(),
      onEditTags: () => handlersRef.current.onEditTags(),
      onRawEdit: () => handlersRef.current.onRawEdit(),
      onSettings: () => handlersRef.current.onSettings(), // handled via store
      onHelp: () => handlersRef.current.onHelp(),
      onResetLayout: () => handlersRef.current.onResetLayout(),
      onToggleSpectrogram: () => handlersRef.current.onToggleSpectrogram(),
      onPlugins: () => handlersRef.current.onPlugins(),
      onSetLang: (l) => handlersRef.current.onSetLang(l),
    };
    installAppMenu(t, lang, stable).catch((e) => console.error("menu install failed", e));
  }, [lang, t]);

  // ─── Update check on launch ───────────────────────────────────────────────────
  useEffect(() => {
    if (!autoCheckUpdate) return;
    checkForUpdate()
      .then((v) => v && setUpdateVersion(v))
      .catch(() => {});
  }, [autoCheckUpdate]);

  return (
    <div
      style={{
        transform: `scale(${uiScale})`,
        transformOrigin: "top left",
        width: `${(100 / uiScale).toFixed(4)}vw`,
        height: `${(100 / uiScale).toFixed(4)}vh`,
      }}
      className="flex flex-col overflow-hidden bg-zinc-950 text-white"
    >
      <Toolbar
        onAddCue={() => useSubtitleStore.getState().addCue()}
        onMerge={() => {
          const s = useSubtitleStore.getState();
          s.mergeCues([...s.selectedIds]);
        }}
        onDelete={() => {
          const s = useSubtitleStore.getState();
          s.deleteCues([...s.selectedIds]);
        }}
      />

      <main className="flex min-h-0 flex-1 flex-col">
        <DockLayout />
      </main>

      {updateVersion && (
        <div className="fixed bottom-3 right-3 rounded bg-indigo-600 px-3 py-2 text-xs text-white shadow">
          {t.updateAvailable}: {updateVersion}
          <button className="ml-2 underline" onClick={() => setUpdateVersion(null)}>
            ✕
          </button>
        </div>
      )}

      {/* modals (triggered from the native menu / toolbar) */}
      {showHelp && <HelpModal onClose={() => setShowHelp(false)} />}
      {showSettings && <SettingsModal onClose={setShowSettings} />}
      {showNewConfirm && (
        <ConfirmModal message={t.newFileConfirm} onConfirm={doNew} onCancel={() => setShowNewConfirm(false)} />
      )}
      {showRawEditor && (
        <RawEditorModal
          initialValue={useSubtitleStore.getState().serializeCurrent()}
          onApply={(raw) => {
            useSubtitleStore.getState().loadFromRaw(raw, useSubtitleStore.getState().doc.format);
            setShowRawEditor(false);
          }}
          onClose={() => setShowRawEditor(false)}
        />
      )}
      {showShift && <ShiftModal onClose={() => setShowShift(false)} />}
      {showStyles && <StyleManagerModal onClose={() => setShowStyles(false)} />}
      {showTagEditor && <InlineTagEditorModal onClose={() => setShowTagEditor(false)} />}
      {showPluginManager && (
        <PluginManagerModal
          onOpen={(plugin) => openPluginPanel(plugin)}
          onClose={() => setShowPluginManager(false)}
        />
      )}
      {pendingExport && (
        <ExportWarningModal
          categories={pendingExport.categories}
          onConfirm={() => {
            const fmt = pendingExport.format;
            setPendingExport(null);
            performExport(fmt);
          }}
          onCancel={() => setPendingExport(null)}
        />
      )}
    </div>
  );
}

function ShiftModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const shiftTime = useSubtitleStore((s) => s.shiftTime);
  const hasSelection = useSubtitleStore((s) => s.selectedIds.size > 0);
  const [seconds, setSeconds] = useState("0");

  const apply = (scope: "all" | "selected") => {
    const delta = Number(seconds);
    if (!Number.isNaN(delta) && delta !== 0) shiftTime(delta, scope);
    onClose();
  };

  return (
    <Backdrop onClick={onClose}>
      <div className="w-[360px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="mb-3 text-sm font-semibold text-zinc-100">{t.shiftTime}</h3>
        <p className="mb-2 text-xs text-zinc-500">{t.shiftPrompt}</p>
        <input
          type="number"
          step="0.1"
          value={seconds}
          autoFocus
          onChange={(e) => setSeconds(e.target.value)}
          className="mb-4 w-full rounded border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-sm text-zinc-100 outline-none focus:border-indigo-500"
        />
        <div className="flex justify-end gap-2">
          <button className="rounded px-3 py-1.5 text-sm text-zinc-300 hover:bg-zinc-800" onClick={onClose}>
            {t.cancel}
          </button>
          {hasSelection && (
            <button
              className="rounded bg-zinc-700 px-3 py-1.5 text-sm text-white hover:bg-zinc-600"
              onClick={() => apply("selected")}
            >
              {t.shiftSelected}
            </button>
          )}
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={() => apply("all")}
          >
            {t.shiftAll}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
