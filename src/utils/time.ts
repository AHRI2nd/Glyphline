// Timecode parsing/formatting helpers. Internal time is always float seconds.

/** Clamp to non-negative and round to millisecond precision. */
export function clampTime(s: number): number {
  return Math.max(0, Math.round(s * 1000) / 1000);
}

// ─── SRT: HH:MM:SS,mmm (comma) — also tolerate '.' on input ────────────────────
export function formatSrtTime(seconds: number): string {
  const ms = Math.round(seconds * 1000);
  const h = Math.floor(ms / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  const s = Math.floor((ms % 60_000) / 1000);
  const milli = ms % 1000;
  return `${pad(h)}:${pad(m)}:${pad(s)},${pad(milli, 3)}`;
}

// ─── VTT: HH:MM:SS.mmm (dot); hours optional on input ──────────────────────────
export function formatVttTime(seconds: number): string {
  return formatSrtTime(seconds).replace(",", ".");
}

// ─── ASS: H:MM:SS.cc (centiseconds) ────────────────────────────────────────────
export function formatAssTime(seconds: number): string {
  const cs = Math.round(seconds * 100);
  const h = Math.floor(cs / 360_000);
  const m = Math.floor((cs % 360_000) / 6000);
  const s = Math.floor((cs % 6000) / 100);
  const centi = cs % 100;
  return `${h}:${pad(m)}:${pad(s)}.${pad(centi)}`;
}

/** Parse SRT/VTT-style "HH:MM:SS,mmm" / "MM:SS.mmm". Accepts ',' or '.'. */
export function parseClockTime(str: string): number | null {
  const m = str.trim().match(/^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})$/);
  if (!m) return null;
  const [, h, mm, ss, frac] = m;
  const millis = Number((frac + "000").slice(0, 3));
  return (Number(h || 0) * 3600 + Number(mm) * 60 + Number(ss)) * 1 + millis / 1000;
}

/** Parse ASS "H:MM:SS.cc" (centiseconds). */
export function parseAssTime(str: string): number | null {
  const m = str.trim().match(/^(\d+):(\d{1,2}):(\d{1,2})\.(\d{1,2})$/);
  if (!m) return null;
  const [, h, mm, ss, cc] = m;
  const centi = Number((cc + "00").slice(0, 2));
  return Number(h) * 3600 + Number(mm) * 60 + Number(ss) + centi / 100;
}

/**
 * Lenient inline-edit parser for the cue table. Accepts:
 *   "1:23.45", "01:23.456", "00:01:23,456", "83.4", "83"
 * Returns seconds or null when unparseable.
 */
export function parseTimestampInput(input: string): number | null {
  const t = input.trim();
  if (!t) return null;
  // Pure seconds (e.g. "83.4")
  if (/^\d+(\.\d+)?$/.test(t)) return Number(t);
  const m = t.match(/^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$/);
  if (!m) return null;
  const [, h, mm, ss, frac] = m;
  const millis = frac ? Number((frac + "000").slice(0, 3)) : 0;
  return Number(h || 0) * 3600 + Number(mm) * 60 + Number(ss) + millis / 1000;
}

/** Compact display for the cue table: "MM:SS.mmm" (or "H:MM:SS.mmm" past an hour). */
export function formatDisplayTime(seconds: number): string {
  const full = formatVttTime(seconds);
  // strip a leading "00:" hour group for brevity when under an hour
  return full.startsWith("00:") ? full.slice(3) : full;
}

function pad(n: number, width = 2): string {
  return String(n).padStart(width, "0");
}
