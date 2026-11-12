/**
 * Pure rules for the weekly league: how a player's league score wears down
 * over the weeks, and what a week's reward is paid at.
 *
 * Kept out of index.ts (like rewards.ts) so they can be tested without
 * firebase-admin or a clock. Mirrored by `decayedLeagueScore` in
 * lib/services/league_service.dart, which shows the same number the server
 * will use.
 */

import {parseDateId} from "./daily_challenge_dates";

/**
 * Share of the league score lost at each week's turn.
 *
 * The score used to only grow, so about ten good days put any player in
 * Master for good, collecting its weekly reward with a single Daily
 * Challenge. With a quarter gone each week the score settles at four times
 * what the player earns in one: staying up takes playing, and stopping
 * brings a player down on its own.
 */
export const WEEKLY_LEAGUE_DECAY = 0.25;

/** Daily Challenges in a week that earn the league's own reward. */
export const MIN_DAILIES_FOR_LEAGUE_REWARD = 3;

/** Past this many weeks away nothing is left to take. */
const MAX_DECAY_WEEKS = 52;

/**
 * Whole weeks from one week id to a later one.
 * @param {string} fromWeekId A week's Monday, `YYYY-MM-DD`.
 * @param {string} toWeekId A later week's Monday.
 * @return {number} 0 when either is unreadable or `to` is not later.
 */
export function weeksBetween(fromWeekId: string, toWeekId: string): number {
  const from = parseDateId(fromWeekId);
  const to = parseDateId(toWeekId);
  if (Number.isNaN(from) || Number.isNaN(to)) return 0;
  return Math.max(0, Math.round((to - from) / (7 * 86400000)));
}

/**
 * A league score as it stands in [currentWeekId], after the weeks gone by
 * since it was last brought up to date.
 *
 * Applied when the player next plays rather than by a job over every
 * account: nobody is charged for players who never come back, and the
 * week it was last applied in ([scoreWeekId]) is all it needs. An account
 * from before this existed has no such week and loses nothing the first
 * time.
 * @param {number} score The stored league score.
 * @param {string} scoreWeekId The week it was last brought up to date in.
 * @param {string} currentWeekId The week being played.
 * @return {number} The score to build on.
 */
export function decayedLeagueScore(
  score: number,
  scoreWeekId: string,
  currentWeekId: string
): number {
  const held = Math.max(0, Math.floor(score));
  const weeks = Math.min(
    weeksBetween(scoreWeekId, currentWeekId), MAX_DECAY_WEEKS
  );
  if (weeks === 0) return held;
  return Math.floor(held * Math.pow(1 - WEEKLY_LEAGUE_DECAY, weeks));
}

/**
 * The later of two week ids, so a result filed late for an earlier week
 * can't move the score's week backwards and be worn down twice.
 * @param {string} a A week id, possibly empty.
 * @param {string} b Another.
 * @return {string} The later one.
 */
export function laterWeekId(a: string, b: string): string {
  return a > b ? a : b;
}

/**
 * The league a week's reward is paid at.
 *
 * A league's reward is for playing in it: with fewer than
 * [MIN_DAILIES_FOR_LEAGUE_REWARD] Daily Challenges that week it is paid at
 * Bronze instead. Weeks recorded before the count existed are paid in
 * full — nobody is docked for a rule that wasn't there.
 * @param {string} leagueId The league the week was played in.
 * @param {unknown} dailiesPlayed Daily Challenges that week, if counted.
 * @return {string} The league whose reward applies.
 */
export function rewardLeagueFor(
  leagueId: string,
  dailiesPlayed: unknown
): string {
  if (typeof dailiesPlayed !== "number") return leagueId;
  return dailiesPlayed >= MIN_DAILIES_FOR_LEAGUE_REWARD ? leagueId : "bronze";
}
