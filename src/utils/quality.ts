// Subtitle quality checks: CPS (characters per second), duration, overlap, and
// line length / line count. Thresholds are configurable (Settings) with a
// Netflix preset; the defaults below are common general-purpose values.

import type { Cue } from "../types/subtitle";

export interface QualityThresholds {
  maxCps: number; // characters per second ceiling
  minDuration: number; // seconds
  maxDuration: number; // seconds
  maxLineLength: number; // characters per line
  maxLines: number; // lines per cue
}

export const DEFAULT_THRESHOLDS: QualityThresholds = {
  maxCps: 20,
  minDuration: 0.7,
  maxDuration: 7,
  maxLineLength: 42,
  maxLines: 2,
};

// Netflix timed-text style guide (English/most languages).
export const NETFLIX_THRESHOLDS: QualityThresholds = {
  maxCps: 17,
  minDuration: 0.833, // 5/6 s (20 frames @ 24fps)
  maxDuration: 7,
  maxLineLength: 42,
  maxLines: 2,
};

// Back-compat named constants (used as fallbacks / dialog defaults).
export const MAX_CPS = DEFAULT_THRESHOLDS.maxCps;
export const MIN_DURATION = DEFAULT_THRESHOLDS.minDuration;
export const MAX_DURATION = DEFAULT_THRESHOLDS.maxDuration;

/** Visible characters (line breaks and spaces excluded from the count). */
export function visibleCharCount(text: string): number {
  return text.replace(/\s+/g, "").length;
}

export function cueDuration(cue: Cue): number {
  return Math.max(0, cue.end - cue.start);
}

/** Characters per second; 0 when duration is non-positive. */
export function cps(cue: Cue): number {
  const d = cueDuration(cue);
  if (d <= 0) return 0;
  return visibleCharCount(cue.text) / d;
}

/** Longest line length (visible chars, spaces kept — they take display width). */
export function longestLineLength(text: string): number {
  return text.split("\n").reduce((max, line) => Math.max(max, line.trim().length), 0);
}

export function lineCount(text: string): number {
  return text.split("\n").length;
}

export interface CueQuality {
  durationTooShort: boolean;
  durationTooLong: boolean;
  cpsTooHigh: boolean;
  negativeDuration: boolean;
  overlapsPrev: boolean;
  lineTooLong: boolean;
  tooManyLines: boolean;
}

/** Evaluate a cue against the cue before it (already time-sorted). */
export function evaluateCue(
  cue: Cue,
  prev: Cue | null,
  th: QualityThresholds = DEFAULT_THRESHOLDS,
): CueQuality {
  const d = cueDuration(cue);
  return {
    negativeDuration: cue.end < cue.start,
    durationTooShort: d > 0 && d < th.minDuration,
    durationTooLong: d > th.maxDuration,
    cpsTooHigh: cps(cue) > th.maxCps,
    overlapsPrev: prev != null && cue.start < prev.end - 1e-6,
    lineTooLong: cue.text.trim() !== "" && longestLineLength(cue.text) > th.maxLineLength,
    tooManyLines: lineCount(cue.text) > th.maxLines,
  };
}

export function hasAnyIssue(q: CueQuality): boolean {
  return (
    q.negativeDuration ||
    q.durationTooShort ||
    q.durationTooLong ||
    q.cpsTooHigh ||
    q.overlapsPrev ||
    q.lineTooLong ||
    q.tooManyLines
  );
}
