/**
 * Pure rules for players reporting a bad question from the end-of-level
 * review (see `reportQuestion` in index.ts).
 *
 * Kept out of index.ts so the shape checks and the daily cap can be
 * unit-tested without firebase-admin.
 */

/** Reasons a player can give; the review screen offers exactly these. */
export const QUESTION_REPORT_REASONS = new Set([
  "wrong_answer",
  "confusing",
  "typo",
  "inappropriate",
  "other",
]);

/** Reports one player can file per day — enough for honest use. */
export const MAX_QUESTION_REPORTS_PER_DAY = 30;

const DETAILS_MAX_LENGTH = 500;

/** A question as the player saw it, plus whatever else it carried. */
export interface ReportedQuestion {
  q: string;
  options: string[];
  answerIndex: number;
  raw: Record<string, unknown>;
}

/**
 * The question at [index] of a stored question list, or null if there is
 * no well-formed question there.
 * @param {unknown} questions A session's `questions` field.
 * @param {number} index Position the player reported.
 * @return {ReportedQuestion|null} The question, or null.
 */
export function questionAt(
  questions: unknown, index: number
): ReportedQuestion | null {
  if (!Array.isArray(questions) || !Number.isInteger(index)) return null;
  if (index < 0 || index >= questions.length) return null;

  const raw = questions[index];
  if (!raw || typeof raw !== "object") return null;
  const data = raw as Record<string, unknown>;

  const q = String(data.q ?? "").trim();
  const options = Array.isArray(data.options) ?
    data.options.map((o) => String(o)) : [];
  const answerIndex = Number(data.answerIndex);

  if (!q || options.length === 0) return null;
  if (!Number.isInteger(answerIndex) ||
      answerIndex < 0 || answerIndex >= options.length) {
    return null;
  }

  return {q, options, answerIndex, raw: data};
}

/**
 * The player's comment, trimmed and capped.
 * @param {unknown} raw What the client sent.
 * @return {string} The comment, possibly empty.
 */
export function cleanReportDetails(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw.trim().slice(0, DETAILS_MAX_LENGTH);
}

/**
 * Report doc id for a fixed-bank question: one per player and question, so
 * reporting it again updates the first report instead of adding another.
 * @param {string} uid Reporter.
 * @param {string} categoryId Pool category.
 * @param {number} difficulty Pool difficulty.
 * @param {string} docId Question doc id in the pool.
 * @return {string} Firestore doc id.
 */
export function fixedReportDocId(
  uid: string, categoryId: string, difficulty: number, docId: string
): string {
  return `${uid}__${categoryId}__d${difficulty}__${docId}`;
}

/**
 * Whether one more report fits in today's allowance, and the counter to
 * store if it does.
 * @param {object|undefined} state The stored counter, if any.
 * @param {string} todayId Today's date id.
 * @param {number} max Reports allowed per day.
 * @return {object} `allowed`, and the counter after this report.
 */
export function reportQuotaAfter(
  state: {dayId?: unknown; count?: unknown} | undefined,
  todayId: string,
  max: number
): {allowed: boolean; next: {dayId: string; count: number}} {
  const sameDay = state?.dayId === todayId;
  const used = sameDay ? Math.max(0, Math.floor(Number(state?.count) || 0)) : 0;

  if (used >= max) {
    return {allowed: false, next: {dayId: todayId, count: used}};
  }
  return {allowed: true, next: {dayId: todayId, count: used + 1}};
}
