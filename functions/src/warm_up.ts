/**
 * Warm-up calls: a client that is about to need a function asks it to be
 * ready first.
 *
 * Each callable is its own service, and one that hasn't been called for a
 * while takes seconds to answer its first request. In a timed game that
 * wait lands on the player's first question. So the app sends `{warm:
 * true}` when it opens the screen that will need the function, and the
 * function answers at once without doing its job.
 *
 * Kept out of index.ts so what counts as a warm-up — and therefore what
 * skips a function's real work — is decided in one tested place.
 */

/**
 * Whether a callable's data is a warm-up and nothing else.
 *
 * Only the literal `true` counts: a real request never carries the flag,
 * and anything looser ("true", 1) is not allowed to turn a real call into
 * a no-op.
 * @param {unknown} data The callable's `request.data`.
 * @return {boolean} True when the function should answer without working.
 */
export function isWarmUpRequest(data: unknown): boolean {
  if (data === null || typeof data !== "object") return false;
  return (data as Record<string, unknown>).warm === true;
}
