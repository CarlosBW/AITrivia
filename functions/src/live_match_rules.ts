/**
 * Pure rules for the edges of a live match: when one that nobody is
 * playing any more gets closed, how long a rematch request stands, and
 * who may be paired in ranked.
 *
 * Kept out of index.ts (like pvp_answer_key.ts) so they can be tested
 * without firebase-admin or a clock: "now" is always passed in.
 */

/**
 * How long a rematch request stands.
 *
 * A request used to stand forever. Accepting one hours later started the
 * rematch at once, against a player long gone, and the match was then
 * claimed as won by disconnect — a free win and its coins.
 */
export const REMATCH_REQUEST_TTL_MS = 5 * 60 * 1000;

/**
 * Whether a rematch request is recent enough to act on.
 * @param {unknown} requestedAtMs When it was made (epoch ms), as stored.
 * @param {number} nowMs Now.
 * @return {boolean} False for a missing, future or expired stamp.
 */
export function rematchRequestIsFresh(
  requestedAtMs: unknown,
  nowMs: number
): boolean {
  if (typeof requestedAtMs !== "number" || !Number.isFinite(requestedAtMs)) {
    return false;
  }
  const age = nowMs - requestedAtMs;
  return age >= 0 && age <= REMATCH_REQUEST_TTL_MS;
}

/**
 * Whether a ranked-abandon cooldown is still running.
 *
 * Only the app used to look at it, so a modified client queued for ranked
 * straight after abandoning. Matchmaking checks it for both players now.
 * @param {number|null} cooldownUntilMs When it ends (epoch ms), if set.
 * @param {number} nowMs Now.
 * @return {boolean} True while the player may not be paired in ranked.
 */
export function pvpCooldownActive(
  cooldownUntilMs: number | null,
  nowMs: number
): boolean {
  return cooldownUntilMs !== null && Number.isFinite(cooldownUntilMs) &&
    cooldownUntilMs > nowMs;
}

/** Seconds allowed per question beyond its clock: verdict and reveal. */
export const LIVE_QUESTION_SLACK_SEC = 10;

/** Extra time before a match that ran long is considered abandoned. */
export const LIVE_MATCH_OVERDUE_GRACE_MS = 2 * 60 * 1000;

/** How long a room may sit in its lobby before it is cancelled. */
export const LIVE_LOBBY_MAX_AGE_MS = 30 * 60 * 1000;

/** How long a queue entry may go without a heartbeat before it is stopped. */
export const LIVE_SEARCH_ABANDONED_MS = 2 * 60 * 1000;

/** What the sweep needs to know about one live match. */
export interface LiveMatchAge {
  status: string;
  /** When the room was created (epoch ms); null if unknown. */
  createdAtMs: number | null;
  /** When play started (epoch ms); null before it did. */
  startAtMs: number | null;
  questionCount: number;
  timePerQuestionSec: number;
  nowMs: number;
}

/**
 * Whether a live match has outlived any way of being played.
 *
 * A match in progress can't run longer than its questions, each with its
 * clock plus the pause between them; a room in its lobby is given half an
 * hour. Past that nobody is there: before the sweep these stayed open for
 * good, and a player who had finished never got a result.
 * @param {LiveMatchAge} m The match's age and shape.
 * @return {boolean} True if the sweep should close it.
 */
export function liveMatchIsOverdue(m: LiveMatchAge): boolean {
  if (m.status === "waiting") {
    return m.createdAtMs !== null &&
      m.nowMs - m.createdAtMs > LIVE_LOBBY_MAX_AGE_MS;
  }
  if (m.status !== "playing") return false;

  const startedMs = m.startAtMs ?? m.createdAtMs;
  if (startedMs === null) return false;

  const longestMs = Math.max(m.questionCount, 1) *
    (Math.max(m.timePerQuestionSec, 1) + LIVE_QUESTION_SLACK_SEC) * 1000;
  return m.nowMs - startedMs > longestMs + LIVE_MATCH_OVERDUE_GRACE_MS;
}

/** How the sweep closes an overdue match that was being played. */
export type OverdueLiveMatchOutcome =
  /** Both rounds are closed: only the settlement is missing. */
  | "settle"
  | "host-wins"
  | "guest-wins"
  /** Nobody finished: there is no result to give. */
  | "cancel";

/**
 * Decides how an overdue match in progress ends.
 *
 * The player who finished wins against one who walked away — the same
 * result claiming the disconnect gives, for the case where the finisher
 * had already left the screen and never claimed it.
 * @param {boolean} hostFinished Whether the host closed their round.
 * @param {boolean} guestFinished Whether the guest closed theirs.
 * @return {OverdueLiveMatchOutcome} What to do with the match.
 */
export function overdueLiveMatchOutcome(
  hostFinished: boolean,
  guestFinished: boolean
): OverdueLiveMatchOutcome {
  if (hostFinished && guestFinished) return "settle";
  if (hostFinished) return "host-wins";
  if (guestFinished) return "guest-wins";
  return "cancel";
}

/**
 * Whether a queue entry still marked as searching belongs to nobody.
 *
 * The app refreshes its entry every few seconds while it searches. One
 * left behind by a closed app keeps saying "searching", and matchmaking
 * reads a limited page of those: enough dead ones in a category and real
 * players stop being found.
 * @param {number|null} heartbeatMs Last heartbeat (epoch ms), if any.
 * @param {number} nowMs Now.
 * @return {boolean} True if the sweep should stop the entry.
 */
export function liveSearchIsAbandoned(
  heartbeatMs: number | null,
  nowMs: number
): boolean {
  return heartbeatMs === null || nowMs - heartbeatMs > LIVE_SEARCH_ABANDONED_MS;
}
