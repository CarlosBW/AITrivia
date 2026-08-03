/**
 * Pure helpers backing the accumulating AI-topic question bank in
 * index.ts. Kept in their own module (like ai_topic_similarity.ts) purely
 * so they can be unit-tested without pulling in firebase-admin — nothing
 * here touches Firestore, the clock, or any Firebase SDK.
 *
 * The bank replaces the original fixed `q_1..q_10` per level. Levels now
 * accumulate questions (`q_11`, `q_12`, ...) as the topic is regenerated
 * or topped up, and each play draws a fresh slice the player hasn't seen.
 */

// Questions served in a single level attempt.
export const AI_QUESTIONS_PER_SESSION = 10;

// Most questions a single level's bank may accumulate. Not a storage
// limit (each question is its own document) — it bounds three real costs:
// every session start reads the whole level bank to filter it, the
// "don't repeat these" list sent to Claude grows with the bank, and a
// modified client that forces top-ups is spending real API money. Fifty
// is five full sessions of unique content per level, well past the point
// a player would realistically replay one.
export const AI_QUESTION_BANK_CAP = 50;

/**
 * Numeric suffix of a `q_N` question id, or -1 if it isn't one.
 *
 * Firestore returns documents ordered by id *lexicographically*, which
 * puts `q_10` between `q_1` and `q_2`. Sorting on this instead keeps a
 * level's questions in the order they were generated.
 * @param {string} questionId Question document id.
 * @return {number} The numeric suffix, or -1.
 */
export function questionIdIndex(questionId: string): number {
  const match = /^q_(\d+)$/.exec(questionId);
  return match ? Number(match[1]) : -1;
}

/**
 * Orders question ids by their numeric suffix (`q_2` before `q_10`).
 * Ids that don't match the `q_N` shape sort last, by raw id, so unknown
 * documents are still returned deterministically rather than dropped.
 * @param {string} a First question id.
 * @param {string} b Second question id.
 * @return {number} Comparator result.
 */
export function compareQuestionIds(a: string, b: string): number {
  const ai = questionIdIndex(a);
  const bi = questionIdIndex(b);
  if (ai === -1 && bi === -1) return a < b ? -1 : a > b ? 1 : 0;
  if (ai === -1) return 1;
  if (bi === -1) return -1;
  return ai - bi;
}

/**
 * The id to give the next question appended to a level's bank.
 *
 * Derived from the highest existing suffix rather than the document
 * count, so a deleted question never causes a new one to collide with a
 * surviving id.
 * @param {string[]} existingIds Ids already in the level.
 * @return {string} The next `q_N` id.
 */
export function nextQuestionId(existingIds: string[]): string {
  let max = 0;
  for (const id of existingIds) {
    const index = questionIdIndex(id);
    if (index > max) max = index;
  }
  return `q_${max + 1}`;
}

/**
 * Ids for a run of [count] questions appended to a level's bank.
 * @param {string[]} existingIds Ids already in the level.
 * @param {number} count How many new questions are being appended.
 * @return {string[]} Sequential `q_N` ids.
 */
export function nextQuestionIds(
  existingIds: string[],
  count: number
): string[] {
  const ids: string[] = [];
  const pool = [...existingIds];
  for (let i = 0; i < count; i++) {
    const id = nextQuestionId(pool);
    ids.push(id);
    pool.push(id);
  }
  return ids;
}

/**
 * How many questions a level's bank may still accept before hitting
 * [AI_QUESTION_BANK_CAP].
 * @param {number} currentSize Questions already in the level.
 * @return {number} Remaining headroom, never negative.
 */
export function bankHeadroom(currentSize: number): number {
  return Math.max(0, AI_QUESTION_BANK_CAP - currentSize);
}

/**
 * Deterministic 32-bit hash (FNV-1a), used to seed a shuffle from a
 * string. Used only for reproducible question selection, never for any
 * security property. Mirrors level_play_screen.dart's `_fnv1a32`.
 *
 * This is the single implementation for the whole backend — index.ts
 * imports it for fixed-pool shuffling too. It used to keep its own
 * byte-identical copy, which meant editing either one silently changed
 * which questions players got from the other.
 * @param {string} input String to hash.
 * @return {number} 32-bit unsigned hash.
 */
export function fnv1a32(input: string): number {
  const fnvPrime = 16777619;
  let hash = 2166136261;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, fnvPrime) >>> 0;
  }
  return hash >>> 0;
}

/**
 * Shuffled `0..length-1`, deterministic for a given seed (mulberry32 PRNG
 * + Fisher-Yates), so the same seed always picks the same subset in the
 * same order. Shared with index.ts's fixed-pool selection — see
 * [fnv1a32] on why there is only one copy.
 * @param {number} length How many indices to shuffle.
 * @param {number} seed Shuffle seed.
 * @return {number[]} Shuffled indices.
 */
export function seededShuffleIndices(length: number, seed: number): number[] {
  let a = seed;
  const rand = () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  const indices = Array.from({length}, (_, i) => i);
  for (let i = indices.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [indices[i], indices[j]] = [indices[j], indices[i]];
  }
  return indices;
}

/**
 * Orders and bounds the "don't repeat these" list for one generation call.
 *
 * The prompt truncates this list to a fixed budget, so *order decides what
 * survives*. [priority] (the target level's own questions) therefore goes
 * first: repeating a question inside a single level is the duplicate
 * players actually notice, and it's the likeliest one since the request is
 * for that same level. Plain truncation of a pool-wide list gets this
 * backwards — it keeps level 1's oldest questions and drops the ones the
 * batch is about to sit next to. The rest of the budget is filled
 * newest-first, since recent content is what a fresh batch tends to echo.
 * @param {string[]} priority Questions that must be avoided if anything is.
 * @param {string[]} rest Other questions to avoid, oldest to newest.
 * @param {number} max Ceiling on the returned list.
 * @return {string[]} Deduplicated list, at most [max] entries.
 */
export function capAvoidList(
  priority: string[],
  rest: string[],
  max: number
): string[] {
  const seen = new Set<string>();
  const out: string[] = [];

  const add = (question: string): boolean => {
    if (out.length >= max) return false;
    if (!question || seen.has(question)) return true;
    seen.add(question);
    out.push(question);
    return true;
  };

  for (const question of priority) {
    if (!add(question)) return out;
  }
  for (let i = rest.length - 1; i >= 0; i--) {
    if (!add(rest[i])) break;
  }

  return out;
}

export interface SessionDraw {
  /** Ids to serve, in the order they should be played. */
  questionIds: string[];
  /** Ids the player had already seen, included only to fill the slate. */
  repeatedIds: string[];
}

/**
 * Picks the questions for one level attempt.
 *
 * Unseen questions always come first: a replay should feel new. Only when
 * the bank can't cover a full slate does it fall back to repeats, chosen
 * at random rather than in id order so a player replaying an exhausted
 * level doesn't get the same filler every time. Generation is *not* done
 * here — the bank is topped up ahead of the player by
 * `ensureAiTopicLevelsGenerated`, so opening a level never waits on
 * Claude.
 * @param {string[]} availableIds Ids in the level, already filtered for
 * heavily-reported questions.
 * @param {Iterable<string>} seenIds Ids this player has been served
 * before for this topic.
 * @param {number} seed Shuffle seed.
 * @param {number} count How many questions to serve.
 * @return {SessionDraw} The chosen ids, and which of them are repeats.
 */
export function selectSessionQuestions(
  availableIds: string[],
  seenIds: Iterable<string>,
  seed: number,
  count: number = AI_QUESTIONS_PER_SESSION
): SessionDraw {
  const seen = new Set(seenIds);
  const ordered = [...availableIds].sort(compareQuestionIds);

  const unseen = ordered.filter((id) => !seen.has(id));
  const alreadySeen = ordered.filter((id) => seen.has(id));

  const pick = (ids: string[], take: number, salt: number): string[] => {
    if (take <= 0 || ids.length === 0) return [];
    if (ids.length <= take) return [...ids];
    const order = seededShuffleIndices(ids.length, (seed + salt) >>> 0);
    return order.slice(0, take).map((i) => ids[i]);
  };

  const fresh = pick(unseen, count, 0);
  const repeatedIds = pick(alreadySeen, count - fresh.length, 0x9e37);

  return {questionIds: [...fresh, ...repeatedIds], repeatedIds};
}
