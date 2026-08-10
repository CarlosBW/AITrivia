/**
 * Pure policy for what a wrong answer costs a player.
 *
 * Kept out of index.ts (like quiz_answers.ts) so the two rules that decide
 * it — the new-player grace window, and having nothing left to take — can
 * be unit-tested without firebase-admin or a clock.
 */

/** What a wrong answer does to a player's life balance. */
export interface WrongAnswerSpend {
  /** Units the player should be left with. */
  newUnits: number;
  /**
   * Whether anything was actually taken. This is what the client reports
   * to the player ("you lost half a life"), so it has to mean a real
   * deduction — not merely that a wrong answer happened.
   */
  lifeLost: boolean;
}

/**
 * Resolves one wrong answer against a player's life balance.
 *
 * A player already at zero loses nothing: there is nothing to take, and
 * they are about to be stopped by the no-lives gate anyway. Reporting a
 * loss there told them they had been charged for something that cost them
 * nothing — and `lifeLost` is also what suppresses the "no life lost"
 * message, so the one case where the reassurance matters most is the one
 * that never showed it.
 *
 * The grace window is the same idea from the other end: the first few
 * levels of a new account are free, so nothing is taken and nothing is
 * reported.
 * @param {number} lifeUnits Units the player currently holds.
 * @param {number} costUnits Units one wrong answer costs.
 * @param {number} gamesPlayed Levels this account has completed.
 * @param {number} graceLevels How many opening levels cost nothing.
 * @return {WrongAnswerSpend} New balance and whether it changed.
 */
export function resolveWrongAnswerSpend(
  lifeUnits: number,
  costUnits: number,
  gamesPlayed: number,
  graceLevels: number
): WrongAnswerSpend {
  const held = Math.max(0, Math.floor(lifeUnits));

  if (gamesPlayed < graceLevels) {
    return {newUnits: held, lifeLost: false};
  }

  // Clamped rather than allowed to go negative: a player holding less than
  // the full cost gives up what they have, which is still a real loss.
  const newUnits = Math.max(0, held - Math.max(0, costUnits));

  return {newUnits, lifeLost: newUnits < held};
}
