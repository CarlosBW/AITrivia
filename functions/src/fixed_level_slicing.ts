/**
 * Pure level/pool arithmetic for fixed-category solo levels, backing
 * `loadFixedLevelQuestions` in index.ts. Kept in its own module (like
 * daily_challenge_dates.ts) so it can be unit-tested without pulling in
 * firebase-admin — nothing here touches Firestore or the clock.
 *
 * Which difficulty pool a level reads, how big that pool should be, and
 * how a player's record of what they've seen in it moves forward — all
 * derived from [FIXED_LEVEL_BANDS], so a band can only be changed in one
 * place.
 */

/** Questions served per fixed-category solo level. */
export const FIXED_LEVEL_QUESTION_COUNT = 10;

/**
 * The difficulty bands of the ten solo levels, in order.
 *
 * Pool sizes follow these bands — see [fixedPoolTarget].
 */
export const FIXED_LEVEL_BANDS: ReadonlyArray<{
  difficulty: number;
  firstLevel: number;
  lastLevel: number;
}> = [
  {difficulty: 1, firstLevel: 1, lastLevel: 3},
  {difficulty: 2, firstLevel: 4, lastLevel: 7},
  {difficulty: 3, firstLevel: 8, lastLevel: 10},
];

/**
 * The band a level belongs to. Levels past the last band fall into it,
 * matching the original `levelNumber <= 7 ? ... : 3` shape.
 * @param {number} levelNumber The solo level number (1-based).
 * @return {object} The band that level reads from.
 */
function bandFor(levelNumber: number) {
  return (
    FIXED_LEVEL_BANDS.find((b) => levelNumber <= b.lastLevel) ??
    FIXED_LEVEL_BANDS[FIXED_LEVEL_BANDS.length - 1]
  );
}

/**
 * Which fixed-pool tier a solo level draws from — the client no longer has
 * a copy of this, question selection moved server-side.
 * @param {number} levelNumber The solo level number (1-based).
 * @return {number} The fixed-pool difficulty tier (1-3) for that level.
 */
export function difficultyForLevel(levelNumber: number): number {
  return bandFor(levelNumber).difficulty;
}

/** How many runs through a band's levels each pool can serve fresh. */
const FIXED_POOL_PASSES = 2;

/**
 * How many questions a difficulty's pool should hold: two runs through the
 * levels of its band (60/80/60), so a replay rotates in questions the
 * player hasn't seen instead of serving the same ten again. This is what
 * tools/seed_fill_pools.js fills each category to.
 * @param {number} difficulty Fixed-pool tier (1-3).
 * @return {number} Questions the pool should hold.
 */
export function fixedPoolTarget(difficulty: number): number {
  const band = FIXED_LEVEL_BANDS.find((b) => b.difficulty === difficulty) ??
    FIXED_LEVEL_BANDS[FIXED_LEVEL_BANDS.length - 1];
  const levels = band.lastLevel - band.firstLevel + 1;
  return levels * FIXED_LEVEL_QUESTION_COUNT * FIXED_POOL_PASSES;
}

/**
 * What a player has seen of a pool after one more level is drawn from it.
 *
 * Levels draw unseen questions first (selectSessionQuestions), so the first
 * pass through a band never repeats one and a replay brings in new ones.
 * Once the whole pool has been seen, a new round starts from the draw just
 * served, so the next level avoids exactly those ten rather than picking at
 * random from a pool that is all "seen". Ids no longer in the pool are
 * dropped, so a question deleted from it doesn't linger here.
 * @param {string[]} poolIds Ids currently in the pool.
 * @param {string[]} seenIds What the player had seen before this draw.
 * @param {string[]} drawnIds What this level serves.
 * @return {string[]} What to store as seen.
 */
export function nextSeenAfterDraw(
  poolIds: string[], seenIds: string[], drawnIds: string[]
): string[] {
  const inPool = new Set(poolIds);
  const seen = [...new Set([...seenIds, ...drawnIds])]
    .filter((id) => inPool.has(id));
  if (seen.length >= inPool.size) {
    return drawnIds.filter((id) => inPool.has(id));
  }
  return seen;
}
