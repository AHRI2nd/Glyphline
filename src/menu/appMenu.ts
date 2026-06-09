// Native macOS application menu (the bar to the right of the Apple logo).
//
// All "command" actions live here rather than in-app buttons, for a Mac-native
// feel. Menu accelerators own the keyboard shortcuts, so the app does NOT also
// register a window keydown handler for these (that would double-fire).

import {
  CheckMenuItem,
  Menu,
  MenuItem,
  PredefinedMenuItem,
  Submenu,
} from "@tauri-apps/api/menu";
import type { Lang, Translations } from "../i18n/translations";
import type { SubFormat } from "../types/subtitle";

export interface MenuHandlers {
  onNew: () => void;
  onOpen: () => void;
  onOpenMedia: () => void;
  onCloseMedia: () => void;
  onSave: () => void;
  onExport: (format: SubFormat) => void;
  onTogglePlay: () => void;
  onSkip: (delta: number) => void;
  onUndo: () => void;
  onRedo: () => void;
  onAddCue: () => void;
  onSplit: () => void;
  onMerge: () => void;
  onDelete: () => void;
  onShift: () => void;
  onStyles: () => void;
  onEditTags: () => void;
  onEmbedded: () => void;
  onRawEdit: () => void;
  onSettings: () => void;
  onHelp: () => void;
  onResetLayout: () => void;
  onToggleSpectrogram: () => void;
  onToggleTranslation: () => void;
  onPlugins: () => void;
  onSetLang: (lang: Lang) => void;
}

/** Build the app menu and install it as the macOS menu bar. */
export async function installAppMenu(t: Translations, lang: Lang, h: MenuHandlers): Promise<void> {
  const sep = () => PredefinedMenuItem.new({ item: "Separator" });

  const appMenu = await Submenu.new({
    text: t.appName,
    items: [
      await MenuItem.new({ text: `${t.settings}…`, accelerator: "CmdOrCtrl+,", action: h.onSettings }),
      await sep(),
      await PredefinedMenuItem.new({ item: "Services" }),
      await sep(),
      await PredefinedMenuItem.new({ item: "Hide" }),
      await PredefinedMenuItem.new({ item: "HideOthers" }),
      await PredefinedMenuItem.new({ item: "ShowAll" }),
      await sep(),
      await PredefinedMenuItem.new({ item: "Quit" }),
    ],
  });

  const fileMenu = await Submenu.new({
    text: t.fileMenu,
    items: [
      await MenuItem.new({ text: t.newFile, accelerator: "CmdOrCtrl+N", action: h.onNew }),
      await MenuItem.new({ text: `${t.open}…`, accelerator: "CmdOrCtrl+O", action: h.onOpen }),
      await MenuItem.new({ text: t.openMedia, accelerator: "CmdOrCtrl+Shift+O", action: h.onOpenMedia }),
      await MenuItem.new({ text: t.closeMedia, action: h.onCloseMedia }),
      await sep(),
      await MenuItem.new({ text: t.save, accelerator: "CmdOrCtrl+S", action: h.onSave }),
      await Submenu.new({
        text: t.exportAs,
        items: [
          await MenuItem.new({ text: "SubRip (.srt)", action: () => h.onExport("srt") }),
          await MenuItem.new({ text: "WebVTT (.vtt)", action: () => h.onExport("vtt") }),
          await MenuItem.new({ text: "ASS/SSA (.ass)", action: () => h.onExport("ass") }),
          await MenuItem.new({ text: "SAMI (.smi)", action: () => h.onExport("smi") }),
        ],
      }),
    ],
  });

  const editMenu = await Submenu.new({
    text: t.editMenu,
    items: [
      await MenuItem.new({ text: t.undo, accelerator: "CmdOrCtrl+Z", action: h.onUndo }),
      await MenuItem.new({ text: t.redo, accelerator: "CmdOrCtrl+Shift+Z", action: h.onRedo }),
      await sep(),
      // Predefined items so text fields support clipboard ops via the menu.
      await PredefinedMenuItem.new({ item: "Cut" }),
      await PredefinedMenuItem.new({ item: "Copy" }),
      await PredefinedMenuItem.new({ item: "Paste" }),
      await PredefinedMenuItem.new({ item: "SelectAll" }),
    ],
  });

  const subtitleMenu = await Submenu.new({
    text: t.subtitleMenu,
    items: [
      await MenuItem.new({ text: t.addCue, accelerator: "CmdOrCtrl+Return", action: h.onAddCue }),
      await MenuItem.new({ text: t.splitCue, action: h.onSplit }),
      await MenuItem.new({ text: t.mergeCues, action: h.onMerge }),
      await MenuItem.new({ text: t.deleteCue, action: h.onDelete }),
      await sep(),
      await MenuItem.new({ text: t.shiftTime, action: h.onShift }),
      await MenuItem.new({ text: t.styleManager, action: h.onStyles }),
      await MenuItem.new({ text: t.editTags, action: h.onEditTags }),
      await MenuItem.new({ text: `${t.embeddedAssets}…`, action: h.onEmbedded }),
      await MenuItem.new({ text: t.rawEdit, action: h.onRawEdit }),
    ],
  });

  const playbackMenu = await Submenu.new({
    text: t.playbackMenu,
    items: [
      // Note: no "Space" accelerator — it would block typing spaces in cue text.
      await MenuItem.new({ text: t.playPause, accelerator: "CmdOrCtrl+K", action: h.onTogglePlay }),
      await sep(),
      await MenuItem.new({ text: t.skipBack5, accelerator: "CmdOrCtrl+Shift+Left", action: () => h.onSkip(-5) }),
      await MenuItem.new({ text: t.skipBack1, accelerator: "CmdOrCtrl+Left", action: () => h.onSkip(-1) }),
      await MenuItem.new({ text: t.skipFwd1, accelerator: "CmdOrCtrl+Right", action: () => h.onSkip(1) }),
      await MenuItem.new({ text: t.skipFwd5, accelerator: "CmdOrCtrl+Shift+Right", action: () => h.onSkip(5) }),
    ],
  });

  const viewMenu = await Submenu.new({
    text: t.viewMenu,
    items: [
      await MenuItem.new({ text: t.resetLayout, action: h.onResetLayout }),
      await MenuItem.new({ text: t.spectrogram, action: h.onToggleSpectrogram }),
      await MenuItem.new({ text: t.showTranslation, action: h.onToggleTranslation }),
      await MenuItem.new({ text: t.plugins, action: h.onPlugins }),
      await sep(),
      await Submenu.new({
        text: t.language,
        items: [
          await CheckMenuItem.new({ text: "한국어", checked: lang === "ko", action: () => h.onSetLang("ko") }),
          await CheckMenuItem.new({ text: "English", checked: lang === "en", action: () => h.onSetLang("en") }),
          await CheckMenuItem.new({ text: "日本語", checked: lang === "ja", action: () => h.onSetLang("ja") }),
        ],
      }),
    ],
  });

  const helpMenu = await Submenu.new({
    text: t.help,
    items: [await MenuItem.new({ text: t.shortcuts, action: h.onHelp })],
  });

  const menu = await Menu.new({
    items: [appMenu, fileMenu, editMenu, subtitleMenu, playbackMenu, viewMenu, helpMenu],
  });
  await menu.setAsAppMenu();
}
