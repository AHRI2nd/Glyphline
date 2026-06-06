import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useI18nStore } from "../../stores/useI18nStore";
import { useSettingsStore } from "../../stores/useSettingsStore";
import { Backdrop } from "../Modals/ConfirmModal";

interface FfmpegProgress {
  stage: "downloading" | "extracting" | "done";
  percent: number;
  message: string;
}

function FfmpegSection() {
  const [status, setStatus] = useState<"checking" | "found" | "missing">("checking");
  const [ffmpegPath, setFfmpegPath] = useState<string | null>(null);
  const [installing, setInstalling] = useState(false);
  const [progress, setProgress] = useState<FfmpegProgress | null>(null);
  const [error, setError] = useState<string | null>(null);

  const check = async () => {
    setStatus("checking");
    const path = await invoke<string | null>("check_ffmpeg");
    if (path) { setStatus("found"); setFfmpegPath(path); }
    else { setStatus("missing"); setFfmpegPath(null); }
  };

  useEffect(() => { void check(); }, []);

  const install = async () => {
    setInstalling(true);
    setError(null);
    setProgress(null);

    const unlisten = await listen<FfmpegProgress>("ffmpeg-progress", (e) => {
      setProgress(e.payload);
    });

    try {
      await invoke("install_ffmpeg");
      await check(); // re-verify
    } catch (e) {
      setError(String(e));
    } finally {
      unlisten();
      setInstalling(false);
    }
  };

  return (
    <div className="mt-5 border-t border-zinc-800 pt-4">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-zinc-500">FFmpeg</div>

      {status === "checking" && (
        <p className="text-xs text-zinc-500">확인 중…</p>
      )}

      {status === "found" && (
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-emerald-500" />
          <span className="text-xs text-zinc-300">설치됨</span>
          {ffmpegPath && ffmpegPath !== "ffmpeg" && (
            <span className="ml-1 truncate text-[10px] text-zinc-600">{ffmpegPath}</span>
          )}
        </div>
      )}

      {status === "missing" && !installing && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-amber-500" />
            <span className="text-xs text-zinc-400">미설치 — MKV, AVI, WebM 등 재생 불가</span>
          </div>
          <button
            onClick={() => void install()}
            className="self-start rounded bg-indigo-600 px-3 py-1.5 text-xs text-white hover:bg-indigo-500 transition-colors"
          >
            FFmpeg 자동 설치 (LGPL)
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
            <span className="text-xs text-zinc-400">{progress?.message ?? "준비 중…"}</span>
          </div>
          {progress?.stage === "downloading" && progress.percent > 0 && (
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800">
              <div
                className="h-full rounded-full bg-indigo-500 transition-all"
                style={{ width: `${progress.percent}%` }}
              />
            </div>
          )}
        </div>
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

        <FfmpegSection />

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
