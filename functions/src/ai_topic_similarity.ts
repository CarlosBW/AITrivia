/**
 * Pure helpers backing the "find an existing AI topic before generating a
 * new one" flow in index.ts. Kept in their own module (rather than inline
 * in the otherwise single-file Cloud Functions entry point) purely so they
 * can be unit-tested without pulling in firebase-admin/Anthropic — nothing
 * here touches Firestore, the network, or any Firebase SDK.
 */

/**
 * Removes diacritics so accent variants of the same word compare equal
 * ("Perú" and "Peru" are the same topic, not two).
 * @param {string} value Input string.
 * @return {string} The string with diacritics stripped.
 */
export function stripAccents(value: string): string {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "");
}

/**
 * Deterministic doc id for the shared content pool entry backing a given
 * title+language — collapsing accents/punctuation so trivial variations
 * still land on the same pool entry, maximizing reuse. Two independent
 * pool entries can exist for the same title in different languages, since
 * content is generated in the requester's own language.
 * @param {string} normalizedTitle Title run through `normalizeTopicTitle`.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {string} Deterministic `ai_topic_pool` doc id.
 */
export function aiTopicPoolId(
  normalizedTitle: string,
  languageCode: unknown
): string {
  const lang = languageCode === "en" ? "en" : "es";
  const slug = stripAccents(normalizedTitle)
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${lang}__${slug || "topic"}`;
}

/**
 * Levenshtein edit distance between two strings.
 * @param {string} a First string.
 * @param {string} b Second string.
 * @return {number} Edit distance.
 */
export function levenshteinDistance(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from(
    {length: m + 1}, () => new Array(n + 1).fill(0)
  );

  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1] ?
        dp[i - 1][j - 1] :
        1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }

  return dp[m][n];
}

/**
 * Jaccard similarity (intersection over union) of the two strings' word
 * sets — catches partial/reordered-word matches Levenshtein distance
 * misses (e.g. "movies marvel" vs "marvel movies").
 * @param {string} a First string.
 * @param {string} b Second string.
 * @return {number} 0-1 similarity.
 */
export function jaccardWordOverlap(a: string, b: string): number {
  const wordsA = new Set(a.split(" ").filter(Boolean));
  const wordsB = new Set(b.split(" ").filter(Boolean));
  if (wordsA.size === 0 && wordsB.size === 0) return 1;

  let intersection = 0;
  for (const w of wordsA) {
    if (wordsB.has(w)) intersection++;
  }

  const union = wordsA.size + wordsB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

// Below this length an edit-distance ratio is not a trustworthy signal:
// two completely unrelated short titles sit only one or two edits apart
// ("roma"/"rosa" scores 0.75, "cine"/"vino" scores 0.5), which would offer
// the player an unrelated topic to reuse. Short titles can still match
// through exact equality (after accent stripping) or word overlap.
export const AI_TOPIC_MIN_FUZZY_LENGTH = 8;

// Score a candidate must reach to be offered as a reusable match. Retune
// freely once there's real usage data to look at.
export const AI_TOPIC_SIMILARITY_THRESHOLD = 0.45;

/**
 * Combined 0-1 similarity between two normalized topic titles — the max of
 * character-level closeness (catches typos, only trusted once the titles
 * are long enough to be meaningful) and word overlap (catches
 * partial/reordered matches). Accent-insensitive; an identical pair always
 * scores 1.
 * @param {string} a First normalized title.
 * @param {string} b Second normalized title.
 * @return {number} 0-1 similarity.
 */
export function titleSimilarity(a: string, b: string): number {
  const cleanA = stripAccents(a);
  const cleanB = stripAccents(b);

  if (cleanA === cleanB) return 1;

  const maxLen = Math.max(cleanA.length, cleanB.length);
  const levenshteinRatio = maxLen < AI_TOPIC_MIN_FUZZY_LENGTH ?
    0 : 1 - levenshteinDistance(cleanA, cleanB) / maxLen;

  return Math.max(levenshteinRatio, jaccardWordOverlap(cleanA, cleanB));
}
