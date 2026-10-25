/**
 * Pure helpers for picking and ordering a Daily Challenge question set.
 * Kept out of index.ts (like ai_question_bank.ts) so the selection rules
 * can be unit-tested without Firestore, a clock, or a random source.
 */

/** One question's location in the fixed pools. */
export interface DailyPoolEntry {
  /** fixed_pools category id. */
  c: string;
  /** Difficulty tier (1-3). */
  d: number;
  /** Question document id. */
  q: string;
}

/**
 * Picks the day's entries out of an already-shuffled index.
 *
 * Questions served on recent days are pushed to the back rather than
 * dropped: on a small bank the fresh ones can't fill a set on their own,
 * and a short day is worse than a repeat.
 * @param {DailyPoolEntry[]} shuffled The whole index, already shuffled.
 * @param {Set<string>} excludeQuestionIds Ids served on recent days.
 * @param {number} limit How many questions the day should hold.
 * @return {DailyPoolEntry[]} The chosen entries, still in shuffled order.
 */
export function selectDailyEntries(
  shuffled: DailyPoolEntry[],
  excludeQuestionIds: Set<string>,
  limit: number
): DailyPoolEntry[] {
  const fresh: DailyPoolEntry[] = [];
  const recentlyUsed: DailyPoolEntry[] = [];

  for (const entry of shuffled) {
    if (excludeQuestionIds.has(entry.q)) recentlyUsed.push(entry);
    else fresh.push(entry);
  }

  const capped = Math.max(0, Math.min(limit, shuffled.length));
  const selected = fresh.slice(0, capped);

  if (selected.length < capped) {
    selected.push(...recentlyUsed.slice(0, capped - selected.length));
  }

  return selected;
}

/**
 * Orders a day's questions easy first, hardest last.
 *
 * The Daily Challenge is a fixed-length sprint, so what difficulty really
 * controls is how far a player gets in the time. Shuffling the tiers
 * together made that a lottery — one player's run front-loaded with tier 3
 * and another's with tier 1 were not the same test, even on the same set.
 * A rising curve gives everyone the same ramp and lets the strong player
 * reach the hard questions by getting further, which is the honest way to
 * make the day harder for them.
 *
 * The sort is stable, so within a tier the incoming (shuffled) order is
 * kept and the day-to-day mix still varies.
 * @param {DailyPoolEntry[]} entries The day's chosen entries.
 * @return {DailyPoolEntry[]} A new array ordered by ascending difficulty.
 */
export function orderByAscendingDifficulty(
  entries: DailyPoolEntry[]
): DailyPoolEntry[] {
  return [...entries].sort((a, b) => a.d - b.d);
}

/**
 * The index entries a PvP match can draw its questions from.
 *
 * Matches used to list a whole pool to keep ten questions — and "random"
 * listed one pool per question — when the index already says where every
 * question is. `null` means the index can't answer for this category: the
 * scan that built it stopped before covering it, and drawing from part of
 * a pool would skew every match in it, so the caller lists the pool.
 * @param {DailyPoolEntry[]} entries The question index.
 * @param {string[]} completeCategories Categories the index fully covers.
 * @param {string} categoryId The match's category, or "random".
 * @param {number} difficulty The match's difficulty tier.
 * @return {DailyPoolEntry[]|null} The candidates, or null to list the pool.
 */
export function matchCandidates(
  entries: DailyPoolEntry[],
  completeCategories: string[],
  categoryId: string,
  difficulty: number
): DailyPoolEntry[] | null {
  if (categoryId !== "random" && !completeCategories.includes(categoryId)) {
    return null;
  }
  const candidates = entries.filter((entry) =>
    entry.d === difficulty &&
    (categoryId === "random" || entry.c === categoryId)
  );
  return candidates.length > 0 ? candidates : null;
}
