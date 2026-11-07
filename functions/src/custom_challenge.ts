/**
 * Sizing for an async challenge on a player's custom topic, whose
 * questions are generated fresh for the match (see createAsyncPvpMatch).
 *
 * Kept out of index.ts so it can be tested without firebase-admin.
 */

/** Questions one unit of the `levels` AI meter pays for. */
const QUESTIONS_PER_BUDGET_UNIT = 10;

/**
 * How much of the player's daily custom-topic limit a challenge uses.
 *
 * The limit is metered in levels of ten questions, so a challenge is
 * charged by the same yardstick: up to ten questions is one level.
 * @param {number} questionCount Questions the challenge generates.
 * @return {number} Units of the `levels` meter, never less than one.
 */
export function customChallengeBudgetUnits(questionCount: number): number {
  return Math.max(1, Math.ceil(questionCount / QUESTIONS_PER_BUDGET_UNIT));
}

/**
 * The topic level whose difficulty matches a challenge difficulty.
 *
 * Generation states difficulty by level number (1-3 easy, 4-7 medium,
 * 8-10 hard); each challenge difficulty takes a level inside its band.
 * @param {number} difficulty Challenge difficulty, 1-3.
 * @return {number} Level number to generate at.
 */
export function customChallengeLevel(difficulty: number): number {
  if (difficulty === 1) return 2;
  if (difficulty === 3) return 9;
  return 5;
}
