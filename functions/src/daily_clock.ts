/**
 * The Daily Challenge clock, decided from its arguments alone so it can be
 * tested without Firestore or a real clock (see daily_challenge_dates.ts).
 */

/**
 * What is left of a daily run, for the app to set its own clock by: the
 * phone's time can be off, and the app's clock stands still while it waits
 * for each verdict, so its count drifts from the server's.
 * @param {number | undefined} startedAtMs When the server opened the run.
 * @param {number} durationMs How long the run lasts.
 * @param {number} nowMs The server's now.
 * @return {number | null} Milliseconds left, never below zero; null when
 *   the run has no recorded start.
 */
export function dailyRemainingMs(
  startedAtMs: number | undefined,
  durationMs: number,
  nowMs: number
): number | null {
  if (startedAtMs === undefined) return null;
  return Math.max(0, startedAtMs + durationMs - nowMs);
}

/**
 * Whether an answer comes in past the run's clock plus [graceMs], the
 * allowance for the round trip and a slow tap.
 * @param {number | undefined} startedAtMs When the server opened the run.
 * @param {number} durationMs How long the run lasts.
 * @param {number} nowMs The server's now.
 * @param {number} graceMs Extra time an answer may still arrive in.
 * @return {boolean} True when the answer is too late to count.
 */
export function dailyAnswerTooLate(
  startedAtMs: number | undefined,
  durationMs: number,
  nowMs: number,
  graceMs: number
): boolean {
  if (startedAtMs === undefined) return false;
  return nowMs > startedAtMs + durationMs + graceMs;
}
