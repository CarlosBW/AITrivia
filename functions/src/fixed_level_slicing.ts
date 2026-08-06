/**
 * Pure level/pool arithmetic for fixed-category solo levels, backing
 * `loadFixedLevelQuestions` in index.ts. Kept in its own module (like
 * daily_challenge_dates.ts) so it can be unit-tested without pulling in
 * firebase-admin — nothing here touches Firestore or the clock.
 *
 * Two questions live here, and they have to agree: which difficulty pool a
 * level reads, and which slice of that pool is its own. They used to be
 * separate functions each repeating the band boundaries, with a comment
 * asking future readers to keep them in step. Both now derive from
 * [FIXED_LEVEL_BANDS], so a band can only be changed in one place.
 */

/** Questions served per fixed-category solo level. */
export const FIXED_LEVEL_QUESTION_COUNT = 10;

/**
 * The difficulty bands of the ten solo levels, in order.
 *
 * Pool sizes are sized to these bands: a band of N levels needs
 * N * FIXED_LEVEL_QUESTION_COUNT questions for its levels to get wholly
 * disjoint slates, which is where the 30/40/30 target per category comes
 * from.
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

/**
 * Where a level sits inside its difficulty band. Levels 1-3, 4-7 and 8-10
 * all draw from the same pool, so this is what tells them apart.
 * @param {number} levelNumber The solo level number (1-based).
 * @return {number} 0-based position of the level within its band.
 */
export function levelIndexInBand(levelNumber: number): number {
  return levelNumber - bandFor(levelNumber).firstLevel;
}

/**
 * Takes this level's slate out of a pool already shuffled for its band.
 *
 * Every level in a band shuffles the pool identically and then reads its
 * own consecutive window of it, so the bands' pool sizes (30/40/30 for
 * bands of 3/4/3 levels) hand each level ten questions none of its
 * siblings get. A pool smaller than the band needs wraps around instead of
 * running short — overlapping again, but only as much as it has to, and
 * never repeating a question inside one level since the window is at most
 * as long as the pool.
 * @param {number[]} order Shuffled pool positions.
 * @param {number} levelNumber Level being opened.
 * @return {number[]} Pool positions for this level, in order.
 */
export function sliceForLevel(
  order: number[], levelNumber: number
): number[] {
  const total = order.length;
  const count = Math.min(FIXED_LEVEL_QUESTION_COUNT, total);
  const start =
    (levelIndexInBand(levelNumber) * FIXED_LEVEL_QUESTION_COUNT) % total;

  const picked: number[] = [];
  for (let i = 0; i < count; i++) {
    picked.push(order[(start + i) % total]);
  }
  return picked;
}
