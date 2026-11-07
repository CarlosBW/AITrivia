/**
 * Turns what the model wrote into questions a level can use.
 *
 * Kept out of index.ts so it can be tested without firebase-admin or a
 * model call.
 */
import {
  buildAnswerOptions,
  fnv1a32,
  questionDedupeKey,
} from "./ai_question_bank";

/** A question as the model returns it, naming the correct answer. */
export interface ModelQuestionDraft {
  q: unknown;
  correctAnswer: unknown;
  wrongAnswers: unknown;
  explanation: unknown;
}

/** A question ready to bank, with its options laid out. */
export interface AcceptedQuestion {
  q: string;
  options: string[];
  answerIndex: number;
  explanation: string;
}

/**
 * The usable questions in [drafts], at most [needed] of them.
 *
 * A level used to be all or nothing: one malformed question, or 9 instead
 * of the 10 asked for, threw the whole batch away — and twice in a row
 * failed the player's topic. Now a malformed question or a repeat is
 * dropped on its own, and the caller asks again only for what is missing.
 * @param {ModelQuestionDraft[]} drafts What the model returned.
 * @param {string[]} kept Questions already accepted, not to be repeated.
 * @param {number} needed How many more are wanted.
 * @return {AcceptedQuestion[]} Up to [needed] new questions.
 */
export function acceptModelQuestions(
  drafts: ModelQuestionDraft[],
  kept: string[],
  needed: number
): AcceptedQuestion[] {
  const seen = new Set(kept.map(questionDedupeKey));
  const out: AcceptedQuestion[] = [];

  for (const draft of drafts) {
    if (out.length >= needed) break;
    if (typeof draft.q !== "string" || draft.q.trim() === "") continue;

    const key = questionDedupeKey(draft.q);
    if (seen.has(key)) continue;

    // Seeded by the question text so a question always lays out the same
    // way, while different questions land on different slots.
    const built = buildAnswerOptions(
      draft.correctAnswer, draft.wrongAnswers, fnv1a32(draft.q)
    );
    if (!built) continue;

    seen.add(key);
    out.push({
      q: draft.q,
      options: built.options,
      answerIndex: built.answerIndex,
      explanation: typeof draft.explanation === "string" ?
        draft.explanation : "",
    });
  }
  return out;
}
