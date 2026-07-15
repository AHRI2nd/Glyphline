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
import { EmbeddedAssetsModal } from "./components/Settings/EmbeddedAssetsModal";
import { InlineTagEditorModal } from "./components/Modals/InlineTagEditorModal";
import { FindReplaceModal } from "./components/Modals/FindReplaceModal";
import { BatchCleanupModal } from "./components/Modals/BatchCleanupModal";
import { PointSyncModal } from "./components/Modals/PointSyncModal";
import { ChangeSpeedModal } from "./components/Modals/ChangeSpeedModal";
import { StatisticsModal } from "./components/Modals/StatisticsModal";
import { CloseConfirmModal, RecoveryModal } from "./components/Modals/SafetyModals";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { serializeGlyph, parseGlyph } from "./formats/glyph";

/** Crash-recovery autosave payload (JSON, written to the OS temp dir). */
interface AutosaveData {
  savedAt: number;
  filePath: string | null;
  fileName: string | null;
  glyph: string;
}

export default function App() {
  const { t, lang } = useI18nStore();
  const { uiScale } = useSettingsStore();
  const autoCheckUpdate = useSettingsStore((s) => s.autoCheckUpdate);
  const recentFiles = useSettingsStore((s) => s.recentFiles);
  const recentKey = recentFiles.join("|");

  const [showHelp, setShowHelp] = useState(false);
  const showSettings = useSettingsStore((s) => s.settingsModalOpen);
  const setShowSettings = useSettingsStore((s) => s.closeSettingsModal);
  const [showNewConfirm, setShowNewConfirm] = useState(false);
  const [showRawEditor, setShowRawEditor] = useState(false);
  const [showShift, setShowShift] = useState(false);
  const [showFindReplace, setShowFindReplace] = useState(false);
  const [showBatchCleanup, setShowBatchCleanup] = useState(false);
  const [showPointSync, setShowPointSync] = useState(false);
  const [showChangeSpeed, setShowChangeSpeed] = useState(false);
  const [showStatistics, setShowStatistics] = useState(false);
  const [showStyles, setShowStyles] = useState(false);
  const [showEmbedded, setShowEmbedded] = useState(false);
  const showTagEditor = useSettingsStore((s) => s.tagEditorOpen);
  const closeTagEditor = useSettingsStore((s) => s.closeTagEditor);
  const [showPluginManager, setShowPluginManager] = useState(false);
  const [pendingExport, setPendingExport] = useState<{ format: SubFormat; categories: LossCategory[]; encoding?: string } | null>(null);
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);
  const [showCloseConfirm, setShowCloseConfirm] = useState(false);
  const [recovery, setRecovery] = useState<AutosaveData | null>(null);

  // ─── File actions ───────────────────────────────────────────────────────────
  const openSubtitlePath = async (path: string) => {
    try {
      await useSubtitleStore.getState().openPath(path);
      useSettingsStore.getState().addRecentFile(path);
    } catch (e) {
      alert((e as Error).message);
    }
  };

  const doOpen = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "Subtitles", extensions: openExtensions() }],
    });
    if (typeof selected === "string") await openSubtitlePath(selected);
  };

  /** Save-as dialog + write. Returns true when actually saved (false = cancelled). */
  const doSaveNative = async (): Promise<boolean> => {
    const base = (useSubtitleStore.getState().fileName ?? "untitled").replace(/\.[^.]+$/, "");
    const path = await save({
      defaultPath: `${base}.${NATIVE_EXT}`,
      filters: [{ name: "Glyphline Project", extensions: [NATIVE_EXT] }],
    });
    if (!path) return false;
    await useSubtitleStore.getState().saveNativePath(path);
    useSettingsStore.getState().addRecentFile(path);
    clearAutosave(); // saved = nothing left to recover
    return true;
  };

  // Run the file dialog + write. Assumes any loss was already confirmed.
  // `encoding` (WHATWG label) lets us emit legacy CP949 SMI for old Korean players.
  const performExport = (format: SubFormat, encoding?: string) => {
    void (async () => {
      const adapter = adapterForFormat(format);
      const base = (useSubtitleStore.getState().fileName ?? "untitled").replace(/\.[^.]+$/, "");
      const path = await save({
        defaultPath: `${base}.${adapter.extensions[0]}`,
        filters: [{ name: adapter.label, extensions: adapter.extensions }],
      });
      if (path) await useSubtitleStore.getState().exportPath(path, format, "text", encoding);
    })();
  };

  // Export the translation column (fallback: original text) as the body.
  const doExportTranslation = (format: SubFormat) => {
    void (async () => {
      const adapter = adapterForFormat(format);
      const base = (useSubtitleStore.getState().fileName ?? "untitled").replace(/\.[^.]+$/, "");
      const path = await save({
        defaultPath: `${base}.translated.${adapter.extensions[0]}`,
        filters: [{ name: adapter.label, extensions: adapter.extensions }],
      });
      if (path) await useSubtitleStore.getState().exportPath(path, format, "translation");
    })();
  };

  const doExport = (format: SubFormat, encoding?: string) => {
    // Warn before a lossy ASS->SMI export when override tags would be dropped.
    const loss = format === "smi" ? smiExportLoss(useSubtitleStore.getState().doc) : [];
    if (loss.length) {
      setPendingExport({ format, categories: loss, encoding });
      return;
    }
    performExport(format, encoding);
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
    onOpenRecent: (path) => void openSubtitlePath(path),
    onClearRecent: () => useSettingsStore.getState().clearRecentFiles(),
    onOpenMedia: () => void doOpenMedia(),
    onCloseMedia: () => useMediaStore.getState().closeMedia(),
    onSave: () => void doSaveNative(),
    onExport: doExport,
    onExportTranslation: doExportTranslation,
    onExportSmiCp949: () => doExport("smi", "euc-kr"),
    onTogglePlay: () => useMediaStore.getState().togglePlay(),
    onSkip: (d) => useMediaStore.getState().skip(d),
    onUndo: () => useSubtitleStore.getState().undo(),
    onRedo: () => useSubtitleStore.getState().redo(),
    onFindReplace: () => setShowFindReplace(true),
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
    onPointSync: () => setShowPointSync(true),
    onChangeSpeed: () => setShowChangeSpeed(true),
    onBatchCleanup: () => setShowBatchCleanup(true),
    onStatistics: () => setShowStatistics(true),
    onStyles: () => setShowStyles(true),
    onEditTags: () => useSettingsStore.getState().openTagEditor(),
    onEmbedded: () => setShowEmbedded(true),
    onRawEdit: () => setShowRawEditor(true),
    onSettings: () => useSettingsStore.getState().openSettingsModal(),
    onHelp: () => setShowHelp(true),
    onResetLayout: () => resetDockLayout(),
    onToggleTranslation: () => useSettingsStore.getState().toggleTranslation(),
    onToggleActor: () => useSettingsStore.getState().toggleActor(),
    onPlugins: () => setShowPluginManager(true),
    onSetLang: (l) => useI18nStore.getState().setLang(l),
  };

  // Rebuild on language change so labels + the language checkmarks stay in sync.
  useEffect(() => {
    // Indirect through the ref so each rebuild captures live handlers.
    const stable: MenuHandlers = {
      onNew: () => handlersRef.current.onNew(),
      onOpen: () => handlersRef.current.onOpen(),
      onOpenRecent: (p) => handlersRef.current.onOpenRecent(p),
      onClearRecent: () => handlersRef.current.onClearRecent(),
      onOpenMedia: () => handlersRef.current.onOpenMedia(),
      onCloseMedia: () => handlersRef.current.onCloseMedia(),
      onSave: () => handlersRef.current.onSave(),
      onExport: (f) => handlersRef.current.onExport(f),
      onExportTranslation: (f) => handlersRef.current.onExportTranslation(f),
      onExportSmiCp949: () => handlersRef.current.onExportSmiCp949(),
      onTogglePlay: () => handlersRef.current.onTogglePlay(),
      onSkip: (d) => handlersRef.current.onSkip(d),
      onUndo: () => handlersRef.current.onUndo(),
      onRedo: () => handlersRef.current.onRedo(),
      onFindReplace: () => handlersRef.current.onFindReplace(),
      onAddCue: () => handlersRef.current.onAddCue(),
      onSplit: () => handlersRef.current.onSplit(),
      onMerge: () => handlersRef.current.onMerge(),
      onDelete: () => handlersRef.current.onDelete(),
      onShift: () => handlersRef.current.onShift(),
      onPointSync: () => handlersRef.current.onPointSync(),
      onChangeSpeed: () => handlersRef.current.onChangeSpeed(),
      onBatchCleanup: () => handlersRef.current.onBatchCleanup(),
      onStatistics: () => handlersRef.current.onStatistics(),
      onStyles: () => handlersRef.current.onStyles(),
      onEditTags: () => handlersRef.current.onEditTags(),
      onEmbedded: () => handlersRef.current.onEmbedded(),
      onRawEdit: () => handlersRef.current.onRawEdit(),
      onSettings: () => handlersRef.current.onSettings(), // handled via store
      onHelp: () => handlersRef.current.onHelp(),
      onResetLayout: () => handlersRef.current.onResetLayout(),
      onToggleTranslation: () => handlersRef.current.onToggleTranslation(),
      onToggleActor: () => handlersRef.current.onToggleActor(),
      onPlugins: () => handlersRef.current.onPlugins(),
      onSetLang: (l) => handlersRef.current.onSetLang(l),
    };
    installAppMenu(t, lang, recentFiles, stable).catch((e) => console.error("menu install failed", e));
    // recentKey: rebuild when the recent-files list changes (native menu is static).
  }, [lang, t, recentKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // ─── Hide the opaque mpv video window while any modal is open ─────────────────
  // The mpv surface is a native child window drawn above the web view; a modal
  // overlapping the video panel would otherwise be hidden behind it.
  const setOverlayOpen = useSettingsStore((s) => s.setOverlayOpen);
  const anyModalOpen =
    showHelp || showSettings || showNewConfirm || showRawEditor || showShift ||
    showFindReplace || showBatchCleanup || showPointSync || showChangeSpeed ||
    showStatistics || showStyles || showEmbedded || showTagEditor ||
    showPluginManager || pendingExport != null || showCloseConfirm || recovery != null;
  useEffect(() => {
    setOverlayOpen(anyModalOpen);
  }, [anyModalOpen, setOverlayOpen]);

  // ─── Crash-recovery autosave ──────────────────────────────────────────────────
  // Every 30 s, if the document is dirty and non-trivial, snapshot it (lossless
  // .glyph JSON) to a fixed temp path. On startup, offer to restore it. The file
  // is deleted on manual save, on explicit discard, and on "close without saving".
  const autosavePathRef = useRef<string | null>(null);
  const clearAutosave = () => {
    const p = autosavePathRef.current;
    if (p) invoke("remove_file", { path: p }).catch(() => {});
  };

  useEffect(() => {
    let timer: number | undefined;
    void (async () => {
      try {
        autosavePathRef.current = await invoke<string>("autosave_path");
        // Startup: offer recovery if a previous session left an autosave behind.
        const raw = await invoke<string>("read_text_file", { path: autosavePathRef.current }).catch(() => null);
        if (raw) {
          const data = JSON.parse(raw) as AutosaveData;
          if (typeof data.glyph === "string" && data.glyph.length > 0) setRecovery(data);
        }
      } catch {
        /* no autosave — normal first start */
      }
      timer = window.setInterval(() => {
        const s = useSubtitleStore.getState();
        const p = autosavePathRef.current;
        if (!p || !s.isDirty || s.doc.cues.length === 0) return;
        const data: AutosaveData = {
          savedAt: Date.now(),
          filePath: s.filePath,
          fileName: s.fileName,
          glyph: serializeGlyph(s.doc),
        };
        invoke("write_text_file", { path: p, content: JSON.stringify(data) }).catch(() => {});
      }, 30_000);
    })();
    return () => window.clearInterval(timer);
  }, []);

  const restoreRecovery = () => {
    if (!recovery) return;
    try {
      const doc = parseGlyph(recovery.glyph);
      useSubtitleStore.getState().restoreDoc(doc, recovery.filePath, recovery.fileName);
    } catch (e) {
      alert((e as Error).message);
    }
    clearAutosave();
    setRecovery(null);
  };
  const discardRecovery = () => {
    clearAutosave();
    setRecovery(null);
  };

  // ─── Unsaved-changes guard on window close ────────────────────────────────────
  useEffect(() => {
    const unlistenP = getCurrentWindow().onCloseRequested((e) => {
      if (useSubtitleStore.getState().isDirty) {
        e.preventDefault();
        setShowCloseConfirm(true);
      }
    });
    return () => {
      unlistenP.then((un) => un()).catch(() => {});
    };
  }, []);

  const forceClose = () => getCurrentWindow().destroy(); // bypasses onCloseRequested

  // ─── Drag & drop: open subtitle / media files dropped onto the window ─────────
  useEffect(() => {
    const unlistenP = getCurrentWebview().onDragDropEvent((e) => {
      if (e.payload.type !== "drop") return;
      const subtitleExts = new Set(openExtensions());
      const mediaExts = new Set(MEDIA_EXTS);
      for (const path of e.payload.paths) {
        const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
        if (subtitleExts.has(ext)) void openSubtitlePath(path);
        else if (mediaExts.has(ext)) void useMediaStore.getState().loadMedia(path);
      }
    });
    return () => {
      unlistenP.then((un) => un()).catch(() => {});
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
      {showFindReplace && <FindReplaceModal onClose={() => setShowFindReplace(false)} />}
      {showBatchCleanup && <BatchCleanupModal onClose={() => setShowBatchCleanup(false)} />}
      {showPointSync && <PointSyncModal onClose={() => setShowPointSync(false)} />}
      {showChangeSpeed && <ChangeSpeedModal onClose={() => setShowChangeSpeed(false)} />}
      {showStatistics && <StatisticsModal onClose={() => setShowStatistics(false)} />}
      {showCloseConfirm && (
        <CloseConfirmModal
          onSaveAndClose={() => {
            setShowCloseConfirm(false);
            void doSaveNative().then((saved) => { if (saved) forceClose(); });
          }}
          onDiscard={() => {
            clearAutosave(); // user explicitly discarded — don't offer recovery next start
            forceClose();
          }}
          onCancel={() => setShowCloseConfirm(false)}
        />
      )}
      {recovery && (
        <RecoveryModal
          fileName={recovery.fileName}
          savedAt={recovery.savedAt}
          onRestore={restoreRecovery}
          onDiscard={discardRecovery}
        />
      )}
      {showStyles && <StyleManagerModal onClose={() => setShowStyles(false)} />}
      {showEmbedded && <EmbeddedAssetsModal onClose={() => setShowEmbedded(false)} />}
      {showTagEditor && <InlineTagEditorModal onClose={closeTagEditor} />}
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
            const { format: fmt, encoding } = pendingExport;
            setPendingExport(null);
            performExport(fmt, encoding);
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
