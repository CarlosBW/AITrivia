/**
 * Daily missions: three small goals a day and a chest for doing all three.
 *
 * The server keeps only what the player did that day (`stats`), counted
 * where each thing is already judged — a level's result, the Daily
 * Challenge's, a Weekly Topic round's. Which missions the day has, how far
 * along each is and whether the chest is due are all worked out from those
 * counts here, so none of it can be claimed by a client.
 *
 * Kept out of index.ts so it can be unit-tested without firebase-admin or
 * a clock.
 */

import {parseDateId} from "./daily_challenge_dates";

/**
 * The day missions run on, for everyone: Lima's. One clock rather than
 * each phone's, because what a player did is counted by endpoints that
 * are never told the phone's date.
 */
export const MISSIONS_TIME_ZONE = "America/Lima";

/** What a day's count is of. */
export type MissionStat =
  | "correct"
  | "soloLevels"
  | "greatLevels"
  | "streakLevels"
  | "dailyPlayed"
  | "weeklyRounds";

export const MISSION_STATS: readonly MissionStat[] = [
  "correct", "soloLevels", "greatLevels", "streakLevels", "dailyPlayed",
  "weeklyRounds",
];

/** One goal: reach [target] in [stat] within the day. */
export interface Mission {
  id: string;
  stat: MissionStat;
  target: number;
}

/**
 * The three slots, each with the missions it rotates through: how much to
 * get right, which mode to play, and something to do well.
 *
 * Mirrored by `DailyMissions.slots` in lib/services/daily_missions.dart,
 * which shows them; `test/services/daily_missions_sync_test.dart` keeps
 * the two from drifting apart.
 */
export const MISSION_SLOTS: readonly (readonly Mission[])[] = [
  [
    {id: "correct_15", stat: "correct", target: 15},
    {id: "correct_25", stat: "correct", target: 25},
    {id: "correct_20", stat: "correct", target: 20},
  ],
  [
    {id: "play_daily", stat: "dailyPlayed", target: 1},
    {id: "solo_levels_2", stat: "soloLevels", target: 2},
    {id: "weekly_round", stat: "weeklyRounds", target: 1},
    {id: "solo_levels_3", stat: "soloLevels", target: 3},
  ],
  [
    {id: "streak_level", stat: "streakLevels", target: 1},
    {id: "great_level", stat: "greatLevels", target: 1},
  ],
];

/** A level counts as "great" from this share of right answers. */
export const GREAT_LEVEL_PERCENT = 0.9;
/** A level counts for the streak mission from this run of right answers. */
export const STREAK_LEVEL_RUN = 5;

/** What the chest pays for completing all of a day's missions. */
export const DAILY_MISSIONS_CHEST = {coins: 10, xp: 20} as const;

/**
 * The missions of the day [dateId]: one from each slot, each slot moving
 * on by one a day. Slots differ in length, so the same three rarely meet.
 * @param {string} dateId The day, `YYYY-MM-DD`.
 * @return {Mission[]} That day's missions; none for a date that isn't one.
 */
export function missionsForDate(dateId: string): Mission[] {
  const ms = parseDateId(dateId);
  if (Number.isNaN(ms)) return [];
  const day = Math.round(ms / 86400000);
  return MISSION_SLOTS.map((slot) => slot[day % slot.length]);
}

/** A day's counts. */
export type MissionStats = Record<MissionStat, number>;

/**
 * A stored `stats` map as counts, with anything missing or malformed read
 * as zero.
 * @param {unknown} stored The `stats` field of the day's doc.
 * @return {MissionStats} The counts.
 */
export function missionStats(stored: unknown): MissionStats {
  const source = (stored && typeof stored === "object" ? stored : {}) as
    Record<string, unknown>;
  const stats = {} as MissionStats;
  for (const stat of MISSION_STATS) {
    const n = Math.floor(Number(source[stat]));
    stats[stat] = Number.isFinite(n) && n > 0 ? n : 0;
  }
  return stats;
}

/**
 * How far along a mission is, never past its target.
 * @param {Mission} mission The mission.
 * @param {MissionStats} stats The day's counts.
 * @return {number} Progress from 0 to the mission's target.
 */
export function missionProgress(
  mission: Mission, stats: MissionStats
): number {
  return Math.min(stats[mission.stat], mission.target);
}

/**
 * Whether every mission of [dateId] is done.
 * @param {string} dateId The day.
 * @param {MissionStats} stats That day's counts.
 * @return {boolean} True when the chest is due.
 */
export function allMissionsComplete(
  dateId: string, stats: MissionStats
): boolean {
  const missions = missionsForDate(dateId);
  return missions.length > 0 &&
    missions.every((m) => missionProgress(m, stats) >= m.target);
}

/**
 * What a finished solo level adds to the day's counts.
 * @param {number} correct Right answers in the level.
 * @param {number} total Questions in the level.
 * @param {number} longestStreak Its longest run of right answers.
 * @return {Partial<MissionStats>} The counts to add.
 */
export function soloLevelMissionStats(
  correct: number, total: number, longestStreak: number
): Partial<MissionStats> {
  const stats: Partial<MissionStats> = {soloLevels: 1};
  if (correct > 0) stats.correct = correct;
  if (total > 0 && correct / total >= GREAT_LEVEL_PERCENT) {
    stats.greatLevels = 1;
  }
  if (longestStreak >= STREAK_LEVEL_RUN) stats.streakLevels = 1;
  return stats;
}
