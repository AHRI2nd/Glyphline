import { useI18nStore } from "../../stores/useI18nStore";
import { useSubtitleStore } from "../../stores/useSubtitleStore";

// Slim in-app toolbar. File/Settings/Export/Language/etc. now live in the native
// macOS menu bar (see src/menu/appMenu.ts); only frequent direct-editing actions
// and the document status stay here.
interface Props {
  onAddCue: () => void;
  onMerge: () => void;
  onDelete: () => void;
}

export function Toolbar({ onAddCue, onMerge, onDelete }: Props) {
  const { t } = useI18nStore();
  const { fileName, isDirty } = useSubtitleStore();
  const canUndo = useSubtitleStore((s) => s._history.length > 0);
  const canRedo = useSubtitleStore((s) => s._future.length > 0);
  const undo = useSubtitleStore((s) => s.undo);
  const redo = useSubtitleStore((s) => s.redo);
  const selectedCount = useSubtitleStore((s) => s.selectedIds.size);

  return (
    <header className="flex shrink-0 items-center gap-1 border-b border-zinc-800 bg-zinc-900 px-4 py-2">
      <span className="mr-2 shrink-0 font-semibold text-indigo-400">{t.appName}</span>

      <Btn onClick={undo} disabled={!canUndo}>↶ {t.undo}</Btn>
      <Btn onClick={redo} disabled={!canRedo}>↷ {t.redo}</Btn>

      <Divider />

      <Btn onClick={onAddCue}>＋ {t.addCue}</Btn>
      <Btn onClick={onMerge} disabled={selectedCount < 2}>{t.mergeCues}</Btn>
      <Btn onClick={onDelete} disabled={selectedCount < 1}>{t.deleteCue}</Btn>

      <div className="ml-auto flex items-center gap-2 truncate text-xs text-zinc-400">
        <span className="truncate">{fileName ?? t.untitled}</span>
        {isDirty && <span className="shrink-0 text-rose-400">• {t.unsaved}</span>}
      </div>
    </header>
  );
}

function Btn({ children, onClick, disabled }: { children: React.ReactNode; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="rounded px-2 py-1 text-xs text-zinc-200 transition-colors hover:bg-zinc-800 disabled:cursor-not-allowed disabled:text-zinc-600 disabled:hover:bg-transparent"
    >
      {children}
    </button>
  );
}

function Divider() {
  return <span className="mx-1 h-5 w-px bg-zinc-700" />;
}
