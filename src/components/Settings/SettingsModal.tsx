import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { Backdrop } from "../Modals/ConfirmModal";

function MpvSection() {
  const [available, setAvailable] = useState<boolean | null>(null);
  const [installing, setInstalling] = useState(false);
  const [progress, setProgress] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    invoke<boolean>("check_mpv").then(setAvailable).catch(() => setAvailable(false));
  }, []);

  const install = async () => {
    setInstalling(true);
    setError(null);
    setProgress("");

    const unlisten = await listen<string>("mpv-install-progress", (e) => {
      setProgress(e.payload);
    });

    try {
      await invoke("install_mpv");
      // Re-check after install
      const ok = await invoke<boolean>("check_mpv");
      setAvailable(ok);
    } catch (e) {
      setError(String(e));
    } finally {
      unlisten();
      setInstalling(false);
    }
  };

  return (
    <div className="mt-5 border-t border-zinc-800 pt-4">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-zinc-500">
        미디어 엔진 (mpv)
      </div>

      {available === null && (
        <p className="text-xs text-zinc-500">확인 중…</p>
      )}

      {available === true && (
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-emerald-500" />
          <span className="text-xs text-zinc-300">설치됨 — 모든 포맷 재생 가능</span>
        </div>
      )}

      {available === false && !installing && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-amber-500" />
            <span className="text-xs text-zinc-400">
              mpv 미설치 — MKV, AVI, WebM 등 재생 불가
            </span>
          </div>
          <button
            onClick={() => void install()}
            className="self-start rounded bg-indigo-600 px-3 py-1.5 text-xs text-white transition-colors hover:bg-indigo-500"
          >
            Homebrew로 mpv 설치
          </button>
          {error && (
            <p className="whitespace-pre-wrap text-[11px] text-rose-400">{error}</p>
          )}
        </div>
      )}

      {installing && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <div className="h-3 w-3 animate-spin rounded-full border border-zinc-600 border-t-indigo-400" />
            <span className="text-xs text-zinc-400">{progress || "준비 중…"}</span>
          </div>
        </div>
      )}

      {available === false && !installing && (
        <p className="mt-2 text-[11px] text-zinc-600">
          수동 설치: <span className="font-mono">brew install mpv</span><br />
          설치 후 앱을 재시작하세요.
        </p>
      )}
    </div>
  );
}

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const { t } = useI18nStore();
  const { uiScale, setUiScale, autoCheckUpdate, setAutoCheckUpdate } = useSettingsStore();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <Backdrop onClick={onClose}>
      <div
        className="w-[420px] rounded-xl border border-zinc-700 bg-zinc-900 p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 className="mb-4 text-sm font-semibold text-zinc-100">{t.settings}</h3>

        <div className="mb-5">
          <div className="mb-1 flex justify-between text-sm text-zinc-300">
            <span>{t.uiScale}</span>
            <span className="font-mono text-zinc-400">{uiScale.toFixed(2)}×</span>
          </div>
          <input
            type="range" min={0.7} max={1.3} step={0.05} value={uiScale}
            onChange={(e) => setUiScale(Number(e.target.value))}
            className="w-full"
          />
        </div>

        <label className="flex cursor-pointer items-center gap-2 text-sm text-zinc-300">
          <input
            type="checkbox" checked={autoCheckUpdate}
            onChange={(e) => setAutoCheckUpdate(e.target.checked)}
          />
          {t.autoCheckUpdate}
        </label>

        <MpvSection />

        <div className="mt-6 flex justify-end">
          <button
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-500"
            onClick={onClose}
          >
            {t.close}
          </button>
        </div>
      </div>
    </Backdrop>
  );
}
