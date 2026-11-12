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

/** What answering one question does to the player's lives. */
export interface AnswerCharge {
  /** Not allowed: too little life for the entry, or out after a miss. */
  refused: boolean;
  newUnits: number;
  /** The level's entry was paid with this answer. */
  entryCharged: boolean;
  /** This (wrong) answer took life. */
  lifeLost: boolean;
}

/**
 * Charges one answer: the entry on the first answer of a paid run, then
 * the wrong-answer cost.
 *
 * Both used to be separate calls the client chose to make, so a modified
 * client simply didn't, and played without lives. Answering is judged on
 * the server now, and this is charged in the same step.
 *
 * Running out ends a run on a miss, not on the balance alone. The entry is
 * a whole life, so a player holding exactly one is at zero the moment they
 * pay it; refusing every answer at zero meant that life bought a single
 * question. At zero the run goes on until the first wrong answer — which
 * has nothing left to take — and only then is the next one refused, until
 * the player has life again.
 * @param {object} params The run and the answer.
 * @return {AnswerCharge} What to store and tell the player.
 */
export function answerCharge(params: {
  chargeEntry: boolean;
  lifeUnits: number;
  entryCost: number;
  wrongCost: number;
  gamesPlayed: number;
  graceLevels: number;
  /** The run's previous answer was wrong — see [lastBankedAnswerWrong]. */
  lastAnswerWrong: boolean;
  correct: boolean;
}): AnswerCharge {
  const held = Math.max(0, Math.floor(params.lifeUnits));
  const refused = {
    refused: true, newUnits: held, entryCharged: false, lifeLost: false,
  };

  if (params.chargeEntry && held < params.entryCost) return refused;
  if (!params.chargeEntry && held <= 0 && params.lastAnswerWrong) {
    return refused;
  }

  const afterEntry = params.chargeEntry ? held - params.entryCost : held;
  if (params.correct) {
    return {
      refused: false, newUnits: afterEntry,
      entryCharged: params.chargeEntry, lifeLost: false,
    };
  }

  const spend = resolveWrongAnswerSpend(
    afterEntry, params.wrongCost, params.gamesPlayed, params.graceLevels
  );
  return {
    refused: false, newUnits: spend.newUnits,
    entryCharged: params.chargeEntry, lifeLost: spend.lifeLost,
  };
}

/**
 * Whether the most recent answer banked in a run was wrong.
 *
 * Questions are answered in order, so the highest index banked is the
 * latest answer. Anything but a clear `correct: true` counts as a miss.
 * @param {unknown} results The session's `results` map, by question index.
 * @return {boolean} False when nothing has been banked yet.
 */
export function lastBankedAnswerWrong(results: unknown): boolean {
  if (results === null || typeof results !== "object") return false;

  const entries = Object.entries(results as Record<string, unknown>)
    .map(([index, verdict]) => ({index: Number(index), verdict}))
    .filter((entry) => Number.isInteger(entry.index));
  if (entries.length === 0) return false;

  const last = entries.reduce((a, b) => (b.index > a.index ? b : a));
  return (last.verdict as {correct?: unknown} | null)?.correct !== true;
}
