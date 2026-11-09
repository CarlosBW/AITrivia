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

/**
 * How long createAsyncPvpMatch may run for a custom topic: one generation,
 * plus a translation when the players read different languages. The app
 * waits a little longer (MatchService.customChallengeTimeout), so it never
 * gives up on a challenge the server goes on to create and charge for.
 */
export const CUSTOM_CHALLENGE_TIMEOUT_SECONDS = 240;

/**
 * Which language a challenge's questions are written in, following the
 * bank's convention: Spanish in `q`/`options` and English alongside in
 * `q_en`/`options_en`, which the app shows to English players.
 *
 * Two players on the same language get just that language — in `q`, which
 * the app shows when there is no English version. Mixed pairs get Spanish
 * plus a translation.
 * @param {unknown} challengerLanguage The challenger's languageCode.
 * @param {unknown} challengedLanguage The challenged's languageCode.
 * @return {object} `generateIn` ("es" or "en") and `addEnglish`.
 */
export function customChallengeLanguages(
  challengerLanguage: unknown,
  challengedLanguage: unknown
): {generateIn: "es" | "en"; addEnglish: boolean} {
  const challenger = challengerLanguage === "en" ? "en" : "es";
  const challenged = challengedLanguage === "en" ? "en" : "es";
  if (challenger === challenged) {
    return {generateIn: challenger, addEnglish: false};
  }
  return {generateIn: "es", addEnglish: true};
}

/**
 * [question] with its English version added, when [translation] is one the
 * app can use: text present and every option there, in the same order (the
 * answer's position is shared by both languages).
 * @param {T} question A Spanish question.
 * @param {object|undefined} translation Its English text and options.
 * @return {T} The question, with `q_en`/`options_en` if usable.
 */
export function withEnglishVersion<T extends {options: string[]}>(
  question: T,
  translation: {q?: unknown; options?: unknown} | undefined
): T | (T & {q_en: string; options_en: string[]}) {
  const q = typeof translation?.q === "string" ? translation.q.trim() : "";
  const options = Array.isArray(translation?.options) ?
    translation.options.map((option) => String(option).trim()) : [];

  if (!q || options.length !== question.options.length ||
      options.some((option) => !option)) {
    return question;
  }
  return {...question, q_en: q, options_en: options};
}
