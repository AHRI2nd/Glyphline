import { useEffect, useState } from "react";
import { Plus, Trash2, Globe, Puzzle } from "lucide-react";
import { useI18nStore } from "../../stores/useI18nStore";
import { usePluginStore, BUILTIN_PLUGINS, type PluginDef } from "../../stores/usePluginStore";
import { Backdrop } from "../Modals/ConfirmModal";

interface Props {
  onOpen: (plugin: PluginDef) => void;
  onClose: () => void;
}

export function PluginManagerModal({ onOpen, onClose }: Props) {
  const { t } = useI18nStore();
  const { allPlugins, addPlugin, removePlugin } = usePluginStore();
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const handleAdd = () => {
    if (!name.trim()) { setError("이름을 입력하세요."); return; }
    if (!url.trim() || !/^https?:\/\//.test(url)) { setError("유효한 URL을 입력하세요 (https://)."); return; }
    addPlugin({ name: name.trim(), kind: "iframe", url: url.trim() });
    setName(""); setUrl(""); setError("");
  };

  const plugins = allPlugins();

  return (
    <Backdrop onClick={onClose}>
      <div className="flex h-[70vh] w-[600px] flex-col rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-3">
          <h3 className="flex items-center gap-2 text-sm font-semibold text-zinc-100">
            <Puzzle size={15} className="text-indigo-400" />
            {t.pluginManager}
          </h3>
          <button className="text-zinc-400 transition-colors hover:text-white" onClick={onClose}>✕</button>
        </div>

        {/* plugin list */}
        <div className="ws-scroll flex-1 overflow-y-auto">
          {plugins.map((p) => {
            const isBuiltin = BUILTIN_PLUGINS.some((b) => b.id === p.id);
            return (
              <div key={p.id} className="flex items-center gap-3 border-b border-zinc-800/60 px-5 py-3">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded bg-zinc-800">
                  {p.kind === "iframe" ? <Globe size={14} className="text-zinc-400" /> : <Puzzle size={14} className="text-indigo-400" />}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-zinc-100">{p.name}</span>
                    {isBuiltin && <span className="rounded bg-indigo-900/50 px-1.5 py-0.5 text-[10px] text-indigo-300">기본</span>}
                  </div>
                  {p.description && <p className="text-xs text-zinc-500">{p.description}</p>}
                  {p.url && <p className="truncate text-[10px] text-zinc-600">{p.url}</p>}
                </div>
                <button
                  onClick={() => { onOpen(p); onClose(); }}
                  className="rounded bg-indigo-600 px-3 py-1 text-xs text-white transition-colors hover:bg-indigo-500"
                >
                  {t.pluginOpen}
                </button>
                {!isBuiltin && (
                  <button
                    onClick={() => removePlugin(p.id)}
                    className="rounded p-1 text-zinc-500 transition-colors hover:bg-zinc-800 hover:text-red-400"
                  >
                    <Trash2 size={14} />
                  </button>
                )}
              </div>
            );
          })}
        </div>

        {/* add user plugin */}
        <div className="border-t border-zinc-800 px-5 py-4">
          <p className="mb-2 text-xs font-medium text-zinc-400">{t.pluginAddNew}</p>
          <div className="flex gap-2">
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t.pluginName}
              className="w-32 shrink-0 rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 outline-none focus:border-indigo-500"
            />
            <input
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://..."
              className="flex-1 rounded border border-zinc-700 bg-zinc-950 px-2 py-1 text-xs text-zinc-100 outline-none focus:border-indigo-500"
            />
            <button
              onClick={handleAdd}
              className="flex shrink-0 items-center gap-1 rounded bg-zinc-700 px-3 py-1 text-xs text-zinc-200 transition-colors hover:bg-zinc-600"
            >
              <Plus size={12} /> {t.pluginAdd}
            </button>
          </div>
          {error && <p className="mt-1 text-xs text-red-400">{error}</p>}
        </div>
      </div>
    </Backdrop>
  );
}
