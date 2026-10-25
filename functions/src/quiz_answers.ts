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
 * What a session that outlives its submission should hold afterwards: the
 * same slate, with nothing banked.
 *
 * Banked answers belong to one run. A fixed-category session is kept after
 * it is submitted (its slate is deterministic, so there is nothing to
 * re-roll), and while it also kept the answers, reopening the level
 * resumed past the last question: the client submitted the same run again
 * without showing a question, which paid the replay XP on every reopen and
 * left a failed level impossible to replay.
 * @param {Record<string, unknown>} session The session doc as scored.
 * @return {Record<string, unknown>} The doc to store, without `answers`.
 */
export function sessionAfterSubmit(
  session: Record<string, unknown>
): Record<string, unknown> {
  const rest = {...session};
  delete rest.answers;
  delete rest.results;
  delete rest.runStartedAtMs;
  return rest;
}

/**
 * The fastest a run's answers may be banked: about one per second.
 *
 * Nobody reads a question and four options in less, and it is far below
 * any real player, so it only ever stops a script.
 */
export const MIN_MS_BETWEEN_BANKED_ANSWERS = 800;

/**
 * Whether a Solo session holds a run that may be submitted: at least one
 * answer banked since the last submission, and banked no faster than
 * [MIN_MS_BETWEEN_BANKED_ANSWERS] apart on average.
 *
 * A fixed-category session outlives its submission, so without this a
 * script could submit the same level in a loop — the answer key is
 * readable — and collect XP and question stats on every call. Now each
 * submission needs a new run, and a run takes real time to bank.
 * @param {Record<string, unknown>|undefined} banked The session's banked
 * `answers` map.
 * @param {number|undefined} runStartedAtMs When the run's first answer was
 * banked.
 * @param {number} nowMs The submission time.
 * @return {boolean} True if the run may be scored.
 */
export function isSoloRunSubmittable(
  banked: Record<string, unknown> | undefined,
  runStartedAtMs: number | undefined,
  nowMs: number
): boolean {
  const count = banked ? Object.keys(banked).length : 0;
  if (count === 0) return false;
  if (count === 1) return true;
  // Only the server stamps it, on a run's first banked answer: a missing
  // one is a session from before the clock existed, not a forged run.
  if (typeof runStartedAtMs !== "number") return true;
  return nowMs - runStartedAtMs >=
    (count - 1) * MIN_MS_BETWEEN_BANKED_ANSWERS;
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

/** One judged answer of a round, by question. */
export type JudgedAnswer = {questionId: string; correct: boolean};

/**
 * Scores a Weekly Topic round, counting each question once per week.
 *
 * Questions already in [used] — answered in an earlier round this week —
 * and repeats within the same round are skipped. Without that, one known
 * question submitted over and over reached the weekly completion reward.
 * @param {JudgedAnswer[]} judged The round's answers, already judged.
 * @param {Set<string>} used Question ids already counted this week.
 * @return {{correct: number, answered: number, questionIds: string[]}}
 * What the round adds.
 */
export function scoreNewAnswers(
  judged: JudgedAnswer[],
  used: Set<string>
): {correct: number; answered: number; questionIds: string[]} {
  const seen = new Set(used);
  const questionIds: string[] = [];
  let correct = 0;

  for (const answer of judged) {
    if (seen.has(answer.questionId)) continue;
    seen.add(answer.questionId);
    questionIds.push(answer.questionId);
    if (answer.correct) correct++;
  }

  return {correct, answered: questionIds.length, questionIds};
}

/**
 * How many answers a timed round started [elapsedMs] ago can honestly
 * hold: one per [MIN_MS_BETWEEN_BANKED_ANSWERS], at most [limit].
 *
 * The Daily Challenge clock runs on the device and its answer key is
 * readable, so without a server-side bound a script submitted every
 * question correct the moment the round opened.
 * @param {number} elapsedMs Time since the round's server start.
 * @param {number} limit The round's question count.
 * @return {number} The most answers to score.
 */
export function maxAnswersForElapsed(elapsedMs: number, limit: number): number {
  const byTime = Math.floor(Math.max(0, elapsedMs) /
    MIN_MS_BETWEEN_BANKED_ANSWERS) + 1;
  return Math.min(limit, byTime);
}
