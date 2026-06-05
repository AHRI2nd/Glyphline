// Subtitle quality checks: CPS (characters per second), overlap, gap.
// Display-only for the first milestone (badges / warning colors).

import type { Cue } from "../types/subtitle";

export const MAX_CPS = 20; // common readability ceiling
export const MIN_DURATION = 0.7; // seconds
export const MAX_DURATION = 7; // seconds

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

export interface CueQuality {
  durationTooShort: boolean;
  durationTooLong: boolean;
  cpsTooHigh: boolean;
  negativeDuration: boolean;
  overlapsPrev: boolean;
}

/** Evaluate a cue against the cue before it (already time-sorted). */
export function evaluateCue(cue: Cue, prev: Cue | null): CueQuality {
  const d = cueDuration(cue);
  return {
    negativeDuration: cue.end < cue.start,
    durationTooShort: d > 0 && d < MIN_DURATION,
    durationTooLong: d > MAX_DURATION,
    cpsTooHigh: cps(cue) > MAX_CPS,
    overlapsPrev: prev != null && cue.start < prev.end - 1e-6,
  };
}

export function hasAnyIssue(q: CueQuality): boolean {
  return (
    q.negativeDuration ||
    q.durationTooShort ||
    q.durationTooLong ||
    q.cpsTooHigh ||
    q.overlapsPrev
  );
}
