/**
 * Pure rules for what `deleteMyAccount` (index.ts) does to data the
 * deleted player shares with others: which match fields get the neutral
 * name, which matches get closed, and where their leaderboard rows sit.
 *
 * Kept out of index.ts so they can be unit-tested without firebase-admin.
 */

import {parseDateId, weekIdForDateId} from "./daily_challenge_dates";

/**
 * The name a deleted player is shown under in someone else's data.
 * @param {unknown} languageCode The reader's `languageCode`.
 * @return {string} "Deleted player" in their language.
 */
export function deletedPlayerName(languageCode: unknown): string {
  return languageCode === "en" ? "Deleted player" : "Jugador eliminado";
}

/** What to write to one shared match, and whose it still is. */
export interface MatchScrub {
  /** The other player, or null if nobody else was in it. */
  opponentUid: string | null;
  /** Field updates; nested ones as dotted paths. */
  patch: Record<string, unknown>;
  /** Whether the patch also ends a match still in play. */
  closed: boolean;
}

/**
 * Anonymizes the deleted player's seat in a live match (`matches/{id}`).
 * The scores and answers stay: they're the opponent's result too.
 *
 * A match not yet settled is cancelled and marked rewarded, so
 * finalizePvpMatch can't settle it later — that would write coins and
 * stats into a fresh `users/{uid}` doc for the deleted player.
 * @param {unknown} match The match document's data.
 * @param {string} uid The deleted player.
 * @param {string} name What to show instead of their name.
 * @return {MatchScrub|null} The update, or null if they aren't in it.
 */
export function liveMatchScrub(
  match: unknown, uid: string, name: string
): MatchScrub | null {
  if (!match || typeof match !== "object") return null;
  const m = match as Record<string, unknown>;
  const hostUid = String(m.hostUid ?? "");
  const guestUid = String(m.guestUid ?? "");
  if (uid !== hostUid && uid !== guestUid) return null;

  const seat = `players.${uid}`;
  const patch: Record<string, unknown> = {
    [`${seat}.displayName`]: name,
    [`${seat}.avatarId`]: "avatar_1",
    [`${seat}.equippedFrame`]: "",
    [`${seat}.bestLeagueId`]: "",
  };

  const status = String(m.status ?? "");
  const closed = m.rewarded !== true &&
    status !== "finished" && status !== "cancelled";
  if (closed) {
    patch.status = "cancelled";
    patch.rewarded = true;
  }

  const opponentUid = uid === hostUid ? guestUid : hostUid;
  return {opponentUid: opponentUid || null, patch, closed};
}

/**
 * Anonymizes the deleted player's side of an async match
 * (`async_matches/{id}`).
 *
 * One still in play is declined on their behalf and marked rewarded, the
 * same end the forfeit sweep gives a declined match — otherwise that
 * sweep could hand the deleted player a forfeit win a week later.
 * @param {unknown} match The match document's data.
 * @param {string} uid The deleted player.
 * @param {string} name What to show instead of their name.
 * @return {MatchScrub|null} The update, or null if they aren't in it.
 */
export function asyncMatchScrub(
  match: unknown, uid: string, name: string
): MatchScrub | null {
  if (!match || typeof match !== "object") return null;
  const m = match as Record<string, unknown>;
  const challengerUid = String(m.challengerUid ?? "");
  const challengedUid = String(m.challengedUid ?? "");

  let role: "challenger" | "challenged";
  if (uid === challengerUid) {
    role = "challenger";
  } else if (uid === challengedUid) {
    role = "challenged";
  } else {
    return null;
  }

  const patch: Record<string, unknown> = {[`${role}DisplayName`]: name};

  const closed = m.rewarded !== true && m.status !== "declined";
  if (closed) {
    patch.status = "declined";
    patch.declinedByUid = uid;
    patch.rewarded = true;
  }

  const opponentUid = role === "challenger" ? challengedUid : challengerUid;
  return {opponentUid: opponentUid || null, patch, closed};
}

/**
 * Every leaderboard row a player can have, from the days they played the
 * daily challenge: one per day in `daily_leaderboards`, and one per week
 * in each league's `weekly_leagues` board — a week's league isn't
 * recorded anywhere that survives the account, so every league is tried.
 * @param {string} uid The deleted player.
 * @param {string[]} dateIds Their `daily_challenges` doc ids.
 * @param {string[]} leagueIds Every weekly league id.
 * @return {string[]} Document paths; most won't exist.
 */
export function leaderboardEntryPaths(
  uid: string, dateIds: string[], leagueIds: string[]
): string[] {
  const days = dateIds.filter((id) => !Number.isNaN(parseDateId(id)));
  const weeks = [...new Set(days.map(weekIdForDateId))];
  return [
    ...days.map((d) => `daily_leaderboards/${d}/players/${uid}`),
    ...weeks.flatMap((w) =>
      leagueIds.map((l) => `weekly_leagues/${w}/${l}/${uid}`)
    ),
  ];
}
