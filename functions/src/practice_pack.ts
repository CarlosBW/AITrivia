/**
 * Pure helpers for the offline practice pack: which questions go in it,
 * what each one carries, and how often a player may ask for a new one.
 * Kept out of index.ts so the rules can be tested without Firestore.
 *
 * The pack is the one place answers leave the server, because a phone with
 * no connection has nobody to ask. That is why it is small, drawn at
 * random and rationed: enough to practise with, not a copy of the bank.
 * Nothing played from it earns anything.
 */

import {seededShuffleIndices} from "./ai_question_bank";
import {DailyPoolEntry} from "./daily_question_set";

/** Questions in one pack: ten rounds of ten. */
export const PRACTICE_PACK_SIZE = 100;

/** The least time between two packs for the same player. */
export const PRACTICE_PACK_MIN_INTERVAL_MS = 6 * 60 * 60 * 1000;

/**
 * Whether a player who last took a pack at [lastMs] may take another.
 * @param {number | null} lastMs When the last pack was handed out.
 * @param {number} nowMs Now.
 * @return {boolean} True when a new pack may be drawn.
 */
export function practicePackDue(lastMs: number | null, nowMs: number): boolean {
  if (lastMs === null || !Number.isFinite(lastMs)) return true;
  // A stamp from the future (a clock that moved) must not lock them out.
  if (lastMs > nowMs) return true;
  return nowMs - lastMs >= PRACTICE_PACK_MIN_INTERVAL_MS;
}

/**
 * The pack's questions, drawn at random from the whole index so every
 * category gets its share.
 * @param {DailyPoolEntry[]} entries Every question's location.
 * @param {number} seed Shuffle seed.
 * @param {number} size How many to take.
 * @return {DailyPoolEntry[]} The chosen entries, in pack order.
 */
export function selectPracticeEntries(
  entries: DailyPoolEntry[], seed: number, size = PRACTICE_PACK_SIZE
): DailyPoolEntry[] {
  return seededShuffleIndices(entries.length, seed)
    .slice(0, Math.max(0, size))
    .map((i) => entries[i]);
}

/** One question as the pack carries it. */
export interface PracticeQuestion {
  categoryId: string;
  q: string;
  options: string[];
  answerIndex: number;
  q_en?: string;
  options_en?: string[];
}

/**
 * A stored question as the pack carries it, or null when it can't be
 * played: no text, fewer than two options, or an answer that points
 * outside them. The English version only goes along when it lines up with
 * the Spanish one, option for option.
 * @param {unknown} data The question document.
 * @param {string} categoryId The category it came from.
 * @return {PracticeQuestion | null} The question, or null.
 */
export function practiceQuestion(
  data: unknown, categoryId: string
): PracticeQuestion | null {
  if (!data || typeof data !== "object") return null;
  const raw = data as Record<string, unknown>;

  const text = typeof raw.q === "string" ? raw.q.trim() : "";
  const options = strings(raw.options);
  const answerIndex = raw.answerIndex;

  if (!text || options.length < 2) return null;
  if (typeof answerIndex !== "number" || !Number.isInteger(answerIndex) ||
      answerIndex < 0 || answerIndex >= options.length) {
    return null;
  }

  const question: PracticeQuestion = {
    categoryId, q: text, options, answerIndex,
  };

  const textEn = typeof raw.q_en === "string" ? raw.q_en.trim() : "";
  const optionsEn = strings(raw.options_en);
  if (textEn && optionsEn.length === options.length) {
    question.q_en = textEn;
    question.options_en = optionsEn;
  }

  return question;
}

/**
 * The non-empty strings of a stored list, or none if any entry isn't one.
 * @param {unknown} value A stored options list.
 * @return {string[]} The options.
 */
function strings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const out = value.map((o) => (typeof o === "string" ? o.trim() : ""));
  return out.every((o) => o.length > 0) ? out : [];
}
