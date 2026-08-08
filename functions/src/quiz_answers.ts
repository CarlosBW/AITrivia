/**
 * Pure helpers for reconciling the answers a quiz session has *banked*
 * with the ones a client reports when it submits. Kept in its own module
 * (like ai_question_bank.ts) so it can be unit-tested without
 * firebase-admin — nothing here touches Firestore or the clock.
 */

export interface RecordedAnswer {
  questionIndex: number;
  selectedIndex: number;
}

/**
 * A timed-out question. Stored like any other answer so the question is
 * closed for good; it can never match a real `answerIndex`, so it scores
 * as wrong exactly like an incorrect tap.
 */
export const TIMED_OUT_ANSWER = -1;

/**
 * The answers a session should be scored from: whatever was banked as the
 * player went, with anything missing filled in from the submission.
 *
 * Banked answers win on purpose. Solo levels used to be scored purely from
 * the list a client sent at the end, and nothing was written until then —
 * so backing out of a level discarded the run, and re-entering served the
 * same questions with a clean slate. A player could leave, look the
 * answers up, and come back. Now each answer is banked as it is given and
 * this makes the first one final: a replay can re-see a question but not
 * change what it scored.
 *
 * The submitted list still fills gaps rather than being ignored outright,
 * so a run whose per-answer writes failed (offline, a dropped call) is
 * scored on what the player actually did instead of silently losing it.
 * @param {Record<string, unknown>|undefined} banked The session's stored
 * `answers` map, keyed by question index.
 * @param {RecordedAnswer[]} submitted Answers sent with the submission.
 * @return {RecordedAnswer[]} Answers to score, ordered by question index.
 */
export function mergeRecordedAnswers(
  banked: Record<string, unknown> | undefined,
  submitted: RecordedAnswer[]
): RecordedAnswer[] {
  const byIndex = new Map<number, number>();

  for (const answer of submitted) {
    if (answer.questionIndex < 0) continue;
    if (byIndex.has(answer.questionIndex)) continue;
    byIndex.set(answer.questionIndex, answer.selectedIndex);
  }

  if (banked && typeof banked === "object") {
    for (const [key, value] of Object.entries(banked)) {
      const questionIndex = Number(key);
      if (!Number.isInteger(questionIndex) || questionIndex < 0) continue;
      if (typeof value !== "number" || !Number.isInteger(value)) continue;
      byIndex.set(questionIndex, value);
    }
  }

  return [...byIndex.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([questionIndex, selectedIndex]) => ({questionIndex, selectedIndex}));
}

/**
 * Where a player should resume a session they left: the question after the
 * deepest one already banked.
 *
 * Derived from the highest index rather than the count so a gap left by a
 * failed write can't drop the player back into questions they already
 * answered — those are locked anyway, replaying them would just be
 * confusing.
 * @param {Record<string, unknown>|undefined} banked The session's stored
 * `answers` map, keyed by question index.
 * @return {number} Index of the question to show next, 0 for a fresh run.
 */
export function resumeIndexFromBanked(
  banked: Record<string, unknown> | undefined
): number {
  if (!banked || typeof banked !== "object") return 0;

  let deepest = -1;
  for (const key of Object.keys(banked)) {
    const questionIndex = Number(key);
    if (!Number.isInteger(questionIndex) || questionIndex < 0) continue;
    if (questionIndex > deepest) deepest = questionIndex;
  }

  return deepest + 1;
}
