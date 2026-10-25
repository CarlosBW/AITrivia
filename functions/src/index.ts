import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError, FunctionsErrorCode} from
  "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import * as crypto from "crypto";
import {
  aiTopicPoolId,
  titleSimilarity,
  AI_TOPIC_SIMILARITY_THRESHOLD,
} from "./ai_topic_similarity";
import {
  PvpLeagueInfo,
  DEFAULT_RATING,
  RATING_FLOOR,
  RATING_CEILING,
  leagueForRating,
  bestLeaguePatch,
  calculateRatings,
  disconnectWinRating,
} from "./pvp_rating";
import {
  levelForXp,
  calculateLevelRewards,
  calculateDailyCoinsEarned,
  calculateDailyXpEarned,
  calculateDailyScore,
  calculateDailyStreakBonusCoins,
} from "./rewards";
import {
  dailySubmissionCheck,
  dateIdInTimeZone,
  isPlausibleDateId,
  isStreakAtRisk,
  isWeekClaimable,
  loginStreakStep,
  previousDateId,
  weekIdForDateId,
} from "./daily_challenge_dates";
import {
  AI_QUESTIONS_PER_SESSION,
  avoidListCapacity,
  bankHeadroom,
  buildAnswerOptions,
  capAvoidList,
  compareQuestionIds,
  fnv1a32,
  interleaveByLevel,
  nextQuestionIds,
  questionDedupeKey,
  seededShuffleIndices,
  selectSessionQuestions,
} from "./ai_question_bank";
import {
  TIMED_OUT_ANSWER,
  isSoloRunSubmittable,
  maxAnswersForElapsed,
  mergeRecordedAnswers,
  scoreNewAnswers,
  sessionAfterSubmit,
} from "./quiz_answers";
import {
  decideCoinCredit,
  judgePlayProductPurchase,
  playProductPurchaseUrl,
  purchaseLedgerId,
} from "./coin_purchases";
import {
  openTurn,
  resolveAnswer,
} from "./async_pvp_turns";
import {answerCharge} from "./life_costs";
import {
  MAX_QUESTION_REPORTS_PER_DAY,
  QUESTION_REPORT_REASONS,
  ReportedQuestion,
  cleanReportDetails,
  fixedReportDocId,
  questionAt,
  reportQuotaAfter,
} from "./question_reports";
import {
  isOpponentUnresponsive,
  mergeAnswerKey,
  splitAnswerKey,
} from "./pvp_answer_key";
import {
  DailyPoolEntry,
  matchCandidates,
  orderByAscendingDifficulty,
  selectDailyEntries,
} from "./daily_question_set";
import {
  AI_METER_CAPS,
  AiMeter,
  checkAiBudget,
} from "./ai_budget";
import {
  difficultyForLevel,
  sliceForLevel,
} from "./fixed_level_slicing";

// How much of each question the "don't repeat these" list sent to Claude
// carries: enough to recognise the question, not its whole wording.
const AI_AVOID_LIST_MAX_CHARS = 120;

setGlobalOptions({maxInstances: 10});

admin.initializeApp();

const db = admin.firestore();

// Set via `firebase functions:secrets:set ANTHROPIC_API_KEY`. Only bound to
// the callables that actually call Claude (see their `secrets:` option).
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const AI_SECRETS = [anthropicApiKey];

/**
 * Cloud Functions run with no client context, so notification text sent to
 * a given user must be picked from their own stored `languageCode` field
 * (lib/services/locale_controller.dart writes it on every locale change;
 * lib/features/auth/user_bootstrap.dart seeds it on first launch) rather
 * than any notion of "current locale" — there isn't one here.
 * @param {unknown} languageCode The recipient's stored `languageCode`.
 * @param {string} es Spanish text.
 * @param {string} en English text.
 * @return {string} `en` if languageCode is `"en"`, otherwise `es`.
 */
function pickText(languageCode: unknown, es: string, en: string): string {
  return languageCode === "en" ? en : es;
}

/**
 * A client-sent id that will become part of a document path, or "" if it
 * can't be one. "/" would change the path's depth, "." and ".." aren't
 * valid ids, and an over-long id fails the write; "" lets each callable's
 * own "missing id" check reject it as a bad request instead of an
 * INTERNAL error.
 * @param {unknown} raw What the client sent.
 * @return {string} The id, or "".
 */
function cleanDocId(raw: unknown): string {
  const id = typeof raw === "string" ? raw.trim() : "";
  if (!id || id.includes("/") || id === "." || id === ".." ||
      id.length > 200) {
    return "";
  }
  return id;
}

/**
 * A document id from a callable's input. `doc("")` throws on its own, and
 * that surfaced as a bare INTERNAL error instead of a bad request.
 * @param {unknown} raw What the client sent.
 * @return {string} The id.
 */
function requiredDocId(raw: unknown): string {
  const id = typeof raw === "string" ? raw.trim() : "";
  if (!id || id.includes("/")) {
    throw new HttpsError("invalid-argument", "Missing or invalid id.");
  }
  return id;
}

/**
 * Builds an HttpsError whose message is in the caller's own language.
 *
 * A callable's error message is surfaced verbatim to the player (the
 * client shows `e.message` — see ai_topic_service.dart), so a hardcoded
 * string here bypasses the app's l10n entirely and shows every player the
 * same language regardless of their setting. Use this for errors a player
 * can actually trigger through normal play (not enough coins, topic
 * already exists, cooldown still active...). Guard rails for impossible
 * client states ("Missing matchId", "Match not found") stay in plain
 * English — a player never sees them, and localizing them would cost a
 * read on paths that should stay cheap.
 * @param {unknown} languageCode The caller's stored `languageCode`.
 * @param {FunctionsErrorCode} code Callable error code.
 * @param {string} es Spanish message.
 * @param {string} en English message.
 * @return {HttpsError} Error carrying the language-matched message.
 */
function localizedError(
  languageCode: unknown,
  code: FunctionsErrorCode,
  es: string,
  en: string
): HttpsError {
  // `localized` tells the app this message was written for the player;
  // it shows only those, and its own text for anything else.
  return new HttpsError(
    code, pickText(languageCode, es, en), {localized: true}
  );
}

/**
 * [localizedError] for call sites that don't already hold the caller's
 * user doc. The extra read only ever happens on the throwing path, so the
 * happy path stays exactly as cheap as before.
 * @param {string} uid Caller's uid.
 * @param {FunctionsErrorCode} code Callable error code.
 * @param {string} es Spanish message.
 * @param {string} en English message.
 * @return {Promise<HttpsError>} Error carrying the language-matched message.
 */
async function localizedErrorFor(
  uid: string,
  code: FunctionsErrorCode,
  es: string,
  en: string
): Promise<HttpsError> {
  let languageCode: unknown;
  try {
    const snap = await db.collection("users").doc(uid).get();
    languageCode = snap.data()?.languageCode;
  } catch (_) {
    // Never let the language lookup mask the error we're reporting.
  }
  return localizedError(languageCode, code, es, en);
}

// Mirrors the achievement*Title keys in lib/l10n/app_es.arb / app_en.arb —
// keep in sync.
const ACHIEVEMENT_TITLES: Record<string, {es: string; en: string}> = {
  first_pvp_win: {es: "Primera victoria en duelo", en: "First Duel Win"},
  pvp_wins_10: {es: "Duelista", en: "Duelist"},
  pvp_wins_25: {es: "Veterano de duelos", en: "Duel Veteran"},
  pvp_streak_5: {es: "En racha", en: "On Fire"},
  solo_levels_10: {es: "Explorador solitario", en: "Solo Explorer"},
  solo_levels_25: {es: "Maestro solitario", en: "Solo Master"},
  daily_streak_7: {es: "Hábito semanal", en: "Weekly Habit"},
  daily_streak_21: {es: "Constancia de hierro", en: "Iron Consistency"},
  friends_5: {es: "Jugador social", en: "Social Player"},
  friends_10: {es: "Círculo social", en: "Social Circle"},
  weekly_topics_completed_3: {es: "Explorador semanal", en: "Weekly Explorer"},
  categories_explored_5: {es: "Mente curiosa", en: "Curious Mind"},
};


// Max coins a match can pay its winner. Matches firestore.rules'
// isSanctionedWinReward (only winReward == 2 is ever allowed to be
// created/joined) — the UI itself only ever creates matches with
// EconomyService.defaultPvpWinReward (2), no stake picker exists. A
// modified client can still store any winReward it likes on the match doc
// before finishing it, so this is clamped server-side rather than
// trusted, but it should reflect the real current ceiling, not a wider
// one that gives a false sense of the actual sanctioned range.
const MAX_WIN_REWARD = 2;

// Mirrors match_service.dart's ranked-disconnect constants exactly.
const RANKED_DISCONNECT_WINNER_BONUS = 12;
const RANKED_ABANDON_RATING_PENALTY = 32;
const RANKED_ABANDON_COOLDOWN_MINUTES = 5;


/**
 * Safely converts a value to integer.
 * @param {unknown} value Value to convert.
 * @param {number} fallback Default value.
 * @return {number} Parsed integer.
 */
function safeInt(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

/**
 * Clamps a client-supplied win reward against the max the UI ever offers.
 * @param {number} value Raw stored winReward.
 * @return {number} Clamped, non-negative reward.
 */
function clampWinReward(value: number): number {
  return Math.max(0, Math.min(MAX_WIN_REWARD, value));
}

/**
 * Where a PvP match keeps its answer key: a doc the rules never let a
 * client read. See pvp_answer_key.ts for why it left the match doc.
 * @param {FirebaseFirestore.DocumentReference} matchRef A `matches` or
 * `async_matches` doc.
 * @return {FirebaseFirestore.DocumentReference} Its key doc.
 */
function answerKeyRef(
  matchRef: FirebaseFirestore.DocumentReference
): FirebaseFirestore.DocumentReference {
  return matchRef.collection("secret").doc("answers");
}

/**
 * A match's questions with their answers back on, for scoring. Matches
 * created before the key moved out still carry it inline and are read as
 * they are. Pass the transaction when inside one: its reads have to come
 * before any of its writes.
 * @param {FirebaseFirestore.DocumentReference} matchRef The match.
 * @param {FirebaseFirestore.DocumentData} data The match doc.
 * @param {FirebaseFirestore.Transaction} [tx] The running transaction.
 * @return {Promise<Record<string, unknown>[]>} Questions with answerIndex.
 */
async function keyedQuestions(
  matchRef: FirebaseFirestore.DocumentReference,
  data: FirebaseFirestore.DocumentData,
  tx?: FirebaseFirestore.Transaction
): Promise<Record<string, unknown>[]> {
  const questions = data.questions;
  const inline = Array.isArray(questions) && questions.some(
    (q) => typeof (q as Record<string, unknown>)?.answerIndex === "number"
  );
  if (inline) return mergeAnswerKey(questions, undefined);

  const keyRef = answerKeyRef(matchRef);
  const keySnap = tx ? await tx.get(keyRef) : await keyRef.get();
  return mergeAnswerKey(questions, keySnap.data()?.answerIndices);
}

/**
 * The answer key of already-keyed questions, as published on a finished
 * match so the players can review it.
 * @param {Record<string, unknown>[]} questions Output of keyedQuestions.
 * @return {number[]} Each question's answer index.
 */
function answerIndicesOf(questions: Record<string, unknown>[]): number[] {
  return questions.map((q) => safeInt(q.answerIndex, -1));
}

/**
 * Recomputes a PvP player's real score from their banked answers against
 * the match's questions with the key put back on (see keyedQuestions):
 * a question counts only if the banked option is its answerIndex. The
 * `score` a player sees during play is written by the server from this
 * same function.
 * @param {unknown} questions Questions carrying `answerIndex`.
 * @param {unknown} answers The player's banked answers map.
 * @return {number} The verified number of correct answers.
 */
function computeVerifiedPvpScore(questions: unknown, answers: unknown): number {
  if (!Array.isArray(questions)) return 0;

  const answerMap = (answers && typeof answers === "object") ?
    answers as Record<string, unknown> : {};

  let score = 0;
  for (let i = 0; i < questions.length; i++) {
    const correctIndex = safeInt(
      (questions[i] as Record<string, unknown> | undefined)?.answerIndex, -1
    );
    const selected = answerMap[String(i)];
    if (selected === undefined) continue;
    if (safeInt(selected, -2) === correctIndex) score++;
  }
  return score;
}

/**
 * Question-count avatar unlocks (100/1000 answered) are granted here rather
 * than by a client-side follow-up write, since `unlockedAvatars` is locked
 * against direct client writes in firestore.rules. Shared across every path
 * that increments correctAnswers/wrongAnswers (Daily Challenge, Solo, live
 * and async PvP) so the threshold reflects answers across all game modes,
 * not just whichever mode happens to compute it.
 * @param {unknown} existingUnlockedAvatars The user doc's current
 * `unlockedAvatars` array.
 * @param {number} totalQuestionsAnswered Correct + wrong answers so far,
 * including this update.
 * @return {Record<string, unknown>} Firestore patch fields to merge into
 * the user doc, or `{}` if nothing newly unlocked.
 */
function questionCountAvatarUnlockPatch(
  existingUnlockedAvatars: unknown, totalQuestionsAnswered: number
): Record<string, unknown> {
  const owned: string[] = Array.isArray(existingUnlockedAvatars) ?
    existingUnlockedAvatars.map((v) => String(v)) : [];

  const newlyUnlockedAvatarIds: string[] = [];
  if (
    totalQuestionsAnswered >= 100 &&
    !owned.includes("achievement_100_questions")
  ) {
    newlyUnlockedAvatarIds.push("achievement_100_questions");
  }
  if (
    totalQuestionsAnswered >= 1000 &&
    !owned.includes("achievement_1000_questions")
  ) {
    newlyUnlockedAvatarIds.push("achievement_1000_questions");
  }

  if (newlyUnlockedAvatarIds.length === 0) return {};

  const latestUnlockedAvatarId =
    newlyUnlockedAvatarIds[newlyUnlockedAvatarIds.length - 1];

  return {
    unlockedAvatars: admin.firestore.FieldValue.arrayUnion(
      ...newlyUnlockedAvatarIds
    ),
    lastUnlockedAvatarId: latestUnlockedAvatarId,
    lastUnlockedAvatarReason:
      latestUnlockedAvatarId === "achievement_1000_questions" ?
        "Answered 1000 questions" : "Answered 100 questions",
    lastUnlockedAvatarAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

// Shared daily cap on coins earned from PvP wins (live + async combined).
// Kept as defense in depth even after finalizePvpMatch/finalizeAsyncPvpMatch
// started recomputing verified scores server-side — it still bounds the
// worst-case from match count abuse or two colluding real accounts
// win-trading, neither of which a per-match score check can catch.
const MAX_DAILY_PVP_COINS = 20;

/**
 * Server-side YYYY-MM-DD bucket key (Cloud Functions clock, never
 * client-supplied) used to rate-limit PvP coin payouts per day.
 * @return {string} Today's date id.
 */
function serverDateId(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}` +
    `-${String(now.getDate()).padStart(2, "0")}`;
}

/**
 * Rejects a client-supplied `dateId` that isn't a real date close enough
 * to the server's own to have come from a real device — see
 * `isPlausibleDateId` for why the window exists and what it prevents.
 *
 * In the player's language and pointing at the cause: a phone whose date
 * is off by more than a day can't play the Daily at all, and a generic
 * error gave them nothing to fix.
 * @param {string} uid The caller.
 * @param {string} dateId Client-supplied date id.
 * @return {Promise<void>} Resolves if the date is plausible.
 */
async function assertPlausibleDateId(
  uid: string, dateId: string
): Promise<void> {
  if (!isPlausibleDateId(dateId, serverDateId())) {
    throw await wrongDeviceDateError(uid);
  }
}

/**
 * The error for a device whose date is too far from the server's.
 * @param {string} uid The caller.
 * @return {Promise<HttpsError>} The localized error.
 */
function wrongDeviceDateError(uid: string): Promise<HttpsError> {
  return localizedErrorFor(
    uid, "invalid-argument",
    "La fecha de tu teléfono no coincide con la de hoy. Activa la fecha y " +
      "hora automáticas e inténtalo de nuevo.",
    "Your phone's date doesn't match today's. Turn on automatic date and " +
      "time and try again."
  );
}

/**
 * The error for a level with no questions to serve right now.
 * @param {string} uid The caller.
 * @return {Promise<HttpsError>} The localized error.
 */
function noLevelQuestionsError(uid: string): Promise<HttpsError> {
  return localizedErrorFor(
    uid, "not-found",
    "Este nivel no tiene preguntas disponibles ahora. Inténtalo más tarde.",
    "This level has no questions available right now. Please try later."
  );
}

/**
 * Clamps how many of `rawCoins` a player may actually be paid right now
 * against their shared daily PvP coin cap, resetting the bucket if the
 * server date has rolled over since their last payout.
 * @param {Record<string, unknown>} userData Current user doc data.
 * @param {number} rawCoins Coins this win would otherwise pay out.
 * @return {{payable: number, patch: Record<string, unknown>}} Payable
 *   amount and the user-doc fields to persist the updated bucket.
 */
function clampDailyPvpCoins(
  userData: Record<string, unknown>,
  rawCoins: number
): {payable: number; patch: Record<string, unknown>} {
  if (rawCoins <= 0) return {payable: 0, patch: {}};

  const today = serverDateId();
  const sameDay = userData.pvpCoinsDate === today;
  const earnedSoFar = sameDay ? safeInt(userData.pvpCoinsToday, 0) : 0;

  const payable = Math.max(
    0, Math.min(rawCoins, MAX_DAILY_PVP_COINS - earnedSoFar)
  );

  return {
    payable,
    patch: {
      pvpCoinsToday: earnedSoFar + payable,
      pvpCoinsDate: today,
    },
  };
}


/**
 * Returns match result for a specific user.
 * @param {string} userId User identifier.
 * @param {string|null} winnerUid Winner identifier.
 * @return {string} victory, defeat or draw.
 */
function resultFor(userId: string, winnerUid: string | null): string {
  if (winnerUid === null) return "draw";
  return winnerUid === userId ? "victory" : "defeat";
}

/**
 * Mirrors lib/services/weekly_league_service.dart's `currentWeekId` —
 * the Monday of the current week, as yyyy-MM-dd. Used both as a
 * `weekly_leagues`/`weekly_participation` bucket key and as the weekly
 * "season" id in season_service.dart.
 * @return {string} Week id.
 */
function currentWeekId(): string {
  const now = new Date();
  const jsDay = now.getDay(); // 0=Sun..6=Sat
  const dartWeekday = jsDay === 0 ? 7 : jsDay; // 1=Mon..7=Sun
  const monday = new Date(now);
  monday.setDate(now.getDate() - (dartWeekday - 1));

  const y = monday.getFullYear();
  const m = String(monday.getMonth() + 1).padStart(2, "0");
  const d = String(monday.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Computes the current PvP season id/start/end for "now", mirroring
 * lib/services/pvp_season_service.dart's `currentSeason()` (calendar-month
 * seasons).
 * @return {{id:string, start:Date, end:Date}} Season info.
 */
function currentPvpSeason(): {id: string; start: Date; end: Date} {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const id = `pvp_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(
    2,
    "0"
  )}`;

  return {id, start, end};
}

/**
 * Mirrors match_service.dart's `_queuePvpSeasonStatsWrite` — updates the
 * player's current-season stats doc and the "season best" fields on their
 * user doc. Ranked-match-only; never called for casual matches.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef Player's user doc ref.
 * @param {Record<string, unknown>} userData Player's user doc data (as read
 * earlier in the same transaction).
 * @param {number} oldRating Rating before this match.
 * @param {number} newRating Rating after this match.
 * @param {boolean} won Whether this player won.
 * @param {boolean} lost Whether this player lost.
 * @param {boolean} draw Whether this match was a draw.
 */
function queuePvpSeasonStatsWrite(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: Record<string, unknown>,
  oldRating: number,
  newRating: number,
  won: boolean,
  lost: boolean,
  draw: boolean
): void {
  const season = currentPvpSeason();

  const sameSeason = String(userData.currentPvpSeasonId || "") === season.id;

  const previousBest = sameSeason ?
    safeInt(userData.pvpSeasonBestRating, oldRating) :
    oldRating;

  const bestRating = Math.max(previousBest, oldRating, newRating);

  const finalLeague = leagueForRating(newRating);
  const bestLeague = leagueForRating(bestRating);

  const statsRef = userRef.collection("pvp_season_stats").doc(season.id);

  tx.set(
    statsRef,
    {
      seasonId: season.id,
      seasonStart: admin.firestore.Timestamp.fromDate(season.start),
      seasonEnd: admin.firestore.Timestamp.fromDate(season.end),
      finalRating: newRating,
      finalLeagueId: finalLeague.id,
      finalLeagueName: finalLeague.name,
      finalLeagueEmoji: finalLeague.emoji,
      bestRating: bestRating,
      bestLeagueId: bestLeague.id,
      bestLeagueName: bestLeague.name,
      bestLeagueEmoji: bestLeague.emoji,
      matchesPlayed: admin.firestore.FieldValue.increment(1),
      ...(won ? {wins: admin.firestore.FieldValue.increment(1)} : {}),
      ...(lost ? {losses: admin.firestore.FieldValue.increment(1)} : {}),
      ...(draw ? {draws: admin.firestore.FieldValue.increment(1)} : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  tx.set(
    userRef,
    {
      currentPvpSeasonId: season.id,
      pvpSeasonBestRating: bestRating,
      pvpSeasonBestLeagueId: bestLeague.id,
      pvpSeasonBestLeagueName: bestLeague.name,
      ...bestLeaguePatch(userData, bestLeague),
      pvpSeasonFinalRating: newRating,
      pvpSeasonFinalLeagueId: finalLeague.id,
      pvpSeasonFinalLeagueName: finalLeague.name,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

type PvpAchievementDef = {
  id: string;
  title: string;
  target: number;
};

// Mirrors the PvP-related entries in lib/services/achievement_service.dart's
// `achievements` list. Keep these two in sync.
const PVP_ACHIEVEMENTS: PvpAchievementDef[] = [
  {id: "first_pvp_win", title: "First Duel Win", target: 1},
  {id: "pvp_wins_10", title: "Duelist", target: 10},
  {id: "pvp_streak_5", title: "On Fire", target: 5},
  {id: "pvp_wins_25", title: "Duel Veteran", target: 25},
];

/**
 * Reads a player's PvP-related achievement docs inside a transaction.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {string} uid Player id.
 * @return {Promise<FirebaseFirestore.DocumentSnapshot[]>} Snapshots, in
 * PVP_ACHIEVEMENTS order.
 */
async function readPvpAchievementSnaps(
  tx: FirebaseFirestore.Transaction,
  uid: string
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const col = db.collection("users").doc(uid).collection("achievements");
  return Promise.all(PVP_ACHIEVEMENTS.map((a) => tx.get(col.doc(a.id))));
}

/**
 * Applies progress to a single PvP achievement doc, mirroring
 * lib/services/achievement_service.dart's setProgress schema, and queues an
 * in-app notification the first time it completes.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {string} uid Player id.
 * @param {PvpAchievementDef} achievement Achievement definition.
 * @param {number} progress New progress value.
 * @param {FirebaseFirestore.DocumentSnapshot} snap Previously-read
 * achievement doc.
 * @param {unknown} languageCode This player's stored `languageCode`
 * (`users/{uid}.languageCode`), used to localize the completion
 * notification — this player is always the notification's own recipient.
 */
function applyPvpAchievementProgress(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  achievement: PvpAchievementDef,
  progress: number,
  snap: FirebaseFirestore.DocumentSnapshot,
  languageCode: unknown
): void {
  const data = snap.data() || {};

  if (data.claimed === true) return;

  const currentProgress = safeInt(data.progress, 0);
  if (progress <= currentProgress) return;

  const completed = progress >= achievement.target;
  const alreadyNotified = data.notificationSent === true;

  const update: Record<string, unknown> = {
    id: achievement.id,
    progress: Math.min(progress, achievement.target),
    target: achievement.target,
    completed,
    claimed: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (completed) {
    update.completedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  if (completed && !alreadyNotified) {
    update.notificationSent = true;
    update.notificationSentAt = admin.firestore.FieldValue.serverTimestamp();
  }

  tx.set(snap.ref, update, {merge: true});

  if (completed && !alreadyNotified) {
    const localizedTitle = languageCode === "en" ?
      (ACHIEVEMENT_TITLES[achievement.id]?.en || achievement.title) :
      (ACHIEVEMENT_TITLES[achievement.id]?.es || achievement.title);

    tx.set(db.collection("users").doc(uid).collection("notifications").doc(), {
      type: "achievement_completed",
      title: pickText(
        languageCode, "Logro completado", "Achievement completed"
      ),
      body: pickText(
        languageCode,
        `Completaste "${localizedTitle}". Reclama tu recompensa.`,
        `You completed "${localizedTitle}". Claim your reward.`
      ),
      data: {achievementId: achievement.id},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

type RankedRewardResult = {
  newRating: number;
  ratingDelta: number;
  xpEarned: number;
  coinsEarned: number;
  newStreak: number;
  bestStreak: number;
  oldLeague: PvpLeagueInfo;
  newLeague: PvpLeagueInfo;
};

/**
 * Computes one player's side of a ranked match's rewards — rating, xp,
 * coins, and win-streak — branching on whether this is a normal
 * score-based finish or an opponent-disconnect finish (flat bonus/penalty
 * instead of ELO). Mirrors match_service.dart's `calculateRatings` /
 * `_queueRankedDisconnectPenaltyUpdates` math exactly.
 * @param {{
 *   oldRating:number, opponentOldRating:number, score:number,
 *   opponentScore:number, won:boolean, draw:boolean, winReward:number,
 *   isDisconnect:boolean, currentStreak:number, bestStreak:number
 * }} params Inputs needed to compute this player's reward.
 * @return {RankedRewardResult} Computed reward fields.
 */
function computeRankedReward(params: {
  oldRating: number;
  opponentOldRating: number;
  score: number;
  opponentScore: number;
  won: boolean;
  draw: boolean;
  winReward: number;
  isDisconnect: boolean;
  currentStreak: number;
  bestStreak: number;
}): RankedRewardResult {
  let newRating: number;

  if (params.isDisconnect) {
    const bonus = RANKED_DISCONNECT_WINNER_BONUS;
    const penalty = RANKED_ABANDON_RATING_PENALTY;
    newRating = params.won ?
      disconnectWinRating(params.oldRating, params.opponentOldRating, bonus) :
      Math.max(
        RATING_FLOOR,
        Math.min(RATING_CEILING, params.oldRating - penalty)
      );
  } else {
    const {newA} = calculateRatings({
      playerARating: params.oldRating,
      playerBRating: params.opponentOldRating,
      playerAScore: params.score,
      playerBScore: params.opponentScore,
    });
    newRating = newA;
  }

  const xpEarned = params.isDisconnect ?
    (params.won ? 15 : 0) :
    params.draw ? 10 : params.won ? 15 : 5;

  const coinsEarned = params.won ? params.winReward : 0;

  const newStreak = params.won ? params.currentStreak + 1 : 0;
  const bestStreak = Math.max(params.bestStreak, newStreak);

  const oldLeague = leagueForRating(params.oldRating);
  const newLeague = leagueForRating(newRating);

  return {
    newRating,
    ratingDelta: newRating - params.oldRating,
    xpEarned,
    coinsEarned,
    newStreak,
    bestStreak,
    oldLeague,
    newLeague,
  };
}

export const finalizePvpMatch = onDocumentUpdated(
  "matches/{matchId}",
  async (event) => {
    const matchId = event.params.matchId;
    const after = event.data?.after.data();

    if (!after) return;
    if (after.status === "finished") return;
    if (after.rewarded === true) return;

    const hostUid = String(after.hostUid || "");
    const guestUid = String(after.guestUid || "");

    if (!hostUid || !guestUid) return;

    const players = after.players || {};
    const host = players[hostUid] || {};
    const guest = players[guestUid] || {};

    if (host.finished !== true || guest.finished !== true) return;

    const matchRef = db.collection("matches").doc(matchId);
    const hostRef = db.collection("users").doc(hostUid);
    const guestRef = db.collection("users").doc(guestUid);

    await db.runTransaction(async (tx) => {
      const matchSnap = await tx.get(matchRef);
      const fresh = matchSnap.data();

      if (!fresh) return;
      if (fresh.status === "finished") return;
      if (fresh.rewarded === true) return;

      const freshPlayers = fresh.players || {};
      const freshHost = freshPlayers[hostUid] || {};
      const freshGuest = freshPlayers[guestUid] || {};

      if (freshHost.finished !== true || freshGuest.finished !== true) return;

      const isDisconnect = fresh.finishReason === "opponent_disconnected";

      const scoredQuestions = await keyedQuestions(matchRef, fresh, tx);
      const hostScore = computeVerifiedPvpScore(
        scoredQuestions, freshHost.answers
      );
      const guestScore = computeVerifiedPvpScore(
        scoredQuestions, freshGuest.answers
      );
      const matchQuestionCount = scoredQuestions.length;
      const hostWrongCount = Math.max(matchQuestionCount - hostScore, 0);
      const guestWrongCount = Math.max(matchQuestionCount - guestScore, 0);

      let winnerUid: string | null = null;

      if (isDisconnect) {
        const storedWinner = String(fresh.winnerUid || "");
        if (storedWinner !== hostUid && storedWinner !== guestUid) return;
        winnerUid = storedWinner;
      } else {
        if (hostScore > guestScore) winnerUid = hostUid;
        if (guestScore > hostScore) winnerUid = guestUid;
      }

      const ranked = fresh.affectsPvpRating === true || fresh.ranked === true;
      const winReward = clampWinReward(safeInt(fresh.winReward, 0));

      const hostSnap = await tx.get(hostRef);
      const guestSnap = await tx.get(guestRef);

      const hostUser = hostSnap.data() || {};
      const guestUser = guestSnap.data() || {};

      const hostName = String(freshHost.displayName || "Host");
      const guestName = String(freshGuest.displayName || "Guest");

      const hostWon = winnerUid === hostUid;
      const guestWon = winnerUid === guestUid;
      const draw = winnerUid === null;

      const hostCurrentStreak = safeInt(hostUser.currentWinStreak1v1, 0);
      const guestCurrentStreak = safeInt(guestUser.currentWinStreak1v1, 0);

      const hostBestStreakSoFar = safeInt(hostUser.bestWinStreak1v1, 0);
      const guestBestStreakSoFar = safeInt(guestUser.bestWinStreak1v1, 0);

      const [hostAchSnaps, guestAchSnaps] = await Promise.all([
        readPvpAchievementSnaps(tx, hostUid),
        readPvpAchievementSnaps(tx, guestUid),
      ]);

      const [
        hostFirstWinSnap, hostWins10Snap, hostStreak5Snap, hostWins25Snap,
      ] = hostAchSnaps;
      const [
        guestFirstWinSnap, guestWins10Snap, guestStreak5Snap, guestWins25Snap,
      ] = guestAchSnaps;

      const ratingResults: Record<string, Record<string, unknown>> = {};

      if (ranked) {
        const hostOldRating = safeInt(hostUser.pvpRating, DEFAULT_RATING);
        const guestOldRating = safeInt(guestUser.pvpRating, DEFAULT_RATING);

        const hostReward = computeRankedReward({
          oldRating: hostOldRating,
          opponentOldRating: guestOldRating,
          score: hostScore,
          opponentScore: guestScore,
          won: hostWon,
          draw,
          winReward,
          isDisconnect,
          currentStreak: hostCurrentStreak,
          bestStreak: hostBestStreakSoFar,
        });

        const guestReward = computeRankedReward({
          oldRating: guestOldRating,
          opponentOldRating: hostOldRating,
          score: guestScore,
          opponentScore: hostScore,
          won: guestWon,
          draw,
          winReward,
          isDisconnect,
          currentStreak: guestCurrentStreak,
          bestStreak: guestBestStreakSoFar,
        });

        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[0],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0),
          hostFirstWinSnap, hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostReward.newStreak,
          hostStreak5Snap, hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[3],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins25Snap,
          hostUser.languageCode
        );

        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0),
          guestFirstWinSnap, guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestReward.newStreak,
          guestStreak5Snap, guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[3],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins25Snap,
          guestUser.languageCode
        );

        const hostCoinClamp = clampDailyPvpCoins(
          hostUser, hostReward.coinsEarned
        );
        const guestCoinClamp = clampDailyPvpCoins(
          guestUser, guestReward.coinsEarned
        );

        ratingResults[hostUid] = {
          oldRating: hostOldRating,
          newRating: hostReward.newRating,
          ratingDelta: hostReward.ratingDelta,
          xpEarned: hostReward.xpEarned,
          coinsEarned: hostCoinClamp.payable,
          winStreak: hostReward.newStreak,
          oldLeagueName: hostReward.oldLeague.name,
          newLeagueName: hostReward.newLeague.name,
        };

        ratingResults[guestUid] = {
          oldRating: guestOldRating,
          newRating: guestReward.newRating,
          ratingDelta: guestReward.ratingDelta,
          xpEarned: guestReward.xpEarned,
          coinsEarned: guestCoinClamp.payable,
          winStreak: guestReward.newStreak,
          oldLeagueName: guestReward.oldLeague.name,
          newLeagueName: guestReward.newLeague.name,
        };

        tx.set(
          hostRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: hostReward.newStreak,
            bestWinStreak1v1: hostReward.bestStreak,
            pvpRating: hostReward.newRating,
            pvpRatingDelta: hostReward.ratingDelta,
            pvpLeagueId: hostReward.newLeague.id,
            pvpLeagueName: hostReward.newLeague.name,
            ...bestLeaguePatch(hostUser, hostReward.newLeague),
            xp: admin.firestore.FieldValue.increment(hostReward.xpEarned),
            coins: admin.firestore.FieldValue.increment(
              hostCoinClamp.payable
            ),
            ...hostCoinClamp.patch,
            lastRankedXpEarned: hostReward.xpEarned,
            lastRankedCoinsEarned: hostCoinClamp.payable,
            ...(matchQuestionCount > 0 ? {
              correctAnswers: admin.firestore.FieldValue.increment(hostScore),
              wrongAnswers:
                admin.firestore.FieldValue.increment(hostWrongCount),
            } : {}),
            ...questionCountAvatarUnlockPatch(
              hostUser.unlockedAvatars,
              safeInt(hostUser.correctAnswers, 0) +
                safeInt(hostUser.wrongAnswers, 0) + matchQuestionCount
            ),
            ...(isDisconnect && !hostWon ? {
              pvpAbandonCount: admin.firestore.FieldValue.increment(1),
              pvpCooldownUntil: admin.firestore.Timestamp.fromMillis(
                Date.now() + RANKED_ABANDON_COOLDOWN_MINUTES * 60 * 1000
              ),
              lastPvpPenaltyReason: "disconnect",
            } : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        tx.set(
          guestRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: guestReward.newStreak,
            bestWinStreak1v1: guestReward.bestStreak,
            pvpRating: guestReward.newRating,
            pvpRatingDelta: guestReward.ratingDelta,
            pvpLeagueId: guestReward.newLeague.id,
            pvpLeagueName: guestReward.newLeague.name,
            ...bestLeaguePatch(guestUser, guestReward.newLeague),
            xp: admin.firestore.FieldValue.increment(guestReward.xpEarned),
            coins: admin.firestore.FieldValue.increment(
              guestCoinClamp.payable
            ),
            ...guestCoinClamp.patch,
            lastRankedXpEarned: guestReward.xpEarned,
            lastRankedCoinsEarned: guestCoinClamp.payable,
            ...(matchQuestionCount > 0 ? {
              correctAnswers: admin.firestore.FieldValue.increment(guestScore),
              wrongAnswers:
                admin.firestore.FieldValue.increment(guestWrongCount),
            } : {}),
            ...questionCountAvatarUnlockPatch(
              guestUser.unlockedAvatars,
              safeInt(guestUser.correctAnswers, 0) +
                safeInt(guestUser.wrongAnswers, 0) + matchQuestionCount
            ),
            ...(isDisconnect && !guestWon ? {
              pvpAbandonCount: admin.firestore.FieldValue.increment(1),
              pvpCooldownUntil: admin.firestore.Timestamp.fromMillis(
                Date.now() + RANKED_ABANDON_COOLDOWN_MINUTES * 60 * 1000
              ),
              lastPvpPenaltyReason: "disconnect",
            } : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        queuePvpSeasonStatsWrite(
          tx, hostRef, hostUser, safeInt(hostUser.pvpRating, DEFAULT_RATING),
          hostReward.newRating, hostWon, guestWon, draw
        );
        queuePvpSeasonStatsWrite(
          tx, guestRef, guestUser, safeInt(guestUser.pvpRating, DEFAULT_RATING),
          guestReward.newRating, guestWon, hostWon, draw
        );
      } else {
        const hostNewStreak = hostWon ? hostCurrentStreak + 1 : 0;
        const guestNewStreak = guestWon ? guestCurrentStreak + 1 : 0;

        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[0],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostFirstWinSnap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostNewStreak, hostStreak5Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[3],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins25Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestFirstWinSnap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestNewStreak, guestStreak5Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[3],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins25Snap,
          guestUser.languageCode
        );

        const hostCoinClamp = clampDailyPvpCoins(
          hostUser, hostWon ? winReward : 0
        );
        const guestCoinClamp = clampDailyPvpCoins(
          guestUser, guestWon ? winReward : 0
        );

        tx.set(
          hostRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: hostNewStreak,
            bestWinStreak1v1: Math.max(hostBestStreakSoFar, hostNewStreak),
            coins: admin.firestore.FieldValue.increment(
              hostCoinClamp.payable
            ),
            ...hostCoinClamp.patch,
            ...(matchQuestionCount > 0 ? {
              correctAnswers: admin.firestore.FieldValue.increment(hostScore),
              wrongAnswers:
                admin.firestore.FieldValue.increment(hostWrongCount),
            } : {}),
            ...questionCountAvatarUnlockPatch(
              hostUser.unlockedAvatars,
              safeInt(hostUser.correctAnswers, 0) +
                safeInt(hostUser.wrongAnswers, 0) + matchQuestionCount
            ),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        tx.set(
          guestRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: guestNewStreak,
            bestWinStreak1v1: Math.max(guestBestStreakSoFar, guestNewStreak),
            coins: admin.firestore.FieldValue.increment(
              guestCoinClamp.payable
            ),
            ...guestCoinClamp.patch,
            ...(matchQuestionCount > 0 ? {
              correctAnswers: admin.firestore.FieldValue.increment(guestScore),
              wrongAnswers:
                admin.firestore.FieldValue.increment(guestWrongCount),
            } : {}),
            ...questionCountAvatarUnlockPatch(
              guestUser.unlockedAvatars,
              safeInt(guestUser.correctAnswers, 0) +
                safeInt(guestUser.wrongAnswers, 0) + matchQuestionCount
            ),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      }

      tx.set(
        hostRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: ranked ? "ranked" : "casual",
          ranked,
          result: resultFor(hostUid, winnerUid),
          opponentUid: guestUid,
          opponentName: guestName,
          myScore: hostScore,
          opponentScore: guestScore,
          oldRating: ratingResults[hostUid]?.oldRating ?? null,
          newRating: ratingResults[hostUid]?.newRating ?? null,
          ratingDelta: ratingResults[hostUid]?.ratingDelta ?? null,
          xpEarned: ratingResults[hostUid]?.xpEarned ?? null,
          coinsEarned: ratingResults[hostUid]?.coinsEarned ?? null,
          winStreak: ratingResults[hostUid]?.winStreak ?? null,
          oldLeagueName: ratingResults[hostUid]?.oldLeagueName ?? null,
          newLeagueName: ratingResults[hostUid]?.newLeagueName ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.set(
        guestRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: ranked ? "ranked" : "casual",
          ranked,
          result: resultFor(guestUid, winnerUid),
          opponentUid: hostUid,
          opponentName: hostName,
          myScore: guestScore,
          opponentScore: hostScore,
          oldRating: ratingResults[guestUid]?.oldRating ?? null,
          newRating: ratingResults[guestUid]?.newRating ?? null,
          ratingDelta: ratingResults[guestUid]?.ratingDelta ?? null,
          xpEarned: ratingResults[guestUid]?.xpEarned ?? null,
          coinsEarned: ratingResults[guestUid]?.coinsEarned ?? null,
          winStreak: ratingResults[guestUid]?.winStreak ?? null,
          oldLeagueName: ratingResults[guestUid]?.oldLeagueName ?? null,
          newLeagueName: ratingResults[guestUid]?.newLeagueName ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.update(matchRef, {
        status: "finished",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        winnerUid,
        rewarded: true,
        ratingResults,
        [`players.${hostUid}.score`]: hostScore,
        [`players.${guestUid}.score`]: guestScore,
        // Published once nothing can be answered any more, for the review.
        answerKey: answerIndicesOf(scoredQuestions),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);

// Mirrors presence_service.dart's `onlineMaxAge` exactly — a live match's
// disconnect claim has to judge staleness the same way the client's own
// `isProbablyOnline` does, or a still-genuinely-connected opponent could
// get treated as disconnected right at the boundary.
const PRESENCE_ONLINE_MAX_AGE_MS = 45 * 1000;

/**
 * Lets a player claim their opponent disconnected mid-match, ending it in
 * their favor — but unlike the client-side flow this replaces
 * (match_service.dart's old `forceFinishMatchByDisconnect`, which trusted
 * a client-supplied `winnerUid` with no verification at all), this
 * independently re-reads the *opponent's* own `presence` doc server-side
 * and only honors the claim if they genuinely look stale. Without this, a
 * losing player could self-declare a win instantly — pocketing the
 * winReward/rating bonus while their still-actively-playing opponent gets
 * hit with a real rating penalty and cooldown as if *they* had
 * disconnected. `winnerUid`/`finishReason`/`rewarded` are now
 * Cloud-Function-only in firestore.rules, so this and finalizePvpMatch are
 * the only ways those fields can change.
 */
export const claimOpponentDisconnected = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const matchId = cleanDocId(request.data?.matchId);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const matchRef = db.collection("matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const matchSnap = await tx.get(matchRef);
    const matchData = matchSnap.data();

    if (!matchData) {
      throw new HttpsError("not-found", "Match not found.");
    }
    if (matchData.status !== "playing") {
      throw new HttpsError(
        "failed-precondition", "This match isn't in progress."
      );
    }

    const hostUid = String(matchData.hostUid || "");
    const guestUid = String(matchData.guestUid || "");

    if (uid !== hostUid && uid !== guestUid) {
      throw new HttpsError(
        "permission-denied", "You're not a player in this match."
      );
    }

    const opponentUid = uid === hostUid ? guestUid : hostUid;
    if (!opponentUid) {
      throw new HttpsError(
        "failed-precondition", "This match has no opponent yet."
      );
    }

    const players = matchData.players || {};
    if (!players[uid]) {
      throw new HttpsError(
        "failed-precondition", "You're not seated in this match."
      );
    }

    // From the deadlines the server stamped on the opponent's questions,
    // not from their presence heartbeat: that one the opponent's own client
    // writes, so a script could keep it fresh and never be claimable, and a
    // flaky connection could cost a player who was still answering.
    const opponent = players[opponentUid] || {};
    const startAt = matchData.startAt;
    const unresponsive = isOpponentUnresponsive({
      answers: opponent.answers,
      deadlines: opponent.deadlines,
      finished: opponent.finished === true,
      questionCount: Array.isArray(matchData.questions) ?
        matchData.questions.length : 0,
      timePerQuestionSec: safeInt(matchData.timePerQuestionSec, 15),
      startAtMs: startAt instanceof admin.firestore.Timestamp ?
        startAt.toMillis() : null,
      nowMs: Date.now(),
    });

    if (!unresponsive) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Tu rival todavía parece activo. Inténtalo en un momento.",
        "Your opponent still looks active. Try again in a moment."
      );
    }

    tx.update(matchRef, {
      winnerUid: uid,
      finishReason: "opponent_disconnected",
      [`players.${uid}.finished`]: true,
      [`players.${opponentUid}.finished`]: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {claimed: true};
  });
});

/**
 * Server-side replacement for match_service.dart's old
 * `resolveMatchIdByCode` + `joinMatch` two-step, which never actually
 * worked for the joiner: `joinMatch`'s own transaction needs to read the
 * match doc before the caller is host/guest on it, but firestore.rules'
 * `/matches` read rule only allows host/guest to read it — so "Join Match
 * by Code" silently failed with permission-denied for anyone using it as
 * intended. Admin SDK bypasses that read restriction, so this does the
 * code lookup and the guest-slot claim itself, server-side.
 */
export const joinMatchByCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const code = String(request.data?.code || "").trim().toUpperCase();
  if (!code) {
    throw new HttpsError("invalid-argument", "Missing code.");
  }

  // Only rooms still open: codes are short, and an old finished match
  // could share one with the room the player is looking for.
  const matchesQuery = await db.collection("matches")
    .where("matchCode", "==", code)
    .where("status", "==", "waiting")
    .limit(1)
    .get();

  if (matchesQuery.empty) {
    throw await localizedErrorFor(
      uid, "not-found",
      "No hay ninguna sala abierta con ese código.",
      "No open room has that code."
    );
  }

  const matchRef = matchesQuery.docs[0].ref;

  const userSnap = await db.collection("users").doc(uid).get();
  const userData = userSnap.data() || {};

  const seat = liveSeatFor(userData);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const data = snap.data();

    if (!data) {
      throw await localizedErrorFor(
        uid, "not-found",
        "Esa sala ya no está disponible.",
        "That room is no longer available."
      );
    }

    const status = String(data.status || "waiting");
    if (status !== "waiting") {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Esta sala ya empezó o terminó.",
        "This room already started or ended."
      );
    }

    const hostUid = String(data.hostUid || "");
    const guestUid = data.guestUid || null;

    if (hostUid === uid) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "No puedes unirte a tu propia sala.",
        "You can't join your own room."
      );
    }
    if (guestUid === uid) {
      return;
    }
    if (guestUid) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Esta sala está llena.",
        "This room is full."
      );
    }

    tx.update(matchRef, {
      guestUid: uid,
      [`players.${uid}`]: seat,
    });
  });

  return {matchId: matchRef.id};
});

// Mirrors match_service.dart's `_liveSearchMaxAge` exactly.
const LIVE_SEARCH_MAX_AGE_MS = 30 * 1000;

/**
 * Mirrors match_service.dart's `_isLiveQueueEntryValid`.
 * @param {FirebaseFirestore.DocumentData | undefined} data live_search doc.
 * @return {boolean} True if still a valid, actively-searching entry.
 */
function isLiveQueueEntryValid(
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  if (!data) return false;
  if (data.status !== "searching") return false;
  if (data.matchId != null) return false;

  const ts = data.lastHeartbeatAt || data.updatedAt;
  if (!(ts instanceof admin.firestore.Timestamp)) return true;

  return (Date.now() - ts.toMillis()) <= LIVE_SEARCH_MAX_AGE_MS;
}

/**
 * Mirrors match_service.dart's `_isAvailableForLiveMatch`.
 * @param {FirebaseFirestore.DocumentData | undefined} userData users/{uid}
 * doc data.
 * @return {boolean} True if this player's presence looks like a genuine,
 * actively-searching candidate.
 */
function isAvailableForLiveMatch(
  userData: FirebaseFirestore.DocumentData | undefined
): boolean {
  const presence = (userData || {}).presence || {};
  const status = String(presence.status || "offline");
  const inMatch = presence.inMatch === true;

  if (inMatch) return false;
  if (status !== "searching_match") return false;

  const ts = presence.updatedAt || presence.lastSeenAt;
  if (!(ts instanceof admin.firestore.Timestamp)) return true;

  return (Date.now() - ts.toMillis()) <= PRESENCE_ONLINE_MAX_AGE_MS;
}

/**
 * Mirrors match_service.dart's `_searchAgeSeconds`.
 * @param {FirebaseFirestore.DocumentData | undefined} data live_search doc.
 * @return {number} Seconds since this queue entry started searching.
 */
function searchAgeSeconds(
  data: FirebaseFirestore.DocumentData | undefined
): number {
  const ts = data?.searchStartedAt || data?.createdAt;
  if (!(ts instanceof admin.firestore.Timestamp)) return 0;

  const age = Math.floor((Date.now() - ts.toMillis()) / 1000);
  return age < 0 ? 0 : age;
}

/**
 * Mirrors pvp_league_service.dart's `PvpLeagueService.windowForSearchSeconds`
 * rating-gap bands exactly.
 * @param {number} seconds How long the longer-waiting side has searched.
 * @return {number} Max allowed rating gap for a ranked pairing right now.
 */
function allowedRatingGapForSearchSeconds(seconds: number): number {
  if (seconds < 10) return 100;
  if (seconds < 20) return 250;
  if (seconds < 30) return 500;
  return 999999;
}

/**
 * Mirrors match_service.dart's `_ratingsAreCompatible`.
 * @param {FirebaseFirestore.DocumentData | undefined} myQueue Caller's
 * live_search doc.
 * @param {FirebaseFirestore.DocumentData | undefined} opponentQueue
 * Candidate's live_search doc.
 * @return {boolean} True if the two ratings are close enough to pair,
 * given how long either side has been searching.
 */
function ratingsAreCompatible(
  myQueue: FirebaseFirestore.DocumentData | undefined,
  opponentQueue: FirebaseFirestore.DocumentData | undefined
): boolean {
  const myRating = safeInt(myQueue?.pvpRating, DEFAULT_RATING);
  const opponentRating = safeInt(opponentQueue?.pvpRating, DEFAULT_RATING);

  const longestSearchAge = Math.max(
    searchAgeSeconds(myQueue), searchAgeSeconds(opponentQueue)
  );

  const allowedGap = allowedRatingGapForSearchSeconds(longestSearchAge);
  return Math.abs(myRating - opponentRating) <= allowedGap;
}

/**
 * Mirrors match_service.dart's `_generateFixedQuestions` /
 * `_generateRandomAcrossCategories`, reading the same `fixed_pools`/
 * `fixed_categories` data server-side instead of trusting a client-chosen
 * question set.
 * @param {string} categoryId Category id, or "random" to pick across all
 * active categories.
 * @param {number} difficulty Difficulty bucket (1-3).
 * @param {number} total How many questions to select.
 * @return {Promise<Record<string, unknown>[]>} Selected questions.
 */
async function selectFixedMatchQuestions(
  categoryId: string,
  difficulty: number,
  total: number
): Promise<Record<string, unknown>[]> {
  // The question index says where every question is, so a match reads the
  // ten it serves instead of listing a whole pool (one pool per question,
  // for "random"). The listing below stays for what the index doesn't
  // cover.
  const index = await loadDailyQuestionIndex()
    .catch(() => ({entries: [], completeCategories: []} as DailyQuestionIndex));
  const candidates = matchCandidates(
    index.entries, index.completeCategories, categoryId, difficulty
  );
  if (candidates) {
    const order = seededShuffleIndices(
      candidates.length, crypto.randomBytes(4).readUInt32LE(0)
    );
    const picked = order.slice(0, total).map((i) => candidates[i]);
    const docs = await db.getAll(...picked.map((entry) =>
      fixedPoolQuestions(entry.c, entry.d).doc(entry.q)
    ));
    const questions = docs.filter((doc) => doc.exists)
      .map((doc) => doc.data() as Record<string, unknown>);
    if (questions.length > 0) return questions;
  }

  if (categoryId === "random") {
    return selectRandomAcrossCategories(difficulty, total);
  }

  const snap = await db.collection("fixed_pools").doc(categoryId)
    .collection(`difficulty_${difficulty}`).doc("pool")
    .collection("questions").get();

  if (snap.empty) {
    throw new HttpsError(
      "failed-precondition", `Empty pool for ${categoryId}.`
    );
  }

  const docs = [...snap.docs];
  for (let i = docs.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [docs[i], docs[j]] = [docs[j], docs[i]];
  }

  return docs.slice(0, Math.min(total, docs.length)).map((d) => d.data());
}

/**
 * @param {number} difficulty Difficulty bucket (1-3).
 * @param {number} total How many questions to select.
 * @return {Promise<Record<string, unknown>[]>} Selected questions, one
 * random pick per iteration across all active categories.
 */
async function selectRandomAcrossCategories(
  difficulty: number,
  total: number
): Promise<Record<string, unknown>[]> {
  const catsSnap = await db.collection("fixed_categories")
    .where("isActive", "==", true).get();

  const categories = catsSnap.docs.map((d) => d.id);
  if (categories.length === 0) {
    throw new HttpsError("failed-precondition", "No active categories.");
  }

  const out: Record<string, unknown>[] = [];
  // The client-side original this mirrors loops unconditionally until
  // `total` is reached, which is harmless (just a hung UI) if every pool
  // for this difficulty happens to be empty — server-side that would be a
  // stuck/expensive function execution instead, so this caps attempts.
  let attempts = 0;
  const maxAttempts = total * 10;

  while (out.length < total && attempts < maxAttempts) {
    attempts++;
    const cat = categories[Math.floor(Math.random() * categories.length)];

    const snap = await db.collection("fixed_pools").doc(cat)
      .collection(`difficulty_${difficulty}`).doc("pool")
      .collection("questions").get();

    if (snap.empty) continue;

    const pick = snap.docs[Math.floor(Math.random() * snap.docs.length)];
    out.push(pick.data());
  }

  return out;
}

/**
 * @param {number} len Code length.
 * @return {string} A cryptographically random room code.
 */
function randomMatchCode(len: number): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < len; i++) {
    out += chars[crypto.randomInt(chars.length)];
  }
  return out;
}

/**
 * Server-side replacement for match_service.dart's old client-driven
 * `tryFindLiveOpponent`, which read/wrote other players' `live_search`
 * docs directly from the client — firestore.rules could only narrow that
 * down to one specific transition shape, never fully prevent a client
 * from writing a fake "matched" claim (with a bogus matchId) onto an
 * actively-searching victim's queue doc. Admin SDK bypasses rules
 * entirely, so this does the candidate scan and the claim transaction
 * itself; the client only needs read/write on its own `live_search` doc
 * now. Takes no input beyond the caller's identity — every match
 * parameter (category, difficulty, ranked, reward, etc.) is read from the
 * caller's own queue doc, already written by `startLiveSearch`, rather
 * than trusted fresh on every poll call.
 */
export const tryFindLiveOpponent = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const meRef = db.collection("live_search").doc(uid);
  const meSnap = await meRef.get();
  const meData = meSnap.data();

  if (!isLiveQueueEntryValid(meData)) {
    return {matchId: null};
  }

  // The queue doc is the caller's own to write, so every parameter is
  // clamped to what the app offers: unclamped, a huge `totalQuestions` on a
  // "random" category read a whole pool per question.
  const params = clampLiveMatchParams(meData);
  const ranked = meData?.ranked === true;

  const candidatesSnap = await db.collection("live_search")
    .where("status", "==", "searching")
    .where("categoryId", "==", params.categoryId)
    .where("difficulty", "==", params.difficulty)
    .where("ranked", "==", ranked)
    .limit(20)
    .get();

  const candidates = candidatesSnap.docs.filter((d) => d.id !== uid);
  if (candidates.length === 0) return {matchId: null};

  // Picked before claiming anyone: when this used to come after the claim,
  // an empty pool left both players `matched` to a match that was never
  // written, stuck until the queue expired.
  const questions = await selectFixedMatchQuestions(
    params.categoryId, params.difficulty, params.totalQuestions
  );
  if (questions.length === 0) return {matchId: null};

  for (const oppDoc of candidates) {
    const oppUid = oppDoc.id;
    const matchRef = db.collection("matches").doc();

    const claimed = await db.runTransaction<boolean>(async (tx) => {
      const oppRef = db.collection("live_search").doc(oppUid);
      const meUserRef = db.collection("users").doc(uid);
      const oppUserRef = db.collection("users").doc(oppUid);

      const [meTxSnap, oppTxSnap, meUserSnap, oppUserSnap] =
        await Promise.all([
          tx.get(meRef), tx.get(oppRef), tx.get(meUserRef), tx.get(oppUserRef),
        ]);

      const meTx = meTxSnap.data();
      const oppTx = oppTxSnap.data();
      const meUser = meUserSnap.data() || {};
      const oppUser = oppUserSnap.data() || {};

      if (!isLiveQueueEntryValid(meTx)) return false;
      if (!isLiveQueueEntryValid(oppTx)) return false;
      if (!isAvailableForLiveMatch(meUser)) return false;
      if (!isAvailableForLiveMatch(oppUser)) return false;
      if ((meTx?.ranked === true) !== ranked) return false;
      if ((oppTx?.ranked === true) !== ranked) return false;

      // Ratings from the user docs, which only the server writes; the
      // queue docs carry a copy the client wrote and could inflate.
      const myRating = safeInt(meUser.pvpRating, DEFAULT_RATING);
      const oppRating = safeInt(oppUser.pvpRating, DEFAULT_RATING);
      if (ranked && !ratingsAreCompatible(
        {...meTx, pvpRating: myRating}, {...oppTx, pvpRating: oppRating}
      )) return false;

      const now = admin.firestore.FieldValue.serverTimestamp();

      tx.update(meRef, {
        status: "matched", matchId: matchRef.id, opponentUid: oppUid,
        updatedAt: now,
      });
      tx.update(oppRef, {
        status: "matched", matchId: matchRef.id, opponentUid: uid,
        updatedAt: now,
      });

      for (const ref of [meUserRef, oppUserRef]) {
        tx.set(ref, {
          presence: {
            status: "in_match", inMatch: true, lastSeenAt: now, updatedAt: now,
          },
          updatedAt: now,
        }, {merge: true});
      }

      const myLeague = leagueForRating(myRating);
      const oppLeague = leagueForRating(oppRating);

      // Written in the same transaction as the claim, so a pairing and its
      // match exist together or not at all.
      writeLiveMatch(tx, matchRef, {
        hostUid: uid,
        guestUid: oppUid,
        hostSeat: liveSeatFor(meUser),
        guestSeat: liveSeatFor(oppUser),
        params,
        ranked,
        questions,
        status: "waiting",
        extra: {
          matchmakingType: ranked ? "ranked_flexible_mmr" : "casual_public",
          hostInitialPvpRating: myRating,
          guestInitialPvpRating: oppRating,
          matchmakingRatingGap: Math.abs(myRating - oppRating),
          hostPvpLeagueId: myLeague.id,
          guestPvpLeagueId: oppLeague.id,
          hostPvpLeagueName: myLeague.name,
          guestPvpLeagueName: oppLeague.name,
          matchmakingWaitSec: Math.max(
            searchAgeSeconds(meTx), searchAgeSeconds(oppTx)
          ),
        },
      });

      return true;
    });

    if (claimed) return {matchId: matchRef.id};
  }

  return {matchId: null};
});

// ============================================================
// LIVE PVP
//
// Live matches used to be written by the clients themselves: the host
// created the doc with its own questions, each player wrote their own
// answers and score, and status, readiness and rematches were plain client
// writes. firestore.rules could check the shape but not the contents, so a
// player could create a ranked match against anyone with questions they
// already knew, flip a casual match to ranked once winning, and read every
// answer off the match doc.
//
// Now the clients only read `matches`. Everything below is how a live match
// is created, readied, played and closed, mirroring the async calls: the
// server stamps each question's deadline and judges every answer against
// it (async_pvp_turns.ts), and the answer key lives in a doc no client can
// read until the match is over (pvp_answer_key.ts).
// ============================================================

type LiveMatchParams = {
  categoryId: string;
  difficulty: number;
  totalQuestions: number;
  timePerQuestionSec: number;
};

/**
 * A live match's parameters, clamped to what the app offers. Shares the
 * async ranges: both create screens offer the same choices.
 * @param {Record<string, unknown>|undefined} raw Client-supplied values.
 * @return {LiveMatchParams} Safe parameters.
 */
function clampLiveMatchParams(
  raw: Record<string, unknown> | undefined
): LiveMatchParams {
  const categoryId = String(raw?.categoryId || "random").slice(0, 64);
  return {
    categoryId,
    difficulty: clampToRange(
      safeInt(raw?.difficulty, 1), ASYNC_DIFFICULTY_RANGE
    ),
    totalQuestions: clampToRange(
      safeInt(raw?.totalQuestions, 10), ASYNC_QUESTION_COUNT_RANGE
    ),
    timePerQuestionSec: clampToRange(
      safeInt(raw?.timePerQuestionSec, 15), ASYNC_SECONDS_PER_QUESTION_RANGE
    ),
  };
}

/**
 * Rejects a category that isn't an active one.
 * @param {string} categoryId Category id, or "random".
 */
async function assertActiveCategory(categoryId: string): Promise<void> {
  if (categoryId === "random") return;
  const snap = await db.collection("fixed_categories").doc(categoryId).get();
  if (snap.data()?.isActive !== true) {
    throw new HttpsError("invalid-argument", "Unknown category.");
  }
}

/**
 * A player's seat in a live match, from their own user doc: the reserved
 * username, never a name the client sent.
 * @param {FirebaseFirestore.DocumentData} user The player's user doc.
 * @return {Record<string, unknown>} The `players.{uid}` entry.
 */
function liveSeatFor(
  user: FirebaseFirestore.DocumentData
): Record<string, unknown> {
  return {
    displayName: String(user.username || user.displayName || "Player")
      .slice(0, 20),
    avatarId: String(user.avatarId || "avatar_1"),
    equippedFrame: String(user.equippedFrame || ""),
    bestLeagueId: String(user.bestLeagueId || ""),
    score: 0,
    ready: false,
    finished: false,
  };
}

/**
 * Writes a new live match and its separate answer key.
 * @param {FirebaseFirestore.Transaction|FirebaseFirestore.WriteBatch} w
 * Where to write.
 * @param {FirebaseFirestore.DocumentReference} matchRef The new match.
 * @param {object} m What the match is.
 */
function writeLiveMatch(
  w: FirebaseFirestore.Transaction | FirebaseFirestore.WriteBatch,
  matchRef: FirebaseFirestore.DocumentReference,
  m: {
    hostUid: string;
    guestUid: string | null;
    hostSeat: Record<string, unknown>;
    guestSeat: Record<string, unknown> | null;
    params: LiveMatchParams;
    ranked: boolean;
    questions: Record<string, unknown>[];
    status: "waiting" | "playing";
    extra?: Record<string, unknown>;
  }
): void {
  const {publicQuestions, answerIndices} = splitAnswerKey(m.questions);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const players: Record<string, unknown> = {[m.hostUid]: m.hostSeat};
  if (m.guestUid && m.guestSeat) players[m.guestUid] = m.guestSeat;

  (w as FirebaseFirestore.WriteBatch).set(matchRef, {
    createdAt: now,
    updatedAt: now,
    status: m.status,
    mode: "fixed",
    ranked: m.ranked,
    affectsPvpRating: m.ranked,
    categoryId: m.params.categoryId,
    difficulty: m.params.difficulty,
    aiTopic: null,
    entryFee: 0,
    winReward: MAX_WIN_REWARD,
    loseReward: 0,
    totalQuestions: publicQuestions.length,
    timePerQuestionSec: m.params.timePerQuestionSec,
    questions: publicQuestions,
    hostUid: m.hostUid,
    guestUid: m.guestUid,
    players,
    startAt: m.status === "playing" ? now : null,
    endedAt: null,
    winnerUid: null,
    finishReason: null,
    rewarded: false,
    matchCode: randomMatchCode(5),
    ...(m.extra || {}),
  });
  (w as FirebaseFirestore.WriteBatch).set(answerKeyRef(matchRef), {
    answerIndices,
  });
}

/**
 * Creates a private room, joined later with its code (joinMatchByCode).
 */
export const createPrivateLiveMatch = onCall({timeoutSeconds: 60},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const params = clampLiveMatchParams(request.data);
    // Private rooms are always casual. A ranked one let a player host a
    // room, join it with a second account and win by default, over and
    // over; ranked play only comes from public matchmaking, which pairs
    // by rating.
    const ranked = false;
    await assertActiveCategory(params.categoryId);

    const userSnap = await db.collection("users").doc(uid).get();
    const user = userSnap.data() || {};

    const questions = await selectFixedMatchQuestions(
      params.categoryId, params.difficulty, params.totalQuestions
    );
    if (questions.length === 0) {
      throw new HttpsError("failed-precondition", "No questions available.");
    }

    const matchRef = db.collection("matches").doc();
    const batch = db.batch();
    writeLiveMatch(batch, matchRef, {
      hostUid: uid,
      guestUid: null,
      hostSeat: liveSeatFor(user),
      guestSeat: null,
      params,
      ranked,
      questions,
      status: "waiting",
      extra: {matchType: ranked ? "ranked_private" : "private"},
    });
    await batch.commit();

    return {matchId: matchRef.id};
  });

/**
 * The caller's seat in a live match, or an error if they have none.
 * @param {FirebaseFirestore.DocumentData|undefined} data The match doc.
 * @param {string} uid Caller.
 * @return {{data: FirebaseFirestore.DocumentData, opponentUid: string}}
 * The match and the other player's uid (empty while the room is open).
 */
function liveSeatContext(
  data: FirebaseFirestore.DocumentData | undefined, uid: string
): {data: FirebaseFirestore.DocumentData; opponentUid: string} {
  if (!data) throw new HttpsError("not-found", "Match not found.");
  const hostUid = String(data.hostUid || "");
  const guestUid = String(data.guestUid || "");
  if (uid !== hostUid && uid !== guestUid) {
    throw new HttpsError("permission-denied", "Not your match.");
  }
  return {data, opponentUid: uid === hostUid ? guestUid : hostUid};
}

/**
 * Marks the caller ready (or not) in a room's lobby, and starts the match
 * once both are.
 */
export const setLiveMatchReady = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const matchId = cleanDocId(request.data?.matchId);
  const ready = request.data?.ready === true;
  const matchRef = db.collection("matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const {data, opponentUid} = liveSeatContext(snap.data(), uid);
    if (String(data.status || "") !== "waiting") return {started: false};

    const players = data.players || {};
    const opponentReady = opponentUid !== "" &&
      players[opponentUid]?.ready === true;
    const start = ready && opponentReady;

    tx.update(matchRef, {
      [`players.${uid}.ready`]: ready,
      ...(start ? {
        status: "playing",
        startAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {started: start};
  });
});

/**
 * Cancels a room still in the lobby, so a player whose opponent left isn't
 * stuck there.
 */
export const cancelLiveMatch = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const matchRef = db.collection("matches")
    .doc(requiredDocId(request.data?.matchId));

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const {data} = liveSeatContext(snap.data(), uid);
    if (String(data.status || "") !== "waiting") return;
    tx.update(matchRef, {
      status: "cancelled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

/**
 * The caller's answers in a live match, as judged so far: question index
 * to whether it was right. Lets a player who comes back mid-match see the
 * score they had, without the key itself.
 * @param {Record<string, unknown>[]} keyed Questions with answers.
 * @param {Record<string, unknown>} answers Banked answers.
 * @return {Record<string, boolean>} Verdicts by question index.
 */
function verdictsFor(
  keyed: Record<string, unknown>[],
  answers: Record<string, unknown>
): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const [key, selected] of Object.entries(answers)) {
    const i = parseInt(key, 10);
    if (Number.isNaN(i) || i < 0 || i >= keyed.length) continue;
    out[key] = safeInt(selected, -2) === safeInt(keyed[i].answerIndex, -1);
  }
  return out;
}

/**
 * Opens (or resumes) the caller's run through a live match: the question
 * to serve and how long is left on it. Same clock as async — see
 * openAsyncPvpTurn.
 */
export const openLiveMatchTurn = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const matchRef = db.collection("matches")
    .doc(requiredDocId(request.data?.matchId));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const {data} = liveSeatContext(snap.data(), uid);
    const keyed = await keyedQuestions(matchRef, data, tx);
    const mine = (data.players || {})[uid] || {};
    const answers = (mine.answers || {}) as Record<string, unknown>;

    if (String(data.status || "") !== "playing" || mine.finished === true) {
      return {
        index: keyed.length, finished: true, remainingMs: 0,
        answers, verdicts: verdictsFor(keyed, answers),
      };
    }

    const turn = openTurn({
      answers,
      deadlines: mine.deadlines,
      questionCount: keyed.length,
      timePerQuestionSec: safeInt(data.timePerQuestionSec, 15),
      nowMs: Date.now(),
    });

    const patch: Record<string, unknown> = {};
    const banked: Record<string, unknown> = {...answers};
    for (const index of turn.timedOutIndices) {
      patch[`players.${uid}.answers.${index}`] = TIMED_OUT_ANSWER;
      banked[String(index)] = TIMED_OUT_ANSWER;
    }
    if (turn.deadlineIsNew && turn.deadlineMs !== null) {
      patch[`players.${uid}.deadlines.${turn.index}`] = turn.deadlineMs;
    }
    if (Object.keys(patch).length > 0) tx.update(matchRef, patch);

    return {
      index: turn.index,
      finished: turn.finished,
      remainingMs: turn.remainingMs,
      answers: banked,
      verdicts: verdictsFor(keyed, banked),
    };
  });
});

/**
 * Judges one live answer against the server's clock and key, banks it,
 * updates the score the opponent sees, and stamps the next question's
 * deadline. Returns the right option so the client can reveal it.
 */
export const submitLiveMatchAnswer = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const matchRef = db.collection("matches")
    .doc(requiredDocId(request.data?.matchId));
  const questionIndex = safeInt(request.data?.questionIndex, -1);
  const selectedIndex = safeInt(request.data?.selectedIndex, TIMED_OUT_ANSWER);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const {data} = liveSeatContext(snap.data(), uid);
    if (String(data.status || "") !== "playing") {
      throw new HttpsError("failed-precondition", "Match not in progress.");
    }
    const keyed = await keyedQuestions(matchRef, data, tx);
    const mine = (data.players || {})[uid] || {};
    if (mine.finished === true) {
      throw new HttpsError("failed-precondition", "Round already closed.");
    }
    const answers = (mine.answers || {}) as Record<string, unknown>;

    const resolution = resolveAnswer({
      answers,
      deadlines: mine.deadlines,
      questionCount: keyed.length,
      timePerQuestionSec: safeInt(data.timePerQuestionSec, 15),
      nowMs: Date.now(),
    }, questionIndex, selectedIndex);

    if (resolution.kind === "out-of-range") {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }
    if (resolution.kind !== "accepted") {
      throw new HttpsError("failed-precondition", resolution.kind);
    }

    const banked = {
      ...answers, [String(questionIndex)]: resolution.storedIndex,
    };
    const correctIndex = safeInt(keyed[questionIndex].answerIndex, -1);

    const patch: Record<string, unknown> = {
      [`players.${uid}.answers.${questionIndex}`]: resolution.storedIndex,
      [`players.${uid}.score`]: computeVerifiedPvpScore(keyed, banked),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (resolution.nextDeadlineMs !== null) {
      patch[`players.${uid}.deadlines.${resolution.nextIndex}`] =
        resolution.nextDeadlineMs;
    }
    tx.update(matchRef, patch);

    return {
      storedIndex: resolution.storedIndex,
      correctIndex,
      correct: resolution.storedIndex === correctIndex,
      timedOut: resolution.timedOut,
      nextIndex: resolution.nextIndex,
      nextRemainingMs: resolution.nextRemainingMs,
      finished: resolution.finished,
    };
  });
});

/**
 * Closes the caller's run: banks anything that timed out and marks them
 * finished, which is what lets finalizePvpMatch settle the match once both
 * are.
 */
export const finishLiveMatch = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const matchRef = db.collection("matches")
    .doc(requiredDocId(request.data?.matchId));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const {data} = liveSeatContext(snap.data(), uid);
    const keyed = await keyedQuestions(matchRef, data, tx);
    const mine = (data.players || {})[uid] || {};
    const answers = {...(mine.answers || {})} as Record<string, unknown>;

    if (mine.finished === true || String(data.status || "") !== "playing") {
      return {score: computeVerifiedPvpScore(keyed, answers)};
    }

    const turn = openTurn({
      answers,
      deadlines: mine.deadlines,
      questionCount: keyed.length,
      timePerQuestionSec: safeInt(data.timePerQuestionSec, 15),
      nowMs: Date.now(),
    });
    if (!turn.finished) {
      throw new HttpsError("failed-precondition", "Round not finished.");
    }

    const patch: Record<string, unknown> = {
      [`players.${uid}.finished`]: true,
      [`players.${uid}.finishedAt`]:
        admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    for (const index of turn.timedOutIndices) {
      patch[`players.${uid}.answers.${index}`] = TIMED_OUT_ANSWER;
      answers[String(index)] = TIMED_OUT_ANSWER;
    }
    const score = computeVerifiedPvpScore(keyed, answers);
    patch[`players.${uid}.score`] = score;
    tx.update(matchRef, patch);

    return {score};
  });
});

/**
 * Asks for a rematch, and creates it once both players have asked. The
 * first ask notifies the opponent.
 */
export const requestLiveRematch = onCall({timeoutSeconds: 60},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const matchId = cleanDocId(request.data?.matchId);
    const oldRef = db.collection("matches").doc(matchId);

    const first = await oldRef.get();
    const {data: old, opponentUid} = liveSeatContext(first.data(), uid);
    if (String(old.status || "") !== "finished" || !opponentUid) {
      throw new HttpsError("failed-precondition", "Match isn't finished.");
    }
    if (old.rematchMatchId) return {rematchMatchId: old.rematchMatchId};

    const params = clampLiveMatchParams(old);
    // A rematch is casual even after a ranked match: the same two players
    // trading ranked wins back and forth was a way to farm rating.
    const ranked = false;
    // Chosen up front so the rematch can be written in the same
    // transaction that decides it, with nothing left half-done.
    const questions = old.rematchRequests?.[opponentUid] === true ?
      await selectFixedMatchQuestions(
        params.categoryId, params.difficulty, params.totalQuestions
      ) : [];

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(oldRef);
      const data = snap.data() || {};
      if (data.rematchMatchId) {
        return {rematchMatchId: String(data.rematchMatchId), notify: false};
      }

      const requests = {...(data.rematchRequests || {}), [uid]: true};
      const both = requests[opponentUid] === true;

      if (!both || questions.length === 0) {
        tx.update(oldRef, {
          [`rematchRequests.${uid}`]: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {rematchMatchId: null, notify: !both};
      }

      const [meSnap, oppSnap] = await Promise.all([
        tx.get(db.collection("users").doc(uid)),
        tx.get(db.collection("users").doc(opponentUid)),
      ]);
      const hostUid = String(data.hostUid);
      const guestUid = String(data.guestUid);
      const seats: Record<string, Record<string, unknown>> = {
        [uid]: {...liveSeatFor(meSnap.data() || {}), ready: true},
        [opponentUid]: {...liveSeatFor(oppSnap.data() || {}), ready: true},
      };

      const newRef = db.collection("matches").doc();
      writeLiveMatch(tx, newRef, {
        hostUid,
        guestUid,
        hostSeat: seats[hostUid],
        guestSeat: seats[guestUid],
        params,
        ranked,
        questions,
        status: "playing",
        extra: {
          matchmakingType: String(data.matchmakingType || "") ||
            (ranked ? "ranked_rematch" : "casual_rematch"),
          previousMatchId: matchId,
        },
      });
      tx.update(oldRef, {
        [`rematchRequests.${uid}`]: true,
        rematchMatchId: newRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {rematchMatchId: newRef.id, notify: false};
    });

    if (result.notify) {
      await notifyOnce(opponentUid, uid, "rematch_request", {matchId});
    }
    return {rematchMatchId: result.rematchMatchId};
  });

/**
 * Writes one cross-user notification, at most once per sender, type and
 * match or invite — the same guarantee sendUserNotification gives.
 * @param {string} targetUid Recipient.
 * @param {string} senderUid Sender.
 * @param {string} type Notification type.
 * @param {Record<string, string>} ids matchId / inviteId to route on.
 */
async function notifyOnce(
  targetUid: string,
  senderUid: string,
  type: string,
  ids: Record<string, string>
): Promise<void> {
  const [senderSnap, targetSnap] = await db.getAll(
    db.collection("users").doc(senderUid),
    db.collection("users").doc(targetUid)
  );
  const sender = senderSnap.data() || {};
  const senderName = String(sender.username || sender.displayName || "?")
    .slice(0, 20);
  const {title, body} = crossUserNotificationText(
    type, targetSnap.data()?.languageCode, senderName
  );
  const id = [type, senderUid, ids.matchId || ids.inviteId || ""].join("__");
  try {
    await db.collection("users").doc(targetUid)
      .collection("notifications").doc(id).create({
        type, title, body,
        data: {...ids, fromUid: senderUid},
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (error) {
    if ((error as {code?: number}).code !== 6) throw error;
  }
}

// ---- Friend challenges (realtime invites) ----------------------------

const MAX_PENDING_REALTIME_INVITES = 10;

/**
 * Challenges a friend to a live match. The invitee is notified; the match
 * itself is created when they accept.
 *
 * Used to be a client write into `realtime_invites` plus a write into the
 * friend's notifications, which the rules (rightly) refused — so the invite
 * was saved, the sender saw an error, and the friend was never told.
 */
export const createRealtimeInvite = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const toUid = cleanDocId(request.data?.toUid);
  if (!toUid || toUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid player.");
  }
  const params = clampLiveMatchParams(request.data);
  await assertActiveCategory(params.categoryId);

  const [friendSnap, meSnap, toSnap] = await Promise.all([
    db.collection("users").doc(uid).collection("friends").doc(toUid).get(),
    db.collection("users").doc(uid).get(),
    db.collection("users").doc(toUid).get(),
  ]);
  if (!friendSnap.exists || !toSnap.exists) {
    throw await localizedErrorFor(
      uid, "permission-denied",
      "Solo puedes retar en vivo a tus amigos.",
      "You can only challenge your friends live."
    );
  }

  const pending = db.collection("realtime_invites")
    .where("fromUid", "==", uid)
    .where("status", "==", "pending");
  const [pendingCount, pendingForFriend] = await Promise.all([
    pending.count().get(),
    pending.where("toUid", "==", toUid).limit(1).get(),
  ]);
  if (!pendingForFriend.empty) {
    return {inviteId: pendingForFriend.docs[0].id};
  }
  if (pendingCount.data().count >= MAX_PENDING_REALTIME_INVITES) {
    throw await localizedErrorFor(
      uid, "resource-exhausted",
      "Tienes demasiados retos pendientes. Espera a que respondan.",
      "You have too many pending challenges. Wait for them to answer."
    );
  }

  const me = meSnap.data() || {};
  const to = toSnap.data() || {};
  const inviteRef = db.collection("realtime_invites").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await inviteRef.set({
    fromUid: uid,
    fromName: String(me.username || me.displayName || "Player").slice(0, 20),
    toUid,
    toName: String(to.username || to.displayName || "Player").slice(0, 20),
    status: "pending",
    ...params,
    winReward: MAX_WIN_REWARD,
    matchId: null,
    createdAt: now,
    updatedAt: now,
  });

  await notifyOnce(toUid, uid, "realtime_invite", {inviteId: inviteRef.id});
  return {inviteId: inviteRef.id};
});

/**
 * Accepts a friend's challenge: creates the match and tells the inviter.
 */
export const acceptRealtimeInvite = onCall({timeoutSeconds: 60},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const inviteRef = db.collection("realtime_invites")
      .doc(requiredDocId(request.data?.inviteId));

    const first = (await inviteRef.get()).data();
    if (!first || first.toUid !== uid || first.status !== "pending") {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Esta invitación ya no está disponible.",
        "This invite is no longer available."
      );
    }
    const params = clampLiveMatchParams(first);
    const questions = await selectFixedMatchQuestions(
      params.categoryId, params.difficulty, params.totalQuestions
    );
    if (questions.length === 0) {
      throw new HttpsError("failed-precondition", "No questions available.");
    }

    const fromUid = String(first.fromUid);
    const matchRef = db.collection("matches").doc();

    await db.runTransaction(async (tx) => {
      const [inviteSnap, fromSnap, toSnap] = await Promise.all([
        tx.get(inviteRef),
        tx.get(db.collection("users").doc(fromUid)),
        tx.get(db.collection("users").doc(uid)),
      ]);
      if (inviteSnap.data()?.status !== "pending") {
        throw await localizedErrorFor(
          uid, "failed-precondition",
          "Ese reto ya no está disponible.",
          "That challenge is no longer available."
        );
      }
      writeLiveMatch(tx, matchRef, {
        hostUid: fromUid,
        guestUid: uid,
        hostSeat: liveSeatFor(fromSnap.data() || {}),
        guestSeat: liveSeatFor(toSnap.data() || {}),
        params,
        ranked: false,
        questions,
        status: "waiting",
        extra: {source: "friend_invite", inviteId: inviteRef.id},
      });
      tx.update(inviteRef, {
        status: "accepted",
        matchId: matchRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await notifyOnce(fromUid, uid, "realtime_invite_accepted", {
      inviteId: inviteRef.id, matchId: matchRef.id,
    });
    return {matchId: matchRef.id};
  });

/**
 * Declines a challenge (the invitee) or withdraws it (the inviter).
 */
export const closeRealtimeInvite = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const inviteRef = db.collection("realtime_invites")
    .doc(requiredDocId(request.data?.inviteId));

  await db.runTransaction(async (tx) => {
    const data = (await tx.get(inviteRef)).data();
    if (!data || data.status !== "pending") return;
    if (data.toUid !== uid && data.fromUid !== uid) {
      throw new HttpsError("permission-denied", "Not your invite.");
    }
    tx.update(inviteRef, {
      status: data.toUid === uid ? "declined" : "cancelled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

/**
 * Async (deferred) 1v1 matches never carry a ranked/affectsPvpRating flag
 * today (createAsyncFixedMatch never sets one) — this trigger only ever
 * applies casual rewards. If async ranked matches are added later, port the
 * ranked branch from finalizePvpMatch here too.
 */
export const finalizeAsyncPvpMatch = onDocumentUpdated(
  "async_matches/{matchId}",
  async (event) => {
    const matchId = event.params.matchId;
    const after = event.data?.after.data();

    if (!after) return;
    if (after.rewarded === true) return;
    if (after.challengerStatus !== "finished") return;
    if (after.challengedStatus !== "finished") return;

    const challengerUid = String(after.challengerUid || "");
    const challengedUid = String(after.challengedUid || "");

    if (!challengerUid || !challengedUid) return;

    const matchRef = db.collection("async_matches").doc(matchId);
    const challengerRef = db.collection("users").doc(challengerUid);
    const challengedRef = db.collection("users").doc(challengedUid);

    await db.runTransaction(async (tx) => {
      const matchSnap = await tx.get(matchRef);
      const fresh = matchSnap.data();

      if (!fresh) return;
      if (fresh.rewarded === true) return;
      if (fresh.challengerStatus !== "finished") return;
      if (fresh.challengedStatus !== "finished") return;

      const scoredQuestions = await keyedQuestions(matchRef, fresh, tx);
      const challengerScore = computeVerifiedPvpScore(
        scoredQuestions, fresh.challenger?.answers
      );
      const challengedScore = computeVerifiedPvpScore(
        scoredQuestions, fresh.challenged?.answers
      );
      const matchQuestionCount = scoredQuestions.length;
      const challengerWrongCount =
        Math.max(matchQuestionCount - challengerScore, 0);
      const challengedWrongCount =
        Math.max(matchQuestionCount - challengedScore, 0);

      let winnerUid: string | null = null;
      if (challengerScore > challengedScore) winnerUid = challengerUid;
      if (challengedScore > challengerScore) winnerUid = challengedUid;

      const draw = winnerUid === null;
      const challengerWon = winnerUid === challengerUid;
      const challengedWon = winnerUid === challengedUid;

      const winReward = clampWinReward(safeInt(fresh.winReward, 0));

      const challengerSnap = await tx.get(challengerRef);
      const challengedSnap = await tx.get(challengedRef);
      const challengerUser = challengerSnap.data() || {};
      const challengedUser = challengedSnap.data() || {};

      const challengerCurrentStreak = safeInt(
        challengerUser.currentWinStreak1v1, 0
      );
      const challengedCurrentStreak = safeInt(
        challengedUser.currentWinStreak1v1, 0
      );
      const challengerBestStreakSoFar = safeInt(
        challengerUser.bestWinStreak1v1, 0
      );
      const challengedBestStreakSoFar = safeInt(
        challengedUser.bestWinStreak1v1, 0
      );

      const challengerNewStreak = challengerWon ?
        challengerCurrentStreak + 1 : 0;
      const challengedNewStreak = challengedWon ?
        challengedCurrentStreak + 1 : 0;

      const challengerCoinClamp = clampDailyPvpCoins(
        challengerUser, challengerWon ? winReward : 0
      );
      const challengedCoinClamp = clampDailyPvpCoins(
        challengedUser, challengedWon ? winReward : 0
      );

      // Async matches never fed first_pvp_win/pvp_wins_10/pvp_streak_5/
      // pvp_wins_25 progress — finalizePvpMatch (live matches) always did,
      // via the identical calls below, so a player who only plays async
      // could win 25+ matches and see wins1v1/currentWinStreak1v1 climb
      // correctly while these four achievements stayed stuck at 0.
      const [challengerAchSnaps, challengedAchSnaps] = await Promise.all([
        readPvpAchievementSnaps(tx, challengerUid),
        readPvpAchievementSnaps(tx, challengedUid),
      ]);

      const [
        challengerFirstWinSnap, challengerWins10Snap,
        challengerStreak5Snap, challengerWins25Snap,
      ] = challengerAchSnaps;
      const [
        challengedFirstWinSnap, challengedWins10Snap,
        challengedStreak5Snap, challengedWins25Snap,
      ] = challengedAchSnaps;

      applyPvpAchievementProgress(
        tx, challengerUid, PVP_ACHIEVEMENTS[0],
        safeInt(challengerUser.wins1v1, 0) + (challengerWon ? 1 : 0),
        challengerFirstWinSnap, challengerUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengerUid, PVP_ACHIEVEMENTS[1],
        safeInt(challengerUser.wins1v1, 0) + (challengerWon ? 1 : 0),
        challengerWins10Snap, challengerUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengerUid, PVP_ACHIEVEMENTS[2], challengerNewStreak,
        challengerStreak5Snap, challengerUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengerUid, PVP_ACHIEVEMENTS[3],
        safeInt(challengerUser.wins1v1, 0) + (challengerWon ? 1 : 0),
        challengerWins25Snap, challengerUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengedUid, PVP_ACHIEVEMENTS[0],
        safeInt(challengedUser.wins1v1, 0) + (challengedWon ? 1 : 0),
        challengedFirstWinSnap, challengedUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengedUid, PVP_ACHIEVEMENTS[1],
        safeInt(challengedUser.wins1v1, 0) + (challengedWon ? 1 : 0),
        challengedWins10Snap, challengedUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengedUid, PVP_ACHIEVEMENTS[2], challengedNewStreak,
        challengedStreak5Snap, challengedUser.languageCode
      );
      applyPvpAchievementProgress(
        tx, challengedUid, PVP_ACHIEVEMENTS[3],
        safeInt(challengedUser.wins1v1, 0) + (challengedWon ? 1 : 0),
        challengedWins25Snap, challengedUser.languageCode
      );

      tx.set(
        challengerRef,
        {
          matches1v1: admin.firestore.FieldValue.increment(1),
          wins1v1: admin.firestore.FieldValue.increment(challengerWon ? 1 : 0),
          losses1v1: admin.firestore.FieldValue.increment(
            challengedWon ? 1 : 0
          ),
          draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
          currentWinStreak1v1: challengerNewStreak,
          bestWinStreak1v1: Math.max(
            challengerBestStreakSoFar, challengerNewStreak
          ),
          coins: admin.firestore.FieldValue.increment(
            challengerCoinClamp.payable
          ),
          ...challengerCoinClamp.patch,
          ...(matchQuestionCount > 0 ? {
            correctAnswers:
              admin.firestore.FieldValue.increment(challengerScore),
            wrongAnswers:
              admin.firestore.FieldValue.increment(challengerWrongCount),
          } : {}),
          ...questionCountAvatarUnlockPatch(
            challengerUser.unlockedAvatars,
            safeInt(challengerUser.correctAnswers, 0) +
              safeInt(challengerUser.wrongAnswers, 0) + matchQuestionCount
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.set(
        challengedRef,
        {
          matches1v1: admin.firestore.FieldValue.increment(1),
          wins1v1: admin.firestore.FieldValue.increment(
            challengedWon ? 1 : 0
          ),
          losses1v1: admin.firestore.FieldValue.increment(
            challengerWon ? 1 : 0
          ),
          draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
          currentWinStreak1v1: challengedNewStreak,
          bestWinStreak1v1: Math.max(
            challengedBestStreakSoFar, challengedNewStreak
          ),
          coins: admin.firestore.FieldValue.increment(
            challengedCoinClamp.payable
          ),
          ...challengedCoinClamp.patch,
          ...(matchQuestionCount > 0 ? {
            correctAnswers:
              admin.firestore.FieldValue.increment(challengedScore),
            wrongAnswers:
              admin.firestore.FieldValue.increment(challengedWrongCount),
          } : {}),
          ...questionCountAvatarUnlockPatch(
            challengedUser.unlockedAvatars,
            safeInt(challengedUser.correctAnswers, 0) +
              safeInt(challengedUser.wrongAnswers, 0) + matchQuestionCount
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      const challengerName = String(
        fresh.challengerDisplayName || "Player"
      );
      const challengedName = String(
        fresh.challengedDisplayName || "Player"
      );

      // Async matches never wrote match_history entries — only live matches
      // did (see finalizePvpMatch above) — so an async-only player's
      // Profile "Recent Matches" section always showed empty despite
      // wins1v1/losses1v1/matches1v1 tracking correctly. Async has no
      // ranking/MMR system, so the rating fields are always null here.
      tx.set(
        challengerRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: "casual",
          ranked: false,
          result: resultFor(challengerUid, winnerUid),
          opponentUid: challengedUid,
          opponentName: challengedName,
          myScore: challengerScore,
          opponentScore: challengedScore,
          oldRating: null,
          newRating: null,
          ratingDelta: null,
          xpEarned: null,
          coinsEarned: challengerCoinClamp.payable,
          winStreak: challengerNewStreak,
          oldLeagueName: null,
          newLeagueName: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.set(
        challengedRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: "casual",
          ranked: false,
          result: resultFor(challengedUid, winnerUid),
          opponentUid: challengerUid,
          opponentName: challengerName,
          myScore: challengedScore,
          opponentScore: challengerScore,
          oldRating: null,
          newRating: null,
          ratingDelta: null,
          xpEarned: null,
          coinsEarned: challengedCoinClamp.payable,
          winStreak: challengedNewStreak,
          oldLeagueName: null,
          newLeagueName: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      const notify = (
        targetUid: string,
        esTitle: string,
        enTitle: string,
        esBody: string,
        enBody: string
      ): void => {
        const languageCode = targetUid === challengerUid ?
          challengerUser.languageCode : challengedUser.languageCode;

        tx.set(
          db.collection("users").doc(targetUid).collection("notifications")
            .doc(),
          {
            type: "match_result",
            title: pickText(languageCode, esTitle, enTitle),
            body: pickText(languageCode, esBody, enBody),
            data: {matchId},
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        );
      };

      if (draw) {
        notify(
          challengerUid, "Partida terminada", "Async match finished",
          `Tu partida contra ${challengedName} terminó en empate.`,
          `Your match against ${challengedName} ended in a draw.`
        );
        notify(
          challengedUid, "Partida terminada", "Async match finished",
          `Tu partida contra ${challengerName} terminó en empate.`,
          `Your match against ${challengerName} ended in a draw.`
        );
      } else {
        const loserUid = challengerWon ? challengedUid : challengerUid;
        const winnerOpponentName = challengerWon ?
          challengedName : challengerName;
        const loserOpponentName = loserUid === challengerUid ?
          challengedName : challengerName;

        notify(
          winnerUid as string, "¡Ganaste!", "You won!",
          `Ganaste tu partida asíncrona contra ${winnerOpponentName}.`,
          `You won your async match against ${winnerOpponentName}.`
        );
        notify(
          loserUid, "Partida terminada", "Match finished",
          `Perdiste tu partida asíncrona contra ${loserOpponentName}.`,
          `You lost your async match against ${loserOpponentName}.`
        );
      }

      tx.update(matchRef, {
        status: "completed",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        winnerUid,
        rewarded: true,
        challengerScore,
        challengedScore,
        answerKey: answerIndicesOf(scoredQuestions),
        resultNotificationsSent: true,
      });
    });
  }
);

// The spread the challenge UI actually offers (friend_challenge_setup_screen
// and create_match_screen): 5/10/15 questions at 8-20 seconds each, three
// difficulties. Clamped rather than rejected so a UI tweak doesn't start
// failing calls, but bounded so a modified client can't create a match with
// a 10-minute clock or a hundred questions.
const ASYNC_QUESTION_COUNT_RANGE = {min: 5, max: 15};
const ASYNC_SECONDS_PER_QUESTION_RANGE = {min: 8, max: 20};
const ASYNC_DIFFICULTY_RANGE = {min: 1, max: 3};

/**
 * @param {number} value Raw value.
 * @param {{min: number, max: number}} range Inclusive bounds.
 * @return {number} `value` held inside `range`.
 */
function clampToRange(
  value: number, range: {min: number; max: number}
): number {
  return Math.max(range.min, Math.min(range.max, value));
}

/**
 * Creates an async (turn-based) challenge against another player.
 *
 * Creating one used to be a direct client write, and firestore.rules can
 * only check the shape of a document, not where its contents came from —
 * so the client picked the `questions` themselves. A modified client could
 * therefore write its own questions (with its own `answerIndex`) into a
 * match the opponent then had to play, which is an unbeatable async match,
 * and could set `timePerQuestionSec` to anything it liked — the very field
 * the server-anchored clock now measures every deadline from.
 *
 * Note this is not about *seeing* the questions: both players read the
 * match doc to play it, so both can always see everything in it. It is
 * about who chooses what goes in.
 *
 * Display names are read from the two user docs rather than taken from the
 * request, for the same reason `sendUserNotification` reads the sender's:
 * they are shown to the other player.
 */
const MAX_WAITING_ASYNC_CHALLENGES = 10;

export const createAsyncPvpMatch = onCall({
  // Selecting questions reads a whole category pool, which is slower than
  // a plain write — the client gives up well before this.
  timeoutSeconds: 60,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const challengedUid = cleanDocId(request.data?.challengedUid);

  if (!challengedUid) {
    throw new HttpsError("invalid-argument", "Missing challengedUid.");
  }

  if (challengedUid === uid) {
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "No puedes retarte a ti mismo",
      "You can't challenge yourself"
    );
  }

  const categoryId = String(request.data?.categoryId || "random");
  const difficulty = clampToRange(
    safeInt(request.data?.difficulty, 1), ASYNC_DIFFICULTY_RANGE
  );
  const totalQuestions = clampToRange(
    safeInt(request.data?.totalQuestions, 10), ASYNC_QUESTION_COUNT_RANGE
  );
  const timePerQuestionSec = clampToRange(
    safeInt(request.data?.timePerQuestionSec, 15),
    ASYNC_SECONDS_PER_QUESTION_RANGE
  );

  const [challengerSnap, challengedSnap] = await db.getAll(
    db.collection("users").doc(uid),
    db.collection("users").doc(challengedUid)
  );

  if (!challengedSnap.exists) {
    throw await localizedErrorFor(
      uid, "not-found",
      "Ese jugador ya no existe.",
      "That player no longer exists."
    );
  }

  // Each challenge pushes a notification to the challenged player, and an
  // unanswered one can be won by forfeit a week later. Unbounded, that was
  // a way to spam anyone and to farm forfeit wins against inactive
  // players, so a player may have only so many waiting at once, and one
  // per opponent.
  const waiting = db.collection("async_matches")
    .where("challengerUid", "==", uid)
    .where("status", "==", "waiting_challenged");
  const [waitingCount, waitingForThisPlayer] = await Promise.all([
    waiting.count().get(),
    waiting.where("challengedUid", "==", challengedUid).limit(1).get(),
  ]);
  if (!waitingForThisPlayer.empty) {
    throw await localizedErrorFor(
      uid, "already-exists",
      "Ya tienes un reto pendiente con este jugador",
      "You already have a pending challenge with this player"
    );
  }
  if (waitingCount.data().count >= MAX_WAITING_ASYNC_CHALLENGES) {
    throw await localizedErrorFor(
      uid, "resource-exhausted",
      "Tienes demasiados retos sin responder. Espera a que los jueguen.",
      "You have too many unanswered challenges. Wait for them to be played."
    );
  }

  if (categoryId !== "random") {
    const categorySnap = await db.collection("fixed_categories")
      .doc(categoryId).get();

    if (categorySnap.data()?.isActive !== true) {
      throw new HttpsError("invalid-argument", "Unknown category.");
    }
  }

  const questions = await selectFixedMatchQuestions(
    categoryId, difficulty, totalQuestions
  );

  if (questions.length === 0) {
    throw new HttpsError("failed-precondition", "No questions available.");
  }

  const challengerData = challengerSnap.data() || {};
  const challengedData = challengedSnap.data() || {};

  const challengerName = String(
    challengerData.displayName || challengerData.username || "Player"
  );
  const challengedName = String(
    challengedData.displayName || challengedData.username || "Player"
  );

  const matchRef = db.collection("async_matches").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  // The key goes where no client can read it — see pvp_answer_key.ts.
  const {publicQuestions, answerIndices} = splitAnswerKey(questions);
  const createBatch = db.batch();
  createBatch.set(answerKeyRef(matchRef), {answerIndices});

  createBatch.set(matchRef, {
    createdAt: now,
    lastUpdatedAt: now,

    status: "waiting_challenged",
    mode: "fixed",
    categoryId,
    difficulty,
    totalQuestions: publicQuestions.length,
    timePerQuestionSec,
    questions: publicQuestions,

    challengerUid: uid,
    challengedUid,

    challengerDisplayName: challengerName,
    challengedDisplayName: challengedName,

    challengerStatus: "pending",
    challengedStatus: "pending",

    challenger: {score: 0, finishedAt: null},
    challenged: {score: 0, finishedAt: null},

    challengerScore: 0,
    challengedScore: 0,

    winnerUid: null,
    rewarded: false,
    winReward: MAX_WIN_REWARD,
    endedAt: null,
  });
  await createBatch.commit();

  // Written here rather than through sendUserNotification: the challenge
  // and the invite that announces it now land in one call, and this is
  // already past every check that call would repeat.
  const {title, body} = crossUserNotificationText(
    "match_invite", challengedData.languageCode, challengerName
  );

  await db.collection("users").doc(challengedUid)
    .collection("notifications").add({
      type: "match_invite",
      title,
      body,
      data: {matchId: matchRef.id},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return {matchId: matchRef.id};
});

// ============================================================
// ASYNC PVP TURNS
//
// Playing an async match used to be a direct client write: the play screen
// ran its own countdown and wrote each answer into
// `async_matches/{id}.{role}.answers` itself. firestore.rules could stop a
// player touching the *opponent's* map, but the write it had to allow was
// "this player edits their own answers" — which is exactly what
// finalizeAsyncPvpMatch scores from, so a modified client could rewrite
// its own answers to the right ones any time before the match finalized,
// and could simply not run the clock at all.
//
// These three calls are the only way in now (firestore.rules leaves the
// client nothing on this collection but declining a challenge): the server
// stamps each question's deadline, judges every answer against it, and
// computes the finishing score itself. Turn/clock decisions live in
// async_pvp_turns.ts so they can be unit-tested; everything here is
// Firestore plumbing around them.
// ============================================================

type AsyncMatchRole = "challenger" | "challenged";

interface AsyncMatchContext {
  data: FirebaseFirestore.DocumentData;
  role: AsyncMatchRole;
  statusKey: "challengerStatus" | "challengedStatus";
  answers: Record<string, unknown>;
  deadlines: Record<string, unknown>;
  questionCount: number;
  timePerQuestionSec: number;
  finishedAlready: boolean;
}

/**
 * The caller's side of an async match, or an error if they have no side.
 * @param {FirebaseFirestore.DocumentData|undefined} data The match doc.
 * @param {string} uid Caller.
 * @return {AsyncMatchContext} Everything the turn calls need to decide.
 */
function asyncMatchContextFor(
  data: FirebaseFirestore.DocumentData | undefined, uid: string
): AsyncMatchContext {
  if (!data) {
    throw new HttpsError("not-found", "Match not found.");
  }

  const challengerUid = String(data.challengerUid || "");
  const challengedUid = cleanDocId(data.challengedUid);

  if (uid !== challengerUid && uid !== challengedUid) {
    throw new HttpsError("permission-denied", "Not your match.");
  }

  if (String(data.status || "") === "declined") {
    throw new HttpsError("failed-precondition", "Challenge was declined.");
  }

  const role: AsyncMatchRole =
    uid === challengerUid ? "challenger" : "challenged";
  const statusKey = role === "challenger" ?
    "challengerStatus" : "challengedStatus";

  const mine = (data[role] && typeof data[role] === "object") ?
    data[role] as Record<string, unknown> : {};

  return {
    data,
    role,
    statusKey,
    answers: (mine.answers && typeof mine.answers === "object") ?
      mine.answers as Record<string, unknown> : {},
    deadlines: (mine.deadlines && typeof mine.deadlines === "object") ?
      mine.deadlines as Record<string, unknown> : {},
    questionCount: Array.isArray(data.questions) ? data.questions.length : 0,
    timePerQuestionSec: safeInt(data.timePerQuestionSec, 15),
    finishedAlready: String(data[statusKey] || "pending") === "finished",
  };
}

/**
 * Opens (or resumes) the caller's turn and returns the question to serve.
 *
 * A question's deadline is stamped once and never refreshed, so backing out
 * of the screen doesn't rewind it — come back after it passed and it is
 * banked as a timeout. `remainingMs` is a duration rather than a timestamp
 * on purpose: the client counts down from it and never has to trust its own
 * device clock.
 */
export const openAsyncPvpTurn = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const matchId = cleanDocId(request.data?.matchId);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const matchRef = db.collection("async_matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const ctx = asyncMatchContextFor(snap.data(), uid);
    const keyed = await keyedQuestions(matchRef, ctx.data, tx);

    if (ctx.finishedAlready) {
      return {
        index: ctx.questionCount,
        finished: true,
        remainingMs: 0,
        answers: ctx.answers,
        verdicts: verdictsFor(keyed, ctx.answers),
      };
    }

    const turn = openTurn({
      answers: ctx.answers,
      deadlines: ctx.deadlines,
      questionCount: ctx.questionCount,
      timePerQuestionSec: ctx.timePerQuestionSec,
      nowMs: Date.now(),
    });

    const patch: Record<string, unknown> = {};
    const answers: Record<string, unknown> = {...ctx.answers};

    for (const index of turn.timedOutIndices) {
      patch[`${ctx.role}.answers.${index}`] = TIMED_OUT_ANSWER;
      answers[String(index)] = TIMED_OUT_ANSWER;
    }

    if (turn.deadlineIsNew && turn.deadlineMs !== null) {
      patch[`${ctx.role}.deadlines.${turn.index}`] = turn.deadlineMs;
    }

    if (Object.keys(patch).length > 0) {
      // Playing counts as activity, so the stale-match sweep doesn't
      // forfeit a player who is still answering.
      patch.lastUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
      tx.update(matchRef, patch);
    }

    return {
      index: turn.index,
      finished: turn.finished,
      remainingMs: turn.remainingMs,
      answers,
      verdicts: verdictsFor(keyed, answers),
    };
  });
});

/**
 * Banks one answer and stamps the next question's clock.
 *
 * The next deadline is set here rather than by a follow-up call so
 * advancing costs no round trip — which is why it has to cover the play
 * screen's reveal pause (see REVEAL_DELAY_MS).
 *
 * Anything the server can't line up with the turn it expects
 * (already answered, out of order, never opened) fails with
 * `failed-precondition`: the client's answer to all of them is the same,
 * re-open the turn and take the server's word for where it is.
 */
export const submitAsyncPvpAnswer = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const matchId = cleanDocId(request.data?.matchId);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const questionIndex = safeInt(request.data?.questionIndex, -1);
  // TIMED_OUT_ANSWER (-1) is a legitimate value: the client's own countdown
  // hitting zero closes the question as wrong without waiting for the
  // server to notice.
  const selectedIndex = safeInt(request.data?.selectedIndex, TIMED_OUT_ANSWER);

  const matchRef = db.collection("async_matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const ctx = asyncMatchContextFor(snap.data(), uid);

    if (ctx.finishedAlready) {
      throw new HttpsError("failed-precondition", "Round already closed.");
    }
    const keyed = await keyedQuestions(matchRef, ctx.data, tx);

    const resolution = resolveAnswer({
      answers: ctx.answers,
      deadlines: ctx.deadlines,
      questionCount: ctx.questionCount,
      timePerQuestionSec: ctx.timePerQuestionSec,
      nowMs: Date.now(),
    }, questionIndex, selectedIndex);

    if (resolution.kind === "out-of-range") {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }

    if (resolution.kind !== "accepted") {
      throw new HttpsError("failed-precondition", resolution.kind);
    }

    const patch: Record<string, unknown> = {
      [`${ctx.role}.answers.${questionIndex}`]: resolution.storedIndex,
      // Activity, so the stale-match sweep doesn't forfeit a player who is
      // still answering.
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (resolution.nextDeadlineMs !== null) {
      patch[`${ctx.role}.deadlines.${resolution.nextIndex}`] =
        resolution.nextDeadlineMs;
    }

    tx.update(matchRef, patch);

    const correctIndex = safeInt(keyed[questionIndex]?.answerIndex, -1);
    return {
      storedIndex: resolution.storedIndex,
      correctIndex,
      correct: resolution.storedIndex === correctIndex,
      timedOut: resolution.timedOut,
      nextIndex: resolution.nextIndex,
      nextRemainingMs: resolution.nextRemainingMs,
      finished: resolution.finished,
    };
  });
});

/**
 * Closes the caller's round: marks their side finished and stores the score.
 *
 * The score is computed here from the banked answers against the match's
 * own questions rather than taken from the client, so the value the result
 * screen shows is the same one finalizeAsyncPvpMatch settles the match on.
 * Setting the status is also what triggers that finalization.
 */
export const finishAsyncPvpMatch = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const matchId = cleanDocId(request.data?.matchId);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const matchRef = db.collection("async_matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const ctx = asyncMatchContextFor(snap.data(), uid);
    const keyed = await keyedQuestions(matchRef, ctx.data, tx);

    if (ctx.finishedAlready) {
      return {
        alreadyFinished: true,
        score: computeVerifiedPvpScore(keyed, ctx.answers),
      };
    }

    const turn = openTurn({
      answers: ctx.answers,
      deadlines: ctx.deadlines,
      questionCount: ctx.questionCount,
      timePerQuestionSec: ctx.timePerQuestionSec,
      nowMs: Date.now(),
    });

    // The last question is commonly still open here: the client submits it
    // and finishes in the same breath, and `openTurn` only reports the run
    // over once every question is banked.
    if (!turn.finished) {
      throw new HttpsError("failed-precondition", "Round not finished.");
    }

    const answers: Record<string, unknown> = {...ctx.answers};
    const patch: Record<string, unknown> = {
      [ctx.statusKey]: "finished",
      [`${ctx.role}.finishedAt`]:
        admin.firestore.FieldValue.serverTimestamp(),
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    for (const index of turn.timedOutIndices) {
      patch[`${ctx.role}.answers.${index}`] = TIMED_OUT_ANSWER;
      answers[String(index)] = TIMED_OUT_ANSWER;
    }

    const score = computeVerifiedPvpScore(keyed, answers);
    patch[`${ctx.role}.score`] = score;

    tx.update(matchRef, patch);

    return {alreadyFinished: false, score};
  });
});

// A stale one-sided async match forfeits after this long with no response
// from the other side — otherwise a losing/absent player could dodge the
// result forever, and the player who did engage never gets their reward.
const ASYNC_MATCH_FORFEIT_DAYS = 7;

/**
 * Sweeps `async_matches` where exactly one side finished and the other
 * never responded within ASYNC_MATCH_FORFEIT_DAYS, and force-completes
 * them: the side that engaged wins (same reward shape as
 * finalizeAsyncPvpMatch's normal casual-branch payout, including
 * achievement progress), the non-responder takes the loss. Both
 * challenger-pending and challenged-pending directions are already caught
 * by the same query since it only checks "exactly one side finished."
 */
export const expireStaleAsyncMatches = onSchedule(
  {schedule: "0 */6 * * *"},
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - ASYNC_MATCH_FORFEIT_DAYS * 24 * 60 * 60 * 1000
    );

    const snap = await db.collection("async_matches")
      .where("rewarded", "==", false)
      .where("lastUpdatedAt", "<", cutoff)
      .limit(100)
      .get();

    for (const doc of snap.docs) {
      await forfeitStaleAsyncMatch(doc.ref);
    }
  }
);

/**
 * @param {FirebaseFirestore.DocumentReference} matchRef Async match ref.
 * @return {Promise<void>} Resolves once the forfeit (or no-op) commits.
 */
async function forfeitStaleAsyncMatch(
  matchRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const data = snap.data();

    if (!data) return;
    if (data.rewarded === true) return;

    const challengerFinished = data.challengerStatus === "finished";
    const challengedFinished = data.challengedStatus === "finished";

    // Only forfeit the one-sided case — if neither side ever played,
    // there's nothing to award; if both finished, finalizeAsyncPvpMatch's
    // own trigger already handled it and rewarded would be true by now.
    // A declined or never-played match is still closed off as settled:
    // left `rewarded: false`, it matched the sweep's query forever, and
    // once a hundred of them piled up the oldest-first page held nothing
    // else and real forfeits were never reached.
    if (
      data.status === "declined" ||
      challengerFinished === challengedFinished
    ) {
      // A never-played challenge is also closed as expired: left as
      // `waiting_challenged` it still counted against the challenger's
      // open challenges, so they could never re-challenge that player, and
      // ten of them blocked new challenges for good.
      tx.update(matchRef, {
        rewarded: true,
        ...(data.status === "declined" ? {} : {status: "expired"}),
      });
      return;
    }

    const winnerUid = String(
      challengerFinished ? data.challengerUid : data.challengedUid
    );
    const loserUid = String(
      challengerFinished ? data.challengedUid : data.challengerUid
    );
    if (!winnerUid || !loserUid) return;

    const winnerRef = db.collection("users").doc(winnerUid);
    const loserRef = db.collection("users").doc(loserUid);

    const winnerSnap = await tx.get(winnerRef);
    const winnerUser = winnerSnap.data() || {};

    const winReward = clampWinReward(safeInt(data.winReward, 0));
    const winnerCoinClamp = clampDailyPvpCoins(winnerUser, winReward);

    const winnerNewStreak = safeInt(winnerUser.currentWinStreak1v1, 0) + 1;
    const winnerBestStreakSoFar = safeInt(winnerUser.bestWinStreak1v1, 0);

    const [
      winnerFirstWinSnap, winnerWins10Snap,
      winnerStreak5Snap, winnerWins25Snap,
    ] = await readPvpAchievementSnaps(tx, winnerUid);

    applyPvpAchievementProgress(
      tx, winnerUid, PVP_ACHIEVEMENTS[0],
      safeInt(winnerUser.wins1v1, 0) + 1, winnerFirstWinSnap,
      winnerUser.languageCode
    );
    applyPvpAchievementProgress(
      tx, winnerUid, PVP_ACHIEVEMENTS[1],
      safeInt(winnerUser.wins1v1, 0) + 1, winnerWins10Snap,
      winnerUser.languageCode
    );
    applyPvpAchievementProgress(
      tx, winnerUid, PVP_ACHIEVEMENTS[2], winnerNewStreak,
      winnerStreak5Snap, winnerUser.languageCode
    );
    applyPvpAchievementProgress(
      tx, winnerUid, PVP_ACHIEVEMENTS[3],
      safeInt(winnerUser.wins1v1, 0) + 1, winnerWins25Snap,
      winnerUser.languageCode
    );

    tx.set(winnerRef, {
      matches1v1: admin.firestore.FieldValue.increment(1),
      wins1v1: admin.firestore.FieldValue.increment(1),
      currentWinStreak1v1: winnerNewStreak,
      bestWinStreak1v1: Math.max(winnerBestStreakSoFar, winnerNewStreak),
      coins: admin.firestore.FieldValue.increment(winnerCoinClamp.payable),
      ...winnerCoinClamp.patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(loserRef, {
      matches1v1: admin.firestore.FieldValue.increment(1),
      losses1v1: admin.firestore.FieldValue.increment(1),
      currentWinStreak1v1: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.update(matchRef, {
      status: "completed",
      winnerUid,
      finishReason: "opponent_forfeited",
      rewarded: true,
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const matchId = matchRef.id;
    const winnerName = String(
      challengerFinished ?
        data.challengerDisplayName : data.challengedDisplayName
    ) || "Player";
    const loserName = String(
      challengerFinished ?
        data.challengedDisplayName : data.challengerDisplayName
    ) || "Player";
    // Scores live under each side's map (`challenger.score`), which is
    // what finishAsyncPvpMatch writes; the flat names never existed, so a
    // forfeit always went into the history as 0–0.
    const challengerScore = safeInt(data.challenger?.score, 0);
    const challengedScore = safeInt(data.challenged?.score, 0);
    const winnerScore = challengerFinished ? challengerScore : challengedScore;
    const loserScore = challengerFinished ? challengedScore : challengerScore;

    tx.set(
      winnerRef.collection("match_history").doc(matchId),
      {
        matchId,
        mode: "casual",
        ranked: false,
        result: "victory",
        opponentUid: loserUid,
        opponentName: loserName,
        myScore: winnerScore,
        opponentScore: loserScore,
        oldRating: null,
        newRating: null,
        ratingDelta: null,
        xpEarned: null,
        coinsEarned: winnerCoinClamp.payable,
        winStreak: winnerNewStreak,
        oldLeagueName: null,
        newLeagueName: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      loserRef.collection("match_history").doc(matchId),
      {
        matchId,
        mode: "casual",
        ranked: false,
        result: "defeat",
        opponentUid: winnerUid,
        opponentName: winnerName,
        myScore: loserScore,
        opponentScore: winnerScore,
        oldRating: null,
        newRating: null,
        ratingDelta: null,
        xpEarned: null,
        coinsEarned: 0,
        winStreak: 0,
        oldLeagueName: null,
        newLeagueName: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(winnerRef.collection("notifications").doc(), {
      type: "match_result",
      title: pickText(
        winnerUser.languageCode, "¡Ganaste por abandono!", "You won by forfeit!"
      ),
      body: pickText(
        winnerUser.languageCode,
        "Tu rival no respondió a tiempo. Ganaste la partida.",
        "Your opponent didn't respond in time. You won the match."
      ),
      data: {matchId: matchRef.id},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Callable replacement for pvp_season_service.dart's
 * `claimAllPendingPvpSeasonRewards`. The source data (pvp_season_stats /
 * pvp_season_history) is already server-only (rules: write:false), so the
 * reward amounts here can't be forged — this function exists purely because
 * the actual `coins` increment must move server-side once `coins` is
 * protected in firestore.rules.
 */
export const claimPvpSeasonRewards = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);
  const currentSeasonId = currentPvpSeason().id;

  return db.runTransaction(async (tx) => {
    const statsSnap = await tx.get(userRef.collection("pvp_season_stats"));
    const historySnap = await tx.get(
      userRef.collection("pvp_season_history")
    );

    const claimedSeasonIds = new Set(historySnap.docs.map((d) => d.id));

    type Pending = {
      seasonId: string;
      finalRating: number;
      bestRating: number;
      leagueId: string;
      leagueName: string;
      leagueEmoji: string;
      rewardCoins: number;
      matchesPlayed: number;
      wins: number;
      losses: number;
      draws: number;
    };

    // Mirrors lib/services/pvp_league_service.dart's `masterTierIndex` +
    // lib/services/pvp_season_service.dart's `rewardForRating` — Master has
    // no rating ceiling, so a flat reward regardless of rating meant
    // progression stopped paying off once a player got there.
    const rewardForLeague = (league: PvpLeagueInfo, rating: number): number => {
      if (league.id !== "master") {
        switch (league.id) {
        case "diamond": return 40;
        case "platinum": return 20;
        case "gold": return 10;
        case "silver": return 5;
        default: return 2;
        }
      }

      if (rating >= 2200) return 150;
      if (rating >= 2050) return 110;
      return 80;
    };

    const pending: Pending[] = [];

    for (const doc of statsSnap.docs) {
      const seasonId = doc.id;
      if (seasonId.localeCompare(currentSeasonId) >= 0) continue;
      if (claimedSeasonIds.has(seasonId)) continue;

      const data = doc.data();
      const finalRating = safeInt(data.finalRating, DEFAULT_RATING);
      const bestRating = safeInt(data.bestRating, finalRating);
      const bestLeague = leagueForRating(bestRating);

      pending.push({
        seasonId,
        finalRating,
        bestRating,
        leagueId: bestLeague.id,
        leagueName: bestLeague.name,
        leagueEmoji: bestLeague.emoji,
        rewardCoins: rewardForLeague(bestLeague, bestRating),
        matchesPlayed: safeInt(data.matchesPlayed, 0),
        wins: safeInt(data.wins, 0),
        losses: safeInt(data.losses, 0),
        draws: safeInt(data.draws, 0),
      });
    }

    pending.sort((a, b) => b.seasonId.localeCompare(a.seasonId));

    if (pending.length === 0) {
      return {claimedCount: 0, totalCoins: 0, rewards: []};
    }

    let totalCoins = 0;
    const results = [];

    for (const reward of pending) {
      totalCoins += reward.rewardCoins;

      const finalLeague = leagueForRating(reward.finalRating);
      const historyRef = userRef
        .collection("pvp_season_history")
        .doc(reward.seasonId);

      tx.set(
        historyRef,
        {
          seasonId: reward.seasonId,
          finalRating: reward.finalRating,
          finalLeagueId: finalLeague.id,
          finalLeagueName: finalLeague.name,
          finalLeagueEmoji: finalLeague.emoji,
          bestRating: reward.bestRating,
          bestLeagueId: reward.leagueId,
          bestLeagueName: reward.leagueName,
          bestLeagueEmoji: reward.leagueEmoji,
          matchesPlayed: reward.matchesPlayed,
          wins: reward.wins,
          losses: reward.losses,
          draws: reward.draws,
          rewardCoins: reward.rewardCoins,
          rewardBasedOn: "bestRating",
          claimedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      results.push({
        seasonId: reward.seasonId,
        leagueId: reward.leagueId,
        leagueName: reward.leagueName,
        finalRating: reward.finalRating,
        bestRating: reward.bestRating,
        rewardCoins: reward.rewardCoins,
        alreadyClaimed: false,
      });
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(totalCoins),
        lastClaimedPvpSeasonId: pending[0].seasonId,
        lastPvpSeasonRewardCoins: totalCoins,
        lastPvpSeasonRewardCount: pending.length,
        lastPvpSeasonRewardClaimedAt:
          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      claimedCount: results.length,
      totalCoins,
      rewards: results,
    };
  });
});

// ============================================================
// DAILY CHALLENGE
// ============================================================

const DAILY_LEVEL_UP_COINS = 15;
const DAILY_QUESTION_LIMIT = 60;
// Server-only: the day's shared question set, including answerIndex. No
// firestore.rules entry, so clients can't read it — they only ever see the
// copy in their own daily_challenges doc.
const DAILY_QUESTION_SET_COLLECTION = "daily_question_sets";
const DAILY_DURATION_SECONDS = 120;

type LeagueInfo = {
  id: string;
  name: string;
  emoji: string;
  minScore: number;
  colorValue: number;
};

// Mirrors lib/services/league_service.dart's `leagues` list exactly.
const LEAGUES: LeagueInfo[] = [
  {
    id: "bronze", name: "Bronze", emoji: "🥉", minScore: 0,
    colorValue: 0xFFCD7F32,
  },
  {
    id: "silver", name: "Silver", emoji: "🥈", minScore: 300,
    colorValue: 0xFFC0C0C0,
  },
  {
    id: "gold", name: "Gold", emoji: "🥇", minScore: 700,
    colorValue: 0xFFFFD700,
  },
  {
    id: "diamond", name: "Diamond", emoji: "💎", minScore: 1200,
    colorValue: 0xFF6EC6FF,
  },
  {
    id: "master", name: "Master", emoji: "👑", minScore: 2000,
    colorValue: 0xFF9C27B0,
  },
];

/**
 * Mirrors lib/services/league_service.dart's `getLeagueFromScore`.
 * @param {number} score Player's league score.
 * @return {LeagueInfo} Matching league.
 */
function getLeagueFromScore(score: number): LeagueInfo {
  let current = LEAGUES[0];
  for (const league of LEAGUES) {
    if (score >= league.minScore) current = league;
  }
  return current;
}


/**
 * Checks whether `dateId` (yyyy-MM-dd) is exactly one day before `today`.
 * @param {string} dateId Previous play date.
 * @param {string} today Today's date id.
 * @return {boolean} True if dateId is yesterday relative to today.
 */
function isYesterday(dateId: string, today: string): boolean {
  const last = new Date(`${dateId}T00:00:00Z`);
  const todayDate = new Date(`${today}T00:00:00Z`);
  if (isNaN(last.getTime()) || isNaN(todayDate.getTime())) return false;
  const diffDays = Math.round(
    (todayDate.getTime() - last.getTime()) / (24 * 60 * 60 * 1000)
  );
  return diffDays === 1;
}

type QuestionAnswer = { questionIndex: number; selectedIndex: number };

/**
 * Recomputes a player's real correct/totalAnswered from their actual
 * submitted per-question answers, ignoring the `correct`/`totalAnswered`
 * a client reports directly. `questions` lives on the same session doc
 * the client already reads to render the quiz (Daily Challenge's
 * createTodaySession, or Solo Levels' sessions_fixed/sessions_ai), so
 * this needs no extra fetch beyond that doc.
 * @param {unknown} questions The session doc's `questions` array.
 * @param {QuestionAnswer[]} answers The player's submitted answers, in
 * the order they were given (may repeat a questionIndex if the session's
 * question pool wrapped around during play, as Daily Challenge allows).
 * @param {number} maxAnswers Hard cap on how many answers count, matching
 * the most questions this session could legitimately contain.
 * @return {{correct: number, totalAnswered: number}} Verified counts.
 */
function computeVerifiedQuizResult(
  questions: unknown, answers: QuestionAnswer[], maxAnswers: number
): {correct: number; totalAnswered: number} {
  const list = Array.isArray(questions) ? questions : [];

  let correct = 0;
  let totalAnswered = 0;

  for (const a of answers) {
    if (totalAnswered >= maxAnswers) break;

    const q = list[a.questionIndex] as Record<string, unknown> | undefined;
    if (!q) continue;

    totalAnswered++;
    const correctIndex = safeInt(q.answerIndex ?? q.correctIndex, -1);
    if (a.selectedIndex === correctIndex) correct++;
  }

  return {correct, totalAnswered};
}

/**
 * Server-authoritative Daily Challenge reward grant, replacing
 * DailyChallengeService.saveResult's client-side transaction.
 * `dateId`/`weekId` are accepted from the client (they're just bucket
 * keys matching what createTodaySession already computed locally — not
 * economically sensitive). The client's reported `correct`/`totalAnswered`
 * are used only for a fast shape-check; the real values that determine
 * the reward are recomputed from `answers` (this player's actual selected
 * option per question) against the session doc's own stored `questions`,
 * so a modified client reporting an inflated correct count can no longer
 * affect the real result.
 */
export const submitDailyChallengeResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  // `correct`/`totalAnswered` are only used for a fast request-shape
  // check here — the real, reward-determining values are recomputed
  // below from the answers the server banked as they were given.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotalAnswered = safeInt(request.data?.totalAnswered, -1);
  const dateId = String(request.data?.dateId || "");
  const weekId = cleanDocId(request.data?.weekId);

  if (
    reportedCorrect < 0 || reportedTotalAnswered < 0 ||
    reportedCorrect > reportedTotalAnswered ||
    reportedTotalAnswered > DAILY_QUESTION_LIMIT
  ) {
    throw new HttpsError("invalid-argument", "Invalid answer counts.");
  }

  // Both ids are client-supplied and decide which documents this write
  // lands in, so neither may be taken on trust: the date has to be a real
  // one near now, and the week has to be the one that date falls in.
  await assertPlausibleDateId(uid, dateId);
  if (weekId !== weekIdForDateId(dateId)) {
    throw new HttpsError("invalid-argument", "Invalid dateId/weekId.");
  }

  const userRef = db.collection("users").doc(uid);
  const dailyRef = userRef.collection("daily_challenges").doc(dateId);
  const leaderboardRef = db
    .collection("daily_leaderboards").doc(dateId)
    .collection("players").doc(uid);
  const weeklyParticipationRef = userRef
    .collection("weekly_participation").doc(weekId);
  const dailyStreakAchievementRef = userRef
    .collection("achievements").doc("daily_streak_7");
  const dailyStreak21AchievementRef = userRef
    .collection("achievements").doc("daily_streak_21");

  return db.runTransaction(async (tx) => {
    const dailySnap = await tx.get(dailyRef);
    const userSnap = await tx.get(userRef);
    const dailyStreakAchievementSnap = await tx.get(dailyStreakAchievementRef);
    const dailyStreak21AchievementSnap =
      await tx.get(dailyStreak21AchievementRef);
    const weeklyParticipationSnap = await tx.get(weeklyParticipationRef);

    const alreadyPlayed = dailySnap.data()?.played === true;

    if (alreadyPlayed) {
      const data = dailySnap.data() || {};
      const userData = userSnap.data() || {};
      const userXp = safeInt(userData.xp, 0);
      const level = levelForXp(userXp);

      return {
        saved: false,
        alreadyPlayed: true,
        correct: safeInt(data.correct, reportedCorrect),
        totalAnswered: safeInt(data.totalAnswered, reportedTotalAnswered),
        coinsEarned: safeInt(data.coinsEarned, 0),
        streak: safeInt(data.streak ?? userData.dailyStreak, 0),
        streakBonusCoins: safeInt(data.streakBonusCoins, 0),
        levelUpBonusCoins: safeInt(data.levelUpBonusCoins, 0),
        score: safeInt(data.score, 0),
        leveledUp: false,
        oldLevel: level,
        newLevel: level,
        xpEarned: safeInt(data.xpEarned, 0),
      };
    }

    // A date at or before the last one scored would be an extra daily —
    // see dailySubmissionCheck, which already guards starting one.
    const lastScored = userSnap.data()?.lastDailyPlayed;
    if (lastScored && dateId <= String(lastScored)) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Ya jugaste el reto diario. Vuelve mañana por el siguiente.",
        "You've already played the Daily Challenge. Come back tomorrow " +
          "for the next one."
      );
    }

    // No session document means this player never started today's
    // challenge through ensureDailyChallengeSession — there are no stored
    // `questions` to score against, so scoring would silently yield 0
    // correct while still advancing the streak and writing a leaderboard
    // row. A real play always has a session; refuse instead.
    if (!dailySnap.exists) {
      throw new HttpsError(
        "failed-precondition", "No daily challenge session for that date."
      );
    }

    // No more answers than the time since the server started the round
    // allows — see maxAnswersForElapsed.
    const startedAt = dailySnap.data()?.startedAt as
      admin.firestore.Timestamp | undefined;
    const answerCap = startedAt ? maxAnswersForElapsed(
      Date.now() - startedAt.toMillis(), DAILY_QUESTION_LIMIT
    ) : DAILY_QUESTION_LIMIT;

    // Scored from the answers the server judged as they came in
    // (answerDailyQuestion), not from a list the client sends at the end.
    const banked = mergeRecordedAnswers(
      dailySnap.data()?.answers as Record<string, unknown> | undefined, []
    );
    const keyed = await keyedQuestions(dailyRef, dailySnap.data() || {}, tx);
    const {correct, totalAnswered} = computeVerifiedQuizResult(
      keyed, banked.slice(0, answerCap), DAILY_QUESTION_LIMIT
    );
    const coinsEarned = calculateDailyCoinsEarned(correct);

    const userData = userSnap.data() || {};

    const previousStreak = safeInt(userData.dailyStreak, 0);
    const lastDailyPlayed = userData.lastDailyPlayed ?
      String(userData.lastDailyPlayed) : null;

    const username = String(
      userData.username || userData.displayName || "Player"
    );
    const avatarId = String(userData.avatarId || "avatar_1");
    const frameId = String(userData.equippedFrame || "");
    const bestLeagueId = String(userData.bestLeagueId || "");

    const currentXp = safeInt(userData.xp, 0);
    const oldLevel = levelForXp(currentXp);

    const xpEarned = calculateDailyXpEarned(correct, totalAnswered);
    const newXp = currentXp + xpEarned;
    const newLevel = levelForXp(newXp);
    const leveledUp = newLevel > oldLevel;

    const levelUpBonusCoins = leveledUp ?
      (newLevel - oldLevel) * DAILY_LEVEL_UP_COINS : 0;

    const newStreak = lastDailyPlayed && isYesterday(lastDailyPlayed, dateId) ?
      previousStreak + 1 : 1;

    // Progress for this achievement is written here (rather than by a
    // client-side follow-up call) since completed/progress/claimed are
    // locked against direct client writes for this id in firestore.rules —
    // this is the one place newStreak is already computed authoritatively.
    applyPvpAchievementProgress(
      tx, uid, {id: "daily_streak_7", title: "Weekly Habit", target: 7},
      newStreak, dailyStreakAchievementSnap, userData.languageCode
    );
    applyPvpAchievementProgress(
      tx, uid,
      {id: "daily_streak_21", title: "Iron Consistency", target: 21},
      newStreak, dailyStreak21AchievementSnap, userData.languageCode
    );

    const streakBonusCoins = calculateDailyStreakBonusCoins(newStreak);
    const totalCoinsToAdd = coinsEarned + streakBonusCoins + levelUpBonusCoins;

    const score = calculateDailyScore(correct, totalAnswered, newStreak);
    const totalLeagueScore = safeInt(userData.leagueScore, 0) + score;
    const league = getLeagueFromScore(totalLeagueScore);

    // A week is played in one league: the one the player was in when the
    // week began. Promotion takes effect from next week. Writing to the
    // current league instead split a promoted player's score across two
    // boards and left a stale row on the old one, while the reward claim
    // ranked their whole week against the new board's partial scores.
    const weekLeagueId = weeklyParticipationSnap.data()?.leagueId;
    const weekLeague = LEAGUES.find((l) => l.id === weekLeagueId) ?? league;

    const weeklyRef = db
      .collection("weekly_leagues").doc(weekId)
      .collection(weekLeague.id).doc(uid);

    const wrongAnswers = Math.max(totalAnswered - correct, 0);
    const totalQuestionsAnswered = safeInt(userData.correctAnswers, 0) +
      safeInt(userData.wrongAnswers, 0) + correct + wrongAnswers;

    tx.set(dailyRef, {
      dateId,
      played: true,
      correct,
      totalAnswered,
      coinsEarned,
      streak: newStreak,
      streakBonusCoins,
      levelUpBonusCoins,
      totalCoinsEarned: totalCoinsToAdd,
      score,
      xpEarned,
      oldLevel,
      newLevel,
      leveledUp,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const userPatch: Record<string, unknown> = {
      username,
      displayName: username,
      avatarId,
      dailyStreak: newStreak,
      // Against the stored record, not the streak this one continued: a
      // broken streak used to overwrite a 30-day record with 2.
      maxDailyStreak: Math.max(
        safeInt(userData.maxDailyStreak, 0), previousStreak, newStreak
      ),
      lastDailyPlayed: dateId,
      gamesPlayed: admin.firestore.FieldValue.increment(1),
      correctAnswers: admin.firestore.FieldValue.increment(correct),
      wrongAnswers: admin.firestore.FieldValue.increment(wrongAnswers),
      xp: admin.firestore.FieldValue.increment(xpEarned),
      level: newLevel,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      leagueScore: totalLeagueScore,
      leagueId: league.id,
      leagueName: league.name,
    };

    if (totalCoinsToAdd > 0) {
      userPatch.coins = admin.firestore.FieldValue.increment(totalCoinsToAdd);
    }

    const userBestDailyScore = safeInt(userData.bestDailyScore, 0);
    if (score > userBestDailyScore) {
      userPatch.bestDailyScore = score;
    }

    Object.assign(
      userPatch,
      questionCountAvatarUnlockPatch(
        userData.unlockedAvatars, totalQuestionsAnswered
      )
    );

    tx.set(userRef, userPatch, {merge: true});

    tx.set(leaderboardRef, {
      uid,
      username,
      displayName: username,
      avatarId,
      equippedFrame: frameId,
      bestLeagueId,
      dateId,
      correct,
      totalAnswered,
      score,
      streak: newStreak,
      coinsEarned,
      streakBonusCoins,
      levelUpBonusCoins,
      xpEarned,
      level: newLevel,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      leagueId: league.id,
      leagueName: league.name,
    }, {merge: true});

    tx.set(weeklyRef, {
      uid,
      username,
      displayName: username,
      avatarId,
      equippedFrame: frameId,
      bestLeagueId,
      weekId,
      leagueId: weekLeague.id,
      leagueName: weekLeague.name,
      weeklyScore: admin.firestore.FieldValue.increment(score),
      level: newLevel,
      streak: newStreak,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(weeklyParticipationRef, {
      weekId,
      leagueId: weekLeague.id,
      leagueName: weekLeague.name,
      weeklyScore: admin.firestore.FieldValue.increment(score),
      lastDailyScore: score,
      level: newLevel,
      streak: newStreak,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      saved: true,
      alreadyPlayed: false,
      correct,
      totalAnswered,
      totalQuestionsAnswered,
      coinsEarned,
      streak: newStreak,
      streakBonusCoins,
      levelUpBonusCoins,
      score,
      leveledUp,
      oldLevel,
      newLevel,
      xpEarned,
    };
  });
});

/**
 * Formats a UTC Date as yyyy-MM-dd, matching the dateId format used
 * throughout (todayDateId in daily_challenge_service.dart).
 * @param {Date} date Date to format (interpreted in UTC).
 * @return {string} yyyy-MM-dd.
 */
function formatDateId(date: Date): string {
  const y = date.getUTCFullYear().toString().padStart(4, "0");
  const m = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = date.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * `dateId` (yyyy-MM-dd), `days` days earlier.
 * @param {string} dateId Reference date id.
 * @param {number} days Number of days to subtract.
 * @return {string} The resulting date id.
 */
function dateIdMinusDays(dateId: string, days: number): string {
  const d = new Date(`${dateId}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return formatDateId(d);
}

/**
 * Question ids served on the last 2 Daily Challenges, so today's draw can
 * avoid repeating them.
 * @param {string} dateId Today's date id.
 * @return {Promise<Set<string>>} Recently-served `sourceQuestionId`s.
 */
async function recentlyUsedDailyQuestionIds(
  dateId: string
): Promise<Set<string>> {
  const ids = new Set<string>();

  // Read off the shared day sets rather than one player's history: the day
  // is the same for everyone now, so "recently served" is a property of the
  // day, not of who is asking.
  for (let i = 1; i <= 2; i++) {
    const pastDateId = dateIdMinusDays(dateId, i);
    const snap = await db.collection(DAILY_QUESTION_SET_COLLECTION)
      .doc(pastDateId).get();
    const questions = snap.data()?.questions;
    if (!Array.isArray(questions)) continue;

    for (const q of questions) {
      if (q && typeof q === "object") {
        const sourceQuestionId =
          (q as Record<string, unknown>).sourceQuestionId;
        if (sourceQuestionId) ids.add(String(sourceQuestionId));
      }
    }
  }

  return ids;
}

/**
 * The one question set everybody plays on [dateId], drawn once and reused.
 *
 * Each player used to draw their own random sixty, which meant the daily
 * leaderboard ranked people who had answered different questions — the
 * board compared scores that were never comparable. Drawing once per date
 * fixes that, and costs one document read per player instead of sixty.
 *
 * Two players can race here on the day's first play. The loser's draw is
 * discarded rather than written, so everyone still ends up on one set; a
 * transaction would only save a wasted read.
 * @param {string} dateId Day to build the set for.
 * @return {Promise<Record<string, unknown>[]>} The day's questions.
 */
async function loadSharedDailyQuestions(
  dateId: string
): Promise<Record<string, unknown>[]> {
  const setRef = db.collection(DAILY_QUESTION_SET_COLLECTION).doc(dateId);

  const existing = await setRef.get();
  const cached = existing.data()?.questions;
  if (Array.isArray(cached) && cached.length > 0) {
    return cached as Record<string, unknown>[];
  }

  const excludeQuestionIds = await recentlyUsedDailyQuestionIds(dateId);
  const questions = await loadRandomDailyQuestions(excludeQuestionIds);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(setRef);
    if (Array.isArray(snap.data()?.questions)) return;

    tx.set(setRef, {
      dateId,
      questions,
      builtAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  const settled = await setRef.get();
  const stored = settled.data()?.questions;
  return Array.isArray(stored) ?
    stored as Record<string, unknown>[] : questions;
}

/**
 * Mirrors DailyChallengeService's `loadRandomQuestions` — reads every
 * active fixed-pool category/difficulty question bank and returns a
 * random `DAILY_QUESTION_LIMIT`-sized subset, preferring questions not in
 * `excludeQuestionIds`.
 * @param {Set<string>} excludeQuestionIds Recently-served question ids to
 * avoid repeating when enough fresh ones are available.
 * @return {Promise<Record<string, unknown>[]>} The chosen questions.
 */
// DailyPoolEntry now lives in ./daily_question_set, next to the selection
// rules that operate on it.

// The fixed question bank is admin-seeded and barely changes, but every
// player opening the Daily Challenge used to re-read all of it —
// categories x 3 difficulties x pool size documents — just to pick
// DAILY_QUESTION_LIMIT of them. Caching an index of *where* each question
// lives turns that into one read plus only the questions actually served.
// The TTL is what lets newly seeded questions appear without any manual
// cache busting.
const DAILY_POOL_INDEX_TTL_MS = 24 * 60 * 60 * 1000;
// Keeps the cache document well inside Firestore's 1 MiB limit at roughly
// 60 bytes per entry.
const DAILY_POOL_INDEX_MAX_ENTRIES = 10000;

interface DailyQuestionIndex {
  /** Where every indexed question lives. */
  entries: DailyPoolEntry[];
  /**
   * Categories whose every difficulty was indexed before the entry cap
   * cut the scan short.
   *
   * Needed because a category the cap truncated *looks* identical to one
   * that simply has no questions at a given difficulty — both come back
   * as an empty filter. Callers that pick per difficulty must not confuse
   * the two: treating "truncated" as "empty" silently serves whatever
   * difficulty did make it into the index. Only categories listed here
   * are safe to answer from the index alone.
   */
  completeCategories: string[];
}

/**
 * Scans every active category's pools and records where each question
 * lives. Expensive, so it runs once per TTL rather than once per player.
 * @return {Promise<DailyQuestionIndex>} Index, and which categories it
 * covers completely.
 */
async function buildDailyQuestionIndex(): Promise<DailyQuestionIndex> {
  const categoriesSnap = await db.collection("fixed_categories")
    .where("isActive", "==", true).get();

  let categoryIds = categoriesSnap.docs.map((d) => d.id);

  if (categoryIds.length === 0) {
    const poolsSnap = await db.collection("fixed_pools").get();
    categoryIds = poolsSnap.docs.map((d) => d.id);
  }

  if (categoryIds.length === 0) {
    throw new HttpsError(
      "failed-precondition", "No active daily categories."
    );
  }

  const entries: DailyPoolEntry[] = [];
  const completeCategories: string[] = [];

  for (const categoryId of categoryIds) {
    let truncated = false;

    for (const difficulty of [1, 2, 3]) {
      const snap = await db.collection("fixed_pools").doc(categoryId)
        .collection(`difficulty_${difficulty}`).doc("pool")
        .collection("questions").get();

      for (const doc of snap.docs) {
        if (entries.length >= DAILY_POOL_INDEX_MAX_ENTRIES) {
          truncated = true;
          break;
        }
        entries.push({c: categoryId, d: difficulty, q: doc.id});
      }

      if (truncated) break;
    }

    // The cap ends the whole scan, as before — every category after this
    // one is simply absent, which callers already handle. What changes is
    // that the category we stopped *inside* isn't claimed as complete.
    if (truncated) return {entries, completeCategories};

    completeCategories.push(categoryId);
  }

  return {entries, completeCategories};
}

/**
 * The cached question index, rebuilt when it's missing or past its TTL.
 * @return {Promise<DailyQuestionIndex>} Index, and which categories it
 * covers completely.
 */
async function loadDailyQuestionIndex(): Promise<DailyQuestionIndex> {
  // Every match and weekly round now reads it, so a warm instance keeps it
  // for a few minutes rather than reading the document each time.
  if (memoQuestionIndex && Date.now() < memoQuestionIndex.untilMs) {
    return memoQuestionIndex.index;
  }
  const index = await readDailyQuestionIndex();
  if (index.entries.length > 0) {
    memoQuestionIndex = {index, untilMs: Date.now() + QUESTION_INDEX_MEMO_MS};
  }
  return index;
}

/** How long a warm instance reuses the question index it read. */
const QUESTION_INDEX_MEMO_MS = 10 * 60 * 1000;
let memoQuestionIndex: {index: DailyQuestionIndex; untilMs: number} | null =
  null;

/**
 * The cached question index from Firestore, rebuilt when it's missing or
 * past its TTL.
 * @return {Promise<DailyQuestionIndex>} Index, and which categories it
 * covers completely.
 */
async function readDailyQuestionIndex(): Promise<DailyQuestionIndex> {
  const ref = db.collection("caches").doc("daily_question_index");
  const snap = await ref.get();
  const data = snap.data();

  const builtAt = data?.builtAt as admin.firestore.Timestamp | undefined;
  const cached = (data?.entries as DailyPoolEntry[] | undefined) || [];
  const cachedComplete = data?.completeCategories as string[] | undefined;
  const isFresh = builtAt !== undefined &&
    Date.now() - builtAt.toMillis() < DAILY_POOL_INDEX_TTL_MS;

  // A document written before `completeCategories` existed can't say which
  // categories it covers, and assuming "all" is the unsafe direction — so
  // it's rebuilt rather than trusted. Costs one extra scan, once.
  if (cached.length > 0 && isFresh && cachedComplete !== undefined) {
    return {entries: cached, completeCategories: cachedComplete};
  }

  const index = await buildDailyQuestionIndex();

  if (index.entries.length > 0) {
    // Two players can race into a rebuild and both write. The write is
    // idempotent, so the loser costs one duplicate scan, never a wrong
    // result — not worth a transaction to prevent.
    await ref.set({
      entries: index.entries,
      completeCategories: index.completeCategories,
      count: index.entries.length,
      builtAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return index;
}

/**
 * Picks this player's daily question set from the cached index, then reads
 * only the questions being served.
 * @param {Set<string>} excludeQuestionIds Recently served question ids.
 * @return {Promise<Record<string, unknown>[]>} The chosen questions.
 */
async function loadRandomDailyQuestions(
  excludeQuestionIds: Set<string>
): Promise<Record<string, unknown>[]> {
  // Draws across every category at once, so a truncated index just means
  // a smaller pool to draw from — never the wrong difficulty.
  const {entries} = await loadDailyQuestionIndex();

  if (entries.length === 0) {
    throw new HttpsError("failed-precondition", "No questions in pools.");
  }

  const shuffled = [...entries];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }

  // Easy first, hardest last. The daily is a timed sprint, so shuffling the
  // tiers together turned "how far did you get" into a lottery over which
  // difficulties happened to land early.
  const selected = orderByAscendingDifficulty(selectDailyEntries(
    shuffled, excludeQuestionIds, DAILY_QUESTION_LIMIT
  ));

  if (selected.length === 0) {
    throw new HttpsError("failed-precondition", "No questions in pools.");
  }

  const docs = await db.getAll(...selected.map((entry) =>
    db.collection("fixed_pools").doc(entry.c)
      .collection(`difficulty_${entry.d}`).doc("pool")
      .collection("questions").doc(entry.q)
  ));

  const questions: Record<string, unknown>[] = [];
  docs.forEach((doc, i) => {
    // A question deleted since the index was built is simply skipped; the
    // next rebuild drops it for good.
    if (!doc.exists) return;
    const entry = selected[i];
    questions.push({
      ...doc.data(),
      sourceCategoryId: entry.c,
      sourceDifficulty: entry.d,
      sourceQuestionId: entry.q,
    });
  });

  if (questions.length === 0) {
    throw new HttpsError("failed-precondition", "No questions in pools.");
  }

  return questions;
}

/**
 * Picks a fixed-category solo level's questions, preferring the cached
 * index over reading the whole difficulty pool.
 *
 * Opening a fixed level used to read every question in the pool just to
 * keep ten of them — on the single most common action in the game. The
 * index built for the Daily Challenge already records exactly where each
 * fixed question lives, so the same cached document answers "which ids are
 * in this category at this difficulty", and only the ten actually served
 * get read.
 *
 * Both paths run the same seeded pick over ids in the pool's own document
 * order, so which path answered is invisible to the player.
 * @param {string} uid Player, part of the deterministic seed.
 * @param {string} categoryId Fixed category being played.
 * @param {number} levelNumber Level being opened.
 * @return {Promise<object>} Chosen questions, difficulty used, and seed.
 */
async function loadFixedLevelQuestions(
  uid: string,
  categoryId: string,
  levelNumber: number
): Promise<{
  questions: Record<string, unknown>[];
  difficulty: number;
  seed: number;
}> {
  const preferred = difficultyForLevel(levelNumber);
  const difficulties = Array.from(new Set([preferred, 1, 2, 3]));

  // Seeded per difficulty, not per level: the levels sharing a band have to
  // agree on the shuffle for sliceForLevel to keep their slates disjoint.
  // Seeding per level made each one an independent draw from the whole
  // pool, so two levels in a band overlapped by about three questions.
  const seedFor = (difficulty: number) =>
    fnv1a32(`${uid}|${categoryId}|d${difficulty}`);

  const questionsRef = (difficulty: number) =>
    db.collection("fixed_pools").doc(categoryId)
      .collection(`difficulty_${difficulty}`).doc("pool")
      .collection("questions");

  // Only a category the index covers *completely* can be answered from it.
  // A category the entry cap cut short reports empty for the difficulties
  // that didn't fit, which is indistinguishable from having none — and the
  // loop below would then quietly serve whichever difficulty did fit,
  // handing a level-30 player level-1 questions. Anything not known
  // complete (inactive, newly seeded, or truncated) falls through to the
  // full read instead.
  const index = await loadDailyQuestionIndex()
    .catch(() => ({entries: [], completeCategories: []} as DailyQuestionIndex));
  const indexCovers = index.completeCategories.includes(categoryId);

  for (const difficulty of indexCovers ? difficulties : []) {
    const ids = index.entries
      .filter((entry) => entry.c === categoryId && entry.d === difficulty)
      .map((entry) => entry.q);

    if (ids.length === 0) continue;

    const seed = seedFor(difficulty);
    const order = seededShuffleIndices(ids.length, seed);
    const picked = sliceForLevel(order, levelNumber).map((i) => ids[i]);

    const docs = await db.getAll(
      ...picked.map((id) => questionsRef(difficulty).doc(id))
    );
    const questions = docs
      .filter((doc) => doc.exists)
      .map((doc) => doc.data() as Record<string, unknown>);

    if (questions.length === picked.length) {
      return {questions, difficulty, seed};
    }

    // Fewer questions back than ids asked for means the index outlived the
    // pool — a question was deleted after it was built, and the index has a
    // day to notice. Serving the short slate anyway would start the level
    // with three questions instead of ten (`total` follows the count), with
    // nothing to distinguish it from a level that is meant to be short. The
    // index is proven stale for this category, so stop trusting it here
    // rather than trying the next difficulty from the same stale data: the
    // full read below re-runs from the preferred difficulty against what the
    // pool actually holds.
    break;
  }

  for (const difficulty of difficulties) {
    const snap = await questionsRef(difficulty).get();
    if (snap.empty) continue;

    const seed = seedFor(difficulty);
    const order = seededShuffleIndices(snap.docs.length, seed);
    const questions = sliceForLevel(order, levelNumber)
      .map((i) => snap.docs[i].data());

    return {questions, difficulty, seed};
  }

  return {questions: [], difficulty: 0, seed: seedFor(preferred)};
}

// How long after the round started an answer is still accepted. The app
// pauses its own 120-second clock while it waits for each verdict, so the
// round can run a little longer in real time than its nominal length.
const DAILY_ANSWER_GRACE_MS = 30_000;

/**
 * Judges one Daily Challenge answer and banks it.
 *
 * The day's questions reach the app without their answers (the key is in
 * the session's `secret/answers`), so this is how it learns whether an
 * answer was right; the first answer per question is final, and only
 * banked answers are scored at the end. The Daily Challenge costs no
 * lives.
 */
export const answerDailyQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const dateId = String(request.data?.dateId || "");
  const questionIndex = safeInt(request.data?.questionIndex, -1);
  const selectedIndex = safeInt(
    request.data?.selectedIndex, TIMED_OUT_ANSWER
  );
  await assertPlausibleDateId(uid, dateId);
  if (questionIndex < 0) {
    throw new HttpsError("invalid-argument", "Invalid answer.");
  }

  const dailyRef = db.collection("users").doc(uid)
    .collection("daily_challenges").doc(dateId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(dailyRef);
    const data = snap.data();
    if (!data || data.played === true) {
      throw new HttpsError("failed-precondition", "No open daily.");
    }
    const keyed = await keyedQuestions(dailyRef, data, tx);
    if (questionIndex >= keyed.length) {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }
    const correctIndex = safeInt(keyed[questionIndex]?.answerIndex, -1);

    const banked = (data.answers && typeof data.answers === "object") ?
      data.answers as Record<string, unknown> : {};
    const key = String(questionIndex);
    if (Object.prototype.hasOwnProperty.call(banked, key)) {
      const stored = safeInt(banked[key], TIMED_OUT_ANSWER);
      return {correct: stored === correctIndex, correctIndex};
    }

    const startedAt = data.startedAt as admin.firestore.Timestamp | undefined;
    const durationMs = safeInt(data.durationSeconds, DAILY_DURATION_SECONDS) *
      1000;
    if (startedAt &&
        Date.now() > startedAt.toMillis() + durationMs +
          DAILY_ANSWER_GRACE_MS) {
      throw new HttpsError("failed-precondition", "Time is up.");
    }

    const correct = selectedIndex === correctIndex;
    tx.set(dailyRef, {
      answers: {[key]: selectedIndex},
      results: {[key]: {correct, correctIndex}},
    }, {merge: true});
    return {correct, correctIndex};
  });
});

/**
 * Server-authoritative replacement for daily_challenge_service.dart's
 * `createTodaySession` — a client used to read the real fixed-pool
 * question data and write its own copy straight into
 * `daily_challenges/{dateId}`, which `submitDailyChallengeResult` then
 * trusted as ground truth (via computeVerifiedQuizResult). That let a
 * modified client write a session with self-chosen "correct" answers
 * unrelated to the real content. This function does the same
 * question-selection the client used to do, but server-side against the
 * authoritative `fixed_pools`/`fixed_categories` data, then writes the
 * session doc itself — firestore.rules now denies client `create` on
 * `daily_challenges`, so this is the only thing that can populate it.
 */
export const ensureDailyChallengeSession = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const dateId = String(request.data?.dateId || "");
  // Bounded to a real date near now: a session is what makes a
  // submission scoreable, so letting one be opened for an arbitrary date
  // would hand back the streak-farming path submitDailyChallengeResult
  // now refuses.
  await assertPlausibleDateId(uid, dateId);

  const userRef = db.collection("users").doc(uid);
  const dailyRef = userRef.collection("daily_challenges").doc(dateId);

  const existing = await dailyRef.get();
  if (existing.exists) {
    await moveSessionKeyOut(dailyRef, existing.data() || {});
    return {created: false};
  }

  // Everyone who plays today gets this same set, in this same order.
  const questions = await loadSharedDailyQuestions(dateId);

  // Server-only (no rule matches users/{uid}/server): the player can't
  // reset their own count.
  const limitsRef = userRef.collection("server").doc("daily_limits");

  await db.runTransaction(async (tx) => {
    const [snap, userSnap, limitsSnap] = await Promise.all([
      tx.get(dailyRef),
      tx.get(userRef),
      tx.get(limitsRef),
    ]);
    if (snap.exists) return;

    const lastPlayed = userSnap.data()?.lastDailyPlayed;
    const recent = ((limitsSnap.data()?.startsMs as unknown[]) || [])
      .map((ms) => Number(ms));
    const check = dailySubmissionCheck(
      lastPlayed ? String(lastPlayed) : undefined, recent, dateId, Date.now()
    );
    if (!check.ok) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Ya jugaste el reto diario. Vuelve mañana por el siguiente.",
        "You've already played the Daily Challenge. Come back tomorrow " +
          "for the next one."
      );
    }
    tx.set(limitsRef, {startsMs: check.recentMs});

    const split = splitAnswerKey(questions);
    tx.set(answerKeyRef(dailyRef), {answerIndices: split.answerIndices});
    tx.set(dailyRef, {
      dateId,
      played: false,
      durationSeconds: DAILY_DURATION_SECONDS,
      questions: split.publicQuestions,
      correct: 0,
      totalAnswered: 0,
      coinsEarned: 0,
      score: 0,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {created: true};
});

// ============================================================
// WEEKLY LEAGUE SEASON REWARDS
// ============================================================

/**
 * Mirrors lib/services/season_service.dart's `rewardForLeague`. The
 * returned `message` is persisted permanently into the claiming user's
 * `season_history` doc (see `claimWeeklySeasonRewards` below), so it's
 * localized at claim time from that user's own `languageCode` — same as
 * every other Cloud-Function-generated notification/history string here.
 * @param {string} leagueId Weekly league id.
 * @param {number} rank Player's rank within that league for the season.
 * @param {unknown} languageCode Claiming user's stored `languageCode`.
 * @return {{coins:number, message:string}} Reward for that placement.
 */
function weeklySeasonRewardForLeague(
  leagueId: string,
  rank: number,
  languageCode: unknown
): {coins: number; message: string} {
  const baseCoins = ((): number => {
    switch (leagueId) {
    case "bronze": return 20;
    case "silver": return 40;
    case "gold": return 80;
    case "diamond": return 150;
    case "master": return 300;
    default: return 20;
    }
  })();

  let bonus = 0;
  if (rank === 1) bonus = baseCoins;
  else if (rank <= 3) bonus = Math.round(baseCoins * 0.5);
  else if (rank <= 10) bonus = Math.round(baseCoins * 0.25);

  const message = rank === 1 ?
    pickText(languageCode, "¡Bono de campeón!", "Champion bonus!") :
    rank <= 3 ?
      pickText(languageCode, "¡Bono top 3!", "Top 3 bonus!") :
      rank <= 10 ?
        pickText(languageCode, "¡Bono top 10!", "Top 10 bonus!") :
        pickText(
          languageCode, "Recompensa de liga semanal", "Weekly league reward"
        );

  return {coins: baseCoins + bonus, message};
}

/**
 * Server-authoritative weekly-league season reward claim, replacing
 * SeasonService.claimAllPendingRewards's client-side batch writes. Reads
 * `weekly_participation`/`weekly_leagues` — both now Cloud-Function-only
 * writable (via submitDailyChallengeResult), so the rank/score used here
 * can no longer be forged by the client.
 */
export const claimWeeklySeasonRewards = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  const userSnap = await userRef.get();
  const languageCode = userSnap.data()?.languageCode;

  const participationSnap = await userRef
    .collection("weekly_participation")
    .orderBy("weekId", "desc")
    // Half a year: a player who comes back after a long break still gets
    // the weeks they earned. It used to be 8, and older weeks went unpaid.
    .limit(26)
    .get();

  const historySnap = await userRef.collection("season_history").get();
  const claimedSeasonIds = new Set(
    historySnap.docs
      .filter((d) => d.data().claimed === true)
      .map((d) => d.id)
  );

  type Pending = {
    seasonId: string;
    leagueId: string;
    leagueName: string;
    rank: number;
    weeklyScore: number;
    rewardCoins: number;
    rewardMessage: string;
  };

  const pending: Pending[] = [];

  for (const doc of participationSnap.docs) {
    const data = doc.data();
    const seasonId = String(data.weekId || doc.id);

    if (!isWeekClaimable(seasonId, serverDateId())) continue;
    if (claimedSeasonIds.has(seasonId)) continue;

    const leagueId = String(data.leagueId || "bronze");
    const leagueName = String(data.leagueName || "Bronze");
    const weeklyScore = safeInt(data.weeklyScore, 0);
    if (weeklyScore <= 0) continue;

    const betterPlayersSnap = await db
      .collection("weekly_leagues").doc(seasonId)
      .collection(leagueId)
      .where("weeklyScore", ">", weeklyScore)
      .count().get();
    const rank = (betterPlayersSnap.data().count || 0) + 1;

    const reward = weeklySeasonRewardForLeague(leagueId, rank, languageCode);

    pending.push({
      seasonId,
      leagueId,
      leagueName,
      rank,
      weeklyScore,
      rewardCoins: reward.coins,
      rewardMessage: reward.message,
    });
  }

  if (pending.length === 0) {
    return {claimedCount: 0, totalCoins: 0};
  }

  // Claimed in a transaction that re-reads each week's history doc: the
  // reads above happen outside one, so two calls at once both saw a week
  // as unclaimed and both paid it.
  return db.runTransaction(async (tx) => {
    const historyRefs = pending.map((reward) =>
      userRef.collection("season_history").doc(reward.seasonId)
    );
    const historyNow = await tx.getAll(...historyRefs);
    const unclaimed = pending.filter(
      (_, i) => historyNow[i].data()?.claimed !== true
    );

    let totalCoins = 0;

    for (const reward of unclaimed) {
      const historyRef = userRef.collection("season_history").doc(
        reward.seasonId
      );

      tx.set(historyRef, {
        seasonId: reward.seasonId,
        leagueId: reward.leagueId,
        leagueName: reward.leagueName,
        rank: reward.rank,
        weeklyScore: reward.weeklyScore,
        rewardCoins: reward.rewardCoins,
        rewardMessage: reward.rewardMessage,
        claimed: true,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      totalCoins += reward.rewardCoins;
    }

    if (totalCoins > 0) {
      tx.set(userRef, {
        coins: admin.firestore.FieldValue.increment(totalCoins),
        lastSeasonRewardClaimed: unclaimed[unclaimed.length - 1].seasonId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return {claimedCount: unclaimed.length, totalCoins};
  });
});

/**
 * Builds a cross-user notification's text server-side.
 *
 * The client used to compose title/body itself and write them straight into
 * the recipient's inbox. Since creating that document fires
 * `sendPushOnNotificationCreated`, that made "write arbitrary text into any
 * user's push notification" a client capability. Composing here means the
 * caller chooses *which* of a fixed set of messages is sent, never its
 * wording, and the sender's name comes from their own user doc rather than
 * from the request.
 * @param {string} type One of the supported cross-user notification types.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @param {string} senderName Sender's display name, read server-side.
 * @return {{title: string, body: string}} Localized notification text.
 */
function crossUserNotificationText(
  type: string, languageCode: unknown, senderName: string
): {title: string; body: string} {
  switch (type) {
  case "friend_request":
    return {
      title: pickText(languageCode,
        "Nueva solicitud de amistad", "New friend request"),
      body: pickText(languageCode,
        `${senderName} quiere agregarte como amigo.`,
        `${senderName} wants to add you as a friend.`),
    };
  case "rematch_request":
    return {
      title: pickText(languageCode,
        "Revancha solicitada", "Rematch requested"),
      body: pickText(languageCode,
        `${senderName} quiere la revancha.`,
        `${senderName} wants a rematch.`),
    };
  case "match_invite":
    return {
      title: pickText(languageCode,
        "Nuevo reto asíncrono", "New async challenge"),
      body: pickText(languageCode,
        `${senderName} te retó a una partida 1 vs 1.`,
        `${senderName} challenged you to a 1 vs 1 match.`),
    };
  case "realtime_invite":
    return {
      title: pickText(languageCode,
        "Reto en tiempo real", "Realtime challenge"),
      body: pickText(languageCode,
        `${senderName} te invitó a una partida 1 vs 1 en tiempo real.`,
        `${senderName} invited you to a realtime 1 vs 1 match.`),
    };
  case "match_turn":
    return {
      title: pickText(languageCode, "Tu turno", "Your turn"),
      body: pickText(languageCode,
        `${senderName} terminó su partida asíncrona. Ahora es tu turno.`,
        `${senderName} finished their async match. Now it is your turn.`),
    };
  default:
    return {
      title: pickText(languageCode,
        "Invitación en tiempo real aceptada", "Realtime invite accepted"),
      body: pickText(languageCode,
        `${senderName} aceptó tu reto en tiempo real.`,
        `${senderName} accepted your realtime challenge.`),
    };
  }
}

/**
 * Whether [uid] has actually earned the right to notify [targetUid].
 *
 * Each type is backed by a document that only a real interaction creates:
 * a pending friend request the caller sent, or a match/invite both are
 * party to. Without this the only requirement was being signed in, and
 * anonymous sign-in is open to anyone who installs the app.
 * @param {string} uid Caller.
 * @param {string} targetUid Intended recipient.
 * @param {string} type Notification type being requested.
 * @param {Record<string, unknown>} data Ids the type needs (matchId etc).
 * @return {Promise<boolean>} True when the pairing is backed by real state.
 */
async function mayNotify(
  uid: string,
  targetUid: string,
  type: string,
  data: Record<string, unknown>
): Promise<boolean> {
  if (type === "friend_request") {
    const snap = await db.collection("users").doc(targetUid)
      .collection("friend_requests").doc(uid).get();
    return snap.exists;
  }

  if (type === "rematch_request") {
    const id = cleanDocId(data.matchId);
    if (!id) return false;
    const snap = await db.collection("matches").doc(id).get();
    const m = snap.data();
    if (!m) return false;
    const uids = [m.hostUid, m.guestUid];
    return uids.includes(uid) && uids.includes(targetUid);
  }

  if (type === "match_invite" || type === "match_turn") {
    const id = cleanDocId(data.matchId);
    if (!id) return false;
    const snap = await db.collection("async_matches").doc(id).get();
    const m = snap.data();
    if (!m) return false;
    const uids = [m.challengerUid, m.challengedUid];
    return uids.includes(uid) && uids.includes(targetUid);
  }

  if (type === "realtime_invite_accepted") {
    const id = cleanDocId(data.inviteId);
    if (!id) return false;
    const snap = await db.collection("realtime_invites").doc(id).get();
    const i = snap.data();
    // Only the invited player tells the inviter it was accepted.
    return !!i && i.toUid === uid && i.fromUid === targetUid;
  }

  return false;
}

/**
 * Delivers one of a fixed set of notifications to another player.
 *
 * Replaces the client writing straight into `users/{other}/notifications`,
 * which firestore.rules had to leave open to any signed-in user for these
 * flows to work — and which therefore let anyone push arbitrary text to
 * anyone whose uid they could read.
 */
export const sendUserNotification = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const targetUid = cleanDocId(request.data?.targetUid);
  const type = String(request.data?.type || "");
  const data = (request.data?.data ?? {}) as Record<string, unknown>;

  const supported = [
    "friend_request", "rematch_request", "match_invite",
    "match_turn", "realtime_invite_accepted",
  ];

  if (!targetUid || targetUid === uid || !supported.includes(type)) {
    throw new HttpsError("invalid-argument", "Invalid notification request.");
  }

  if (!await mayNotify(uid, targetUid, type, data)) {
    throw new HttpsError(
      "permission-denied", "Not allowed to notify this user."
    );
  }

  const [senderSnap, targetSnap] = await db.getAll(
    db.collection("users").doc(uid),
    db.collection("users").doc(targetUid)
  );

  const senderData = senderSnap.data() || {};
  // The reserved username, not `displayName`: that one is free text the
  // client writes, and it went straight into another player's push.
  const senderName = String(
    senderData.username || senderData.displayName || "?"
  ).slice(0, 20);

  const {title, body} = crossUserNotificationText(
    type, targetSnap.data()?.languageCode, senderName
  );

  // One notification per sender, type and match or invite, ever. With an
  // auto-id, the same friend request could be re-announced on every call:
  // an unlimited stream of pushes to anyone a request had been sent to.
  const notificationId = [
    type, uid, String(data.matchId || data.inviteId || ""),
  ].join("__");

  try {
    await db.collection("users").doc(targetUid)
      .collection("notifications").doc(notificationId).create({
        type,
        title,
        body,
        // Only the ids the app routes on — anything else the caller sent is
        // dropped rather than echoed into the recipient's document.
        data: {
          ...(data.matchId ? {matchId: String(data.matchId)} : {}),
          ...(data.inviteId ? {inviteId: String(data.inviteId)} : {}),
          ...(data.fromUid ? {fromUid: String(data.fromUid)} : {}),
        },
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (error) {
    // Already sent once: not an error for the caller, just nothing new.
    if ((error as {code?: number}).code === 6) return {sent: false};
    throw error;
  }

  return {sent: true};
});

/**
 * Relays every newly created in-app notification (friend requests,
 * achievements, season rewards, match invites/results, streak reminders...)
 * as a push notification, if the target user has a saved FCM token.
 */
export const sendPushOnNotificationCreated = onDocumentCreated(
  "users/{uid}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const uid = event.params.uid;

    // The token lives in a private subcollection rather than on the user
    // doc, which any signed-in user may read. There is no fallback to the
    // old field on the user doc: it kept stale tokens readable by
    // everyone, and the app removes it each time it saves the token.
    const pushSnap = await db.collection("users").doc(uid)
      .collection("private").doc("push").get();

    const token = pushSnap.data()?.fcmToken;

    if (!token || typeof token !== "string") return;

    const title = String(data.title || "TriviaIA");
    const body = String(data.body || "");

    try {
      await admin.messaging().send({
        token,
        notification: {title, body},
        data: {type: String(data.type || "")},
      });
    } catch (e) {
      console.warn(`Push send failed for user ${uid}: ${e}`);
    }
  }
);

/**
 * Users scanned per page by `notifyStreakAtRisk`, and the ceiling on one
 * batch's writes — a Firestore batch takes 500 operations, and this leaves
 * room to spare.
 */
const STREAK_NOTIFY_PAGE_SIZE = 400;

/**
 * Once a day, reminds users with an active Daily Challenge streak who
 * haven't played yet today, so they don't lose it silently.
 */
export const notifyStreakAtRisk = onSchedule(
  {schedule: "0 19 * * *", timeZone: "America/Lima"},
  async () => {
    // The date in the zone the job is scheduled in, not UTC — see
    // dateIdInTimeZone.
    const dateId = dateIdInTimeZone(Date.now(), "America/Lima");

    // Paged rather than one unbounded read: every player with a live streak
    // matches this query, so a single `.get()` grows with the whole active
    // player base and lands in one invocation's memory. Writes go out in
    // batches for the same reason — one `add()` per user through an
    // unbounded Promise.all opened as many concurrent writes as there were
    // users.
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    for (;;) {
      // Only the players whose streak is at risk — last played yesterday —
      // rather than every player with a streak, most of whom already
      // played today.
      let page = db
        .collection("users")
        .where("lastDailyPlayed", "==", previousDateId(dateId))
        .limit(STREAK_NOTIFY_PAGE_SIZE);

      if (cursor) page = page.startAfter(cursor);

      const snap = await page.get();
      if (snap.empty) break;

      const batch = db.batch();
      let queued = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        if (!isStreakAtRisk(data.lastDailyPlayed, dateId)) continue;

        const streak = safeInt(data.dailyStreak, 0);

        batch.set(doc.ref.collection("notifications").doc(), {
          type: "streak_at_risk",
          title: pickText(
            data.languageCode,
            "Tu racha está en riesgo",
            "Your streak is at risk"
          ),
          body: pickText(
            data.languageCode,
            `Tienes una racha de ${streak} días. Juega el reto ` +
              "diario de hoy antes de perderla.",
            `You have a ${streak}-day streak. Play today's Daily ` +
              "Challenge before you lose it."
          ),
          data: {streak},
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        queued++;
      }

      if (queued > 0) await batch.commit();

      if (snap.size < STREAK_NOTIFY_PAGE_SIZE) break;
      cursor = snap.docs[snap.docs.length - 1];
    }
  }
);

// ============================================================
// LOGIN STREAK BONUS
//
// Mirrors user_bootstrap.dart's per-launch login-streak logic. `loginStreak`
// and `lastLoginDate` are now protected fields — previously a client could
// write them directly (e.g. rewind `lastLoginDate` to "yesterday" and bump
// `loginStreak` by hand) to repeatedly claim the 3/7/14-day coin bonus.
// `todayDateId` is trusted from the client only as a bucket key (same as
// submitDailyChallengeResult's dateId/weekId) — the streak math and coin
// amount are entirely server-computed.
// ============================================================

const LOGIN_STREAK_3_DAYS_COINS = 3;
const LOGIN_STREAK_7_DAYS_COINS = 8;
const LOGIN_STREAK_14_DAYS_COINS = 15;

/**
 * Mirrors user_bootstrap.dart's `_loginStreakBonusCoins`.
 * @param {number} streak Login streak after today's login.
 * @return {number} Bonus coins for hitting a streak milestone.
 */
function loginStreakBonusCoins(streak: number): number {
  if (streak > 0 && streak % 14 === 0) return LOGIN_STREAK_14_DAYS_COINS;
  if (streak > 0 && streak % 7 === 0) return LOGIN_STREAK_7_DAYS_COINS;
  if (streak > 0 && streak % 3 === 0) return LOGIN_STREAK_3_DAYS_COINS;
  return 0;
}

export const claimLoginStreakBonus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const todayDateId = String(request.data?.todayDateId || "");
  if (!isPlausibleDateId(todayDateId, serverDateId())) {
    throw await wrongDeviceDateError(uid);
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const lastLoginDate = data.lastLoginDate ?
      String(data.lastLoginDate) : null;
    const previousStreak = safeInt(data.loginStreak, 0);

    const step = loginStreakStep(
      lastLoginDate, previousStreak, todayDateId, serverDateId()
    );
    if (step.status === "invalid") {
      throw await wrongDeviceDateError(uid);
    }
    if (step.status === "already") {
      return {
        streak: previousStreak,
        coinsEarned: 0,
        alreadyProcessedToday: true,
      };
    }

    const newStreak = step.streak;

    const coinsEarned = loginStreakBonusCoins(newStreak);

    const patch: Record<string, unknown> = {
      loginStreak: newStreak,
      lastLoginDate: todayDateId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (coinsEarned > 0) {
      patch.coins = admin.firestore.FieldValue.increment(coinsEarned);
      patch.loginStreakCelebrationPending = true;
      patch.loginStreakCelebrationCoins = coinsEarned;
    }

    tx.set(userRef, patch, {merge: true});

    return {streak: newStreak, coinsEarned, alreadyProcessedToday: false};
  });
});

// ============================================================
// SOLO LEVEL REWARDS
//
// Mirrors level_play_screen.dart's `_saveProgress` transaction. `coins`/
// `xp` are protected fields in firestore.rules, so the reward grant (and
// the progress/achievement bookkeeping that determines whether a grant is
// due) moved here in full. `levelCount` — used only to decide the
// "completed all levels in this category" bonus — is read from the
// authoritative fixed_categories/ai_topics doc rather than trusted from
// the client, closing a minor "claim the completion bonus early" gap.
// ============================================================

const COMPLETE_FIXED_CATEGORY_COINS = 10;
const AI_LEVELS_PER_TOPIC = 10;
// Every question a topic can bank — see [avoidListCapacity] on why the
// "don't repeat these" list is no longer a sample.
const AI_AVOID_LIST_MAX_QUESTIONS = avoidListCapacity(AI_LEVELS_PER_TOPIC);
const AI_QUESTIONS_PER_LEVEL = 10;
const AI_INITIAL_GENERATED_LEVELS = 2;
const AI_GENERATION_BUFFER_LEVELS = 2;
const AI_MODEL = "claude-haiku-5-5";

// Buffering now starts when a level *opens* rather than when it's
// submitted, so two callers can legitimately want the same level at once
// (the buffer running during play, and ensureSoloLevelSession self-healing
// a level that was never banked). Without a lock both would call Claude and
// append to the same bank — duplicate questions, double spend. The loser of
// the race waits for the winner's questions instead of generating its own.
const AI_LEVEL_LOCK_MS = 150_000;
const AI_LEVEL_LOCK_WAIT_MS = 90_000;
const AI_LEVEL_LOCK_POLL_MS = 2_000;

// Steers Claude's own judgment for the broad cases (hate speech, graphic
// historical violence, etc.) that BLOCKED_TOPIC_KEYWORDS below deliberately
// doesn't try to catch — keeping topics appropriate for a general-audience,
// all-ages app distributed on the Play Store / App Store.
const AI_TOPIC_SYSTEM_PROMPT = "You generate trivia questions for a " +
  "general-audience mobile game available to players of all ages on the " +
  "Google Play Store and Apple App Store. Refuse to generate questions " +
  "(produce no content) if the requested topic is about suicide or " +
  "self-harm; sexual content, pornography, or content sexualizing " +
  "minors; extreme or graphic violence; instructions for making weapons, " +
  "drugs, or other dangerous items; hate speech or content that " +
  "promotes discrimination against a group; terrorism or extremist " +
  "content; or is otherwise inappropriate for a general audience that " +
  "includes children. For legitimate topics that touch sensitive subject " +
  "matter (e.g. history of a war, a disease, addiction as a public-" +
  "health subject), keep every question strictly factual, encyclopedic, " +
  "and free of graphic or gratuitous detail — write it the way a " +
  "school textbook or family-friendly encyclopedia would.";

export const submitSoloLevelResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = cleanDocId(request.data?.categoryId);
  const aiTopicId = cleanDocId(request.data?.aiTopicId) || null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  // `correct`/`total` are only used for a fast request-shape check here —
  // the real, reward-determining values are recomputed below from the
  // answers the server banked as they were given.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotal = safeInt(request.data?.total, -1);

  if (
    levelNumber < 1 || reportedCorrect < 0 || reportedTotal < 0 ||
    reportedCorrect > reportedTotal
  ) {
    throw new HttpsError("invalid-argument", "Invalid level result.");
  }
  if (isAiTopic && !aiTopicId) {
    throw new HttpsError("invalid-argument", "Missing aiTopicId.");
  }
  if (!isAiTopic && !categoryId) {
    throw new HttpsError("invalid-argument", "Missing categoryId.");
  }

  const userRef = db.collection("users").doc(uid);
  const progressRef = isAiTopic ?
    userRef.collection("progress_ai").doc(aiTopicId as string) :
    userRef.collection("progress_fixed").doc(categoryId);
  const soloLevelsAchievementRef = userRef
    .collection("achievements").doc("solo_levels_10");
  const soloLevels25AchievementRef = userRef
    .collection("achievements").doc("solo_levels_25");
  const categoriesExploredAchievementRef = userRef
    .collection("achievements").doc("categories_explored_5");

  const sessionId = isAiTopic ?
    `${aiTopicId}_${levelNumber}` : `${categoryId}_${levelNumber}`;
  const sessionRef = userRef
    .collection(isAiTopic ? "sessions_ai" : "sessions_fixed").doc(sessionId);

  let levelCount = 0;
  if (isAiTopic) {
    const topicSnap = await userRef
      .collection("ai_topics").doc(aiTopicId as string).get();
    const topicData = topicSnap.data();
    levelCount = safeInt(
      topicData?.targetLevels ?? topicData?.levelsCount,
      AI_LEVELS_PER_TOPIC
    );
  } else {
    const catSnap = await db
      .collection("fixed_categories").doc(categoryId).get();
    levelCount = safeInt(catSnap.data()?.levelCount, 0);
  }

  if (levelCount > 0 && levelNumber > levelCount) {
    throw new HttpsError("invalid-argument", "Invalid level result.");
  }

  return db.runTransaction(async (tx) => {
    const progressSnap = await tx.get(progressRef);
    const userSnap = await tx.get(userRef);
    const soloLevelsAchievementSnap = await tx.get(soloLevelsAchievementRef);
    const soloLevels25AchievementSnap =
      await tx.get(soloLevels25AchievementRef);
    const categoriesExploredAchievementSnap =
      await tx.get(categoriesExploredAchievementRef);
    const sessionSnap = await tx.get(sessionRef);

    const sessionData = sessionSnap.data();
    const sessionQuestions = sessionData?.questions;
    const total = Array.isArray(sessionQuestions) ?
      sessionQuestions.length : 0;

    if (!isSoloRunSubmittable(
      sessionData?.answers as Record<string, unknown> | undefined,
      sessionData?.runStartedAtMs as number | undefined,
      Date.now()
    )) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "No pudimos guardar este nivel: tus respuestas no llegaron al " +
          "servidor. Juégalo de nuevo.",
        "We couldn't save this level: your answers didn't reach the " +
          "server. Please play it again."
      );
    }

    // Only answers the server judged as they were given
    // (answerSoloQuestion) count. The client's list used to fill in any
    // that weren't banked, which now would score answers that never paid
    // their life.
    const scoredAnswers = mergeRecordedAnswers(
      sessionData?.answers as Record<string, unknown> | undefined,
      []
    );
    const keyed = await keyedQuestions(sessionRef, sessionData || {}, tx);

    const {correct} = computeVerifiedQuizResult(
      keyed, scoredAnswers, total
    );

    const percent = total === 0 ? 0 : correct / total;
    const passedLevel = percent >= 0.4;
    const {xp: levelXp, coins: levelCoins} =
      calculateLevelRewards(correct, total);

    const prev = progressSnap.data();
    const userData = userSnap.data() || {};
    const prevUserXp = safeInt(userData.xp, 0);

    const prevCompleted = new Set<number>(
      ((prev?.completedLevels as unknown[]) || [])
        .map((e) => safeInt(e, 0))
    );

    const prevLevelStats: Record<string, Record<string, unknown>> = {
      ...((prev?.levelStats as Record<string, Record<string, unknown>>) ||
        {}),
    };

    const migratedPassedLevels = new Set<number>();
    for (const [key, stat] of Object.entries(prevLevelStats)) {
      const level = parseInt(key, 10);
      const statPercent = Number(stat?.percent ?? 0);
      if (!isNaN(level) && statPercent >= 0.4) {
        migratedPassedLevels.add(level);
      }
    }

    const prevPassed = new Set<number>(
      prev?.passedLevels ?
        (prev.passedLevels as unknown[]).map((e) => safeInt(e, 0)) :
        Array.from(migratedPassedLevels)
    );

    const wasAlreadyPlayed = prevCompleted.has(levelNumber);
    const wasAlreadyPassed = prevPassed.has(levelNumber);
    const categoryWasUnexplored = prevPassed.size === 0;

    prevCompleted.add(levelNumber);
    if (passedLevel) prevPassed.add(levelNumber);

    const levelKey = String(levelNumber);
    const oldStat = prevLevelStats[levelKey] || {};
    const oldPercent = Number(oldStat.percent ?? -1);

    if (percent >= oldPercent) {
      prevLevelStats[levelKey] = {
        correct,
        total,
        percent,
        passed: passedLevel,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }

    const newlyPassed = passedLevel && !wasAlreadyPassed;
    // Replaying a level once its one-time coin payout is spent still earns
    // a small XP trickle (20%, floor 1) instead of flatly zero — XP has no
    // cap and no coin equivalent (see player_level_service.dart), so this
    // gives completionist players something to keep working toward without
    // reopening the coin-farming exploit the one-time gate exists to block.
    const grantedXp = wasAlreadyPlayed ?
      Math.max(1, Math.floor(levelXp * 0.2)) : levelXp;
    let grantedCoins = newlyPassed ? levelCoins : 0;
    const shouldEnsureAiBuffer = isAiTopic && newlyPassed;

    // Progress for this achievement is written here (rather than by a
    // client-side follow-up call) since completed/progress/claimed are
    // locked against direct client writes for this id in firestore.rules —
    // newlyPassed is already computed authoritatively above, from this
    // same transaction's own tracked completedLevels/passedLevels.
    if (newlyPassed) {
      const currentSoloLevelsProgress = safeInt(
        soloLevelsAchievementSnap.data()?.progress, 0
      );
      applyPvpAchievementProgress(
        tx, uid, {id: "solo_levels_10", title: "Solo Explorer", target: 10},
        currentSoloLevelsProgress + 1, soloLevelsAchievementSnap,
        userData.languageCode
      );

      const currentSoloLevels25Progress = safeInt(
        soloLevels25AchievementSnap.data()?.progress, 0
      );
      applyPvpAchievementProgress(
        tx, uid, {id: "solo_levels_25", title: "Solo Master", target: 25},
        currentSoloLevels25Progress + 1, soloLevels25AchievementSnap,
        userData.languageCode
      );
    }

    // A category counts as "explored" the moment its first level is passed
    // — `categoriesExploredCount` on the user doc is the running total
    // (cheaper than re-scanning the whole progress_fixed subcollection on
    // every level completion) and only ever grows here.
    const categoryNewlyExplored =
      !isAiTopic && categoryWasUnexplored && passedLevel;

    const newCategoriesExploredCount = categoryNewlyExplored ?
      safeInt(userData.categoriesExploredCount, 0) + 1 : null;

    if (newCategoriesExploredCount !== null) {
      applyPvpAchievementProgress(
        tx, uid,
        {id: "categories_explored_5", title: "Curious Mind", target: 5},
        newCategoriesExploredCount, categoriesExploredAchievementSnap,
        userData.languageCode
      );
    }

    const completedAll = levelCount > 0 && prevPassed.size >= levelCount;
    const rewardGranted = prev?.categoryRewardGranted === true;
    const categoryBonusGranted = completedAll && !rewardGranted;

    if (categoryBonusGranted) {
      grantedCoins += COMPLETE_FIXED_CATEGORY_COINS;
    }

    const progressPatch: Record<string, unknown> = {
      completedLevels: Array.from(prevCompleted).sort((a, b) => a - b),
      passedLevels: Array.from(prevPassed).sort((a, b) => a - b),
      levelStats: prevLevelStats,
      lastScore: {correct, total, percent, passed: passedLevel, levelNumber},
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (grantedXp > 0 || grantedCoins > 0) {
      progressPatch.lastLevelReward = {
        levelNumber,
        xp: grantedXp,
        coins: grantedCoins,
        passed: passedLevel,
        grantedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }

    if (completedAll) {
      progressPatch.completedAllLevels = true;
      if (categoryBonusGranted) {
        progressPatch.categoryRewardGranted = true;
        progressPatch.rewardGrantedAt =
          admin.firestore.FieldValue.serverTimestamp();
      }
    }

    tx.set(progressRef, progressPatch, {merge: true});

    // AI levels re-roll on replay: dropping the finished session makes the
    // next `ensureSoloLevelSession` draw a fresh slate from the level's
    // accumulated bank instead of handing back the same ten questions
    // forever. Fixed categories keep their session — their slate is a
    // deterministic seeded shuffle of a large static pool, so re-rolling
    // would only churn reads for no new content. What they can't keep is
    // this run's banked answers — see `sessionAfterSubmit`.
    if (isAiTopic) {
      tx.delete(sessionRef);
    } else if (sessionData) {
      tx.set(sessionRef, sessionAfterSubmit(sessionData));
    }

    // gamesPlayed increments once per level attempt (pass or fail), same
    // semantics as submitDailyChallengeResult's increment — it gates
    // LifeService.tryConsumeWrongAnswer's new-player grace period, which
    // was previously only bumped by Daily Challenge, leaving it permanent
    // or absent for players who never (or not yet) touch Daily Challenge.
    tx.set(
      userRef,
      {
        gamesPlayed: admin.firestore.FieldValue.increment(1),
        ...(grantedXp > 0 ?
          {xp: admin.firestore.FieldValue.increment(grantedXp)} : {}),
        ...(grantedCoins > 0 ?
          {coins: admin.firestore.FieldValue.increment(grantedCoins)} : {}),
        ...(newCategoriesExploredCount !== null ?
          {categoriesExploredCount: newCategoriesExploredCount} : {}),
        // correctAnswers/wrongAnswers feed the profile accuracy stat and
        // the 100/1000-questions avatar unlock — both used to only count
        // Daily Challenge answers, leaving Solo/PvP-only players stuck at 0.
        ...(total > 0 ? {
          correctAnswers: admin.firestore.FieldValue.increment(correct),
          wrongAnswers: admin.firestore.FieldValue.increment(total - correct),
        } : {}),
        ...questionCountAvatarUnlockPatch(
          userData.unlockedAvatars,
          safeInt(userData.correctAnswers, 0) +
            safeInt(userData.wrongAnswers, 0) + total
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      grantedXp,
      grantedCoins,
      passed: passedLevel,
      newlyPassed,
      userTotalXp: prevUserXp + grantedXp,
      completedAll,
      shouldEnsureAiBuffer,
      // The whole key, for the end-of-level review: the level is over.
      answerKey: keyed.map((q) => safeInt(q.answerIndex, -1)),
    };
  });
});


/**
 * Server-authoritative replacement for level_play_screen.dart's
 * `_ensureSession` — a client used to read the real level/pool questions
 * and write its own copy (including `answerIndex`) straight into
 * `sessions_ai`/`sessions_fixed`, which `submitSoloLevelResult` then
 * trusted as ground truth. That let a modified client write a session
 * with self-chosen "correct" answers unrelated to the real content. This
 * function does the same question-selection the client used to do, but
 * server-side against the authoritative `ai_topics/*\/levels/*\/questions`
 * / `fixed_pools` data (both Cloud-Function/admin-only), then writes the
 * session doc itself — firestore.rules now denies client `create` on
 * `sessions_ai`/`sessions_fixed`, so this is the only thing that can
 * populate them.
 */
// Holds the AI secret because an AI level whose bank never got buffered
// has to be generated here — see the empty-bank branch below.
export const ensureSoloLevelSession = onCall({
  secrets: AI_SECRETS,
  // Deliberately longer than the client waits: on the rare path where this
  // has to generate a level, finishing and persisting the questions after
  // the caller has given up still turns their retry into an instant hit.
  timeoutSeconds: 120,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = cleanDocId(request.data?.categoryId);
  const aiTopicId = cleanDocId(request.data?.aiTopicId) || null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);

  if (levelNumber < 1) {
    throw new HttpsError("invalid-argument", "Invalid levelNumber.");
  }
  if (isAiTopic && !aiTopicId) {
    throw new HttpsError("invalid-argument", "Missing aiTopicId.");
  }
  if (!isAiTopic && !categoryId) {
    throw new HttpsError("invalid-argument", "Missing categoryId.");
  }

  const userRef = db.collection("users").doc(uid);
  const sessionId = isAiTopic ?
    `${aiTopicId}_${levelNumber}` : `${categoryId}_${levelNumber}`;
  const sessionRef = userRef
    .collection(isAiTopic ? "sessions_ai" : "sessions_fixed").doc(sessionId);

  const existing = await sessionRef.get();
  if (existing.exists) {
    await moveSessionKeyOut(sessionRef, existing.data() || {});
    return {created: false};
  }

  // "Locked" was previously only a client-side UI affordance — neither
  // this function nor submitSoloLevelResult checked level-unlock ordering,
  // so any client could request a session for an arbitrary levelNumber
  // directly. Level 1 always needs no prior progress; every other level
  // requires the one before it to already be in passedLevels.
  if (levelNumber > 1) {
    const progressRef = isAiTopic ?
      userRef.collection("progress_ai").doc(aiTopicId as string) :
      userRef.collection("progress_fixed").doc(categoryId);
    const progressSnap = await progressRef.get();
    const passedLevels = new Set<number>(
      ((progressSnap.data()?.passedLevels as unknown[]) || [])
        .map((e) => safeInt(e, 0))
    );

    if (!passedLevels.has(levelNumber - 1)) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Este nivel está bloqueado.",
        "This level is locked."
      );
    }
  }

  if (isAiTopic) {
    const topicRef = userRef.collection("ai_topics").doc(aiTopicId as string);
    const topicSnap = await topicRef.get();
    const topicData = topicSnap.data();

    if (!topicData) {
      throw await localizedErrorFor(
        uid, "not-found",
        "Este tema ya no existe.",
        "This topic no longer exists."
      );
    }

    const ownerSnap = await userRef.get();
    const poolId = await ensureTopicAdoptedIntoPool(
      uid, topicRef, topicData, ownerSnap.data()?.languageCode
    );
    const levelRef = db.collection("ai_topic_pool").doc(poolId)
      .collection("levels").doc(`level_${levelNumber}`);

    const levelSnap = await levelRef.get();
    const reportedCounts: Record<string, unknown> =
      levelSnap.data()?.reportedQuestionCounts || {};

    // The level doc carries its own question ids, so picking a slate costs
    // nothing: only the questions actually served get read. Levels written
    // before that field existed fall back to listing the collection, and
    // are backfilled below so they pay for it once.
    const storedIds = (levelSnap.data()?.questionIds as unknown[] | undefined)
      ?.map((id) => String(id));

    let allIds: string[];
    if (storedIds && storedIds.length > 0) {
      allIds = storedIds;
    } else {
      const questionsSnap = await levelRef.collection("questions").get();
      allIds = questionsSnap.docs.map((doc) => doc.id);

      if (allIds.length > 0) {
        await levelRef.set(
          {questionIds: [...allIds].sort(compareQuestionIds)},
          {merge: true}
        );
      }
    }

    if (allIds.length === 0) {
      // Self-heal instead of dead-ending. Levels are normally generated
      // ahead of the player by ensureAiTopicLevelsGenerated, but that call
      // is best-effort and the client swallows its failures — so a level
      // the player has legitimately unlocked can still have an empty bank,
      // and refusing here left them stuck on it forever with no way
      // forward. Generating just this one level keeps the wait to a single
      // batch rather than the usual look-ahead.
      const poolRef = db.collection("ai_topic_pool").doc(poolId);
      const languageCode = ownerSnap.data()?.languageCode;

      const added = await generateAiTopicLevel(
        uid, poolRef, levelNumber,
        String(topicData.title || "Custom Topic"),
        languageCode,
        {
          avoidQuestions: await existingPoolQuestionTexts(poolRef),
        }
      );

      if (added.length === 0) {
        throw await localizedErrorFor(
          uid, "not-found",
          "No se pudieron preparar las preguntas de este nivel.",
          "This level's questions couldn't be prepared."
        );
      }

      const [refreshedSnap, poolSnap] = await Promise.all([
        levelRef.get(),
        poolRef.get(),
      ]);

      allIds = ((refreshedSnap.data()?.questionIds as unknown[]) || [])
        .map((id) => String(id));

      // Keep both sides' depth honest now that the level really exists.
      const newUserLevels = Math.max(
        safeInt(topicData.generatedLevels, 0), levelNumber
      );

      // `questionsCount` has to move together with `generatedLevels`. The
      // topics list reads a count that trails the level depth as a broken
      // topic and refuses to open it, so raising one without the other
      // locked the player out of a topic whose content was perfectly fine.
      const bankedQuestions = await countBankedQuestions(
        poolRef, newUserLevels
      );

      await Promise.all([
        poolRef.set({
          generatedLevels: Math.max(
            safeInt(poolSnap.data()?.generatedLevels, 0), levelNumber
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}),
        topicRef.set({
          generatedLevels: newUserLevels,
          questionsCount: bankedQuestions,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}),
      ]);
    }

    const usableIds = allIds.filter((id) => {
      const count = safeInt(reportedCounts[id], 0);
      return count < AI_QUESTION_REPORT_THRESHOLD;
    });
    const idsToUse = usableIds.length > 0 ? usableIds : allIds;

    // A level's bank accumulates past the ten questions it started with,
    // so a replay serves questions this player hasn't been asked yet
    // rather than the same slate forever. The seed varies with how much
    // they've already seen, so successive replays don't draw identically.
    const seenRef = userRef
      .collection("ai_topic_seen").doc(`${aiTopicId}_${levelNumber}`);
    const seenSnap = await seenRef.get();
    const seenIds: string[] = (
      (seenSnap.data()?.questionIds as unknown[]) || []
    ).map((id) => String(id));

    const seed = fnv1a32(
      `${uid}|${poolId}|${levelNumber}|${seenIds.length}`
    );
    const draw = selectSessionQuestions(
      idsToUse, seenIds, seed, AI_QUESTIONS_PER_SESSION
    );

    if (draw.questionIds.length === 0) {
      throw await noLevelQuestionsError(uid);
    }

    const questionDocs = await db.getAll(...draw.questionIds.map((id) =>
      levelRef.collection("questions").doc(id)
    ));

    const chosen: Record<string, unknown>[] = [];
    draw.questionIds.forEach((id, i) => {
      // A stale id (question deleted since the level was indexed) is
      // skipped rather than served as an empty question.
      const doc = questionDocs[i];
      if (!doc.exists) return;
      chosen.push({...doc.data(), questionId: id});
    });

    if (chosen.length === 0) {
      throw await noLevelQuestionsError(uid);
    }

    await db.runTransaction(async (tx) => {
      const sesSnap = await tx.get(sessionRef);
      if (sesSnap.exists) return;

      const split = splitAnswerKey(chosen);
      tx.set(sessionRef, {
        categoryId: aiTopicId,
        levelNumber,
        difficulty: 1,
        total: chosen.length,
        questions: split.publicQuestions,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(answerKeyRef(sessionRef), {answerIndices: split.answerIndices});

      // Only the genuinely new ones count as seen — questions served as
      // filler for an exhausted bank are already in the set, and adding
      // them again would just bloat it.
      const newlySeen = draw.questionIds
        .filter((id) => !draw.repeatedIds.includes(id));

      if (newlySeen.length > 0) {
        tx.set(seenRef, {
          questionIds: admin.firestore.FieldValue.arrayUnion(...newlySeen),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    });

    return {created: true};
  }

  const {questions: chosen, difficulty: usedDifficulty, seed} =
    await loadFixedLevelQuestions(uid, categoryId, levelNumber);

  if (chosen.length === 0) {
    throw await noLevelQuestionsError(uid);
  }

  await db.runTransaction(async (tx) => {
    const sesSnap = await tx.get(sessionRef);
    if (sesSnap.exists) return;

    const split = splitAnswerKey(chosen);
    tx.set(sessionRef, {
      categoryId,
      levelNumber,
      difficulty: usedDifficulty,
      total: chosen.length,
      seed,
      questions: split.publicQuestions,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(answerKeyRef(sessionRef), {answerIndices: split.answerIndices});
  });

  return {created: true};
});

/**
 * Judges one Solo / AI-topic answer the moment it is given, banks it, and
 * charges for it.
 *
 * The session no longer carries the answers (they live in its
 * `secret/answers`, which no client can read), so this is the only way to
 * learn whether an answer was right — and it only tells once: the first
 * answer per question is final. The first answer of a paid run also pays
 * the level's entry, and a wrong one pays its half life, in the same
 * transaction; those used to be separate calls a modified client could
 * leave out.
 *
 * -1 (TIMED_OUT_ANSWER) closes a question the clock ran out on.
 * Fails with failed-precondition and `details.reason = "no_lives"` when
 * the player can't afford to answer.
 */
export const answerSoloQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = cleanDocId(request.data?.categoryId);
  const aiTopicId = cleanDocId(request.data?.aiTopicId) || null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  const questionIndex = safeInt(request.data?.questionIndex, -1);
  const selectedIndex = safeInt(
    request.data?.selectedIndex, TIMED_OUT_ANSWER
  );

  if (levelNumber < 1 || questionIndex < 0) {
    throw new HttpsError("invalid-argument", "Invalid answer.");
  }
  if (isAiTopic ? !aiTopicId : !categoryId) {
    throw new HttpsError("invalid-argument", "Missing topic.");
  }

  const userRef = db.collection("users").doc(uid);
  const sessionId = isAiTopic ?
    `${aiTopicId}_${levelNumber}` : `${categoryId}_${levelNumber}`;
  const sessionRef = userRef
    .collection(isAiTopic ? "sessions_ai" : "sessions_fixed").doc(sessionId);
  const progressRef = isAiTopic ?
    userRef.collection("progress_ai").doc(aiTopicId as string) :
    userRef.collection("progress_fixed").doc(categoryId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, userSnap, progressSnap] = await tx.getAll(
      sessionRef, userRef, progressRef
    );
    const session = sessionSnap.data();
    if (!session) {
      throw new HttpsError("failed-precondition", "No open session.");
    }
    const keyed = await keyedQuestions(sessionRef, session, tx);
    if (questionIndex >= keyed.length) {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }

    const correctIndex = safeInt(keyed[questionIndex]?.answerIndex, -1);
    const banked = (session.answers && typeof session.answers === "object") ?
      session.answers as Record<string, unknown> : {};
    const key = String(questionIndex);
    const userData = userSnap.data() || {};
    const nowMs = Date.now();
    const state = computeLifeState(userData, nowMs);

    // Already answered: the same verdict again (a retried call), and
    // nothing charged twice.
    if (Object.prototype.hasOwnProperty.call(banked, key)) {
      const stored = safeInt(banked[key], TIMED_OUT_ANSWER);
      return {
        correct: stored === correctIndex,
        correctIndex,
        alreadyAnswered: true,
        entryCharged: false,
        lifeLost: false,
        ...lifeStateResponse(state),
      };
    }

    const firstOfRun = Object.keys(banked).length === 0;
    const passed = ((progressSnap.data()?.passedLevels as unknown[]) || [])
      .map((entry) => safeInt(entry, 0));
    const replayFree = passed.includes(levelNumber);
    const correct = selectedIndex === correctIndex;

    const charge = answerCharge({
      chargeEntry: firstOfRun && !replayFree,
      lifeUnits: state.lifeUnits,
      entryCost: LEVEL_ENTRY_COST_UNITS,
      wrongCost: WRONG_ANSWER_COST_UNITS,
      gamesPlayed: safeInt(userData.gamesPlayed, 0),
      graceLevels: NEW_PLAYER_GRACE_LEVELS,
      correct,
    });
    if (charge.refused) {
      throw noLivesError(userData.languageCode);
    }

    tx.set(sessionRef, {
      answers: {[key]: selectedIndex},
      results: {[key]: {correct, correctIndex}},
      ...(firstOfRun ? {runStartedAtMs: nowMs} : {}),
    }, {merge: true});

    const after = writeLifeUnits(tx, userRef, state, charge.newUnits, nowMs);

    return {
      correct,
      correctIndex,
      alreadyAnswered: false,
      replayFree,
      entryCharged: charge.entryCharged,
      lifeLost: charge.lifeLost,
      ...lifeStateResponse(after),
    };
  });
});

/**
 * The error for answering without the life to pay for it. The app reads
 * `details.reason` to show its no-lives screen.
 * @param {unknown} languageCode The player's language.
 * @return {HttpsError} The error.
 */
function noLivesError(languageCode: unknown): HttpsError {
  return new HttpsError(
    "failed-precondition",
    pickText(languageCode,
      "No tienes vidas suficientes.", "You don't have enough lives."),
    {localized: true, reason: "no_lives"}
  );
}

/**
 * Moves a session's inline answer key into its `secret/answers`, for
 * sessions written before the key moved out. Their already-banked answers
 * get their verdicts, so a resumed run shows them as judged.
 * @param {FirebaseFirestore.DocumentReference} sessionRef The session.
 * @param {FirebaseFirestore.DocumentData} data Its data.
 * @return {Promise<void>} Resolves once moved (or if nothing to move).
 */
async function moveSessionKeyOut(
  sessionRef: FirebaseFirestore.DocumentReference,
  data: FirebaseFirestore.DocumentData
): Promise<void> {
  const questions = data.questions;
  const inline = Array.isArray(questions) && questions.some(
    (q) => typeof (q as Record<string, unknown>)?.answerIndex === "number"
  );
  if (!inline) return;

  const split = splitAnswerKey(questions as Record<string, unknown>[]);
  const banked = (data.answers && typeof data.answers === "object") ?
    data.answers as Record<string, unknown> : {};
  const results: Record<string, unknown> = {};
  for (const [index, selected] of Object.entries(banked)) {
    const correctIndex = split.answerIndices[safeInt(index, -1)] ?? -1;
    results[index] = {
      correct: safeInt(selected, TIMED_OUT_ANSWER) === correctIndex,
      correctIndex,
    };
  }

  const batch = db.batch();
  batch.set(answerKeyRef(sessionRef), {answerIndices: split.answerIndices});
  batch.update(sessionRef, {questions: split.publicQuestions, results});
  await batch.commit();
}

// ============================================================
// ACHIEVEMENTS
//
// All progress is Cloud-Function-only now (applyPvpAchievementProgress /
// submitSoloLevelResult / submitDailyChallengeResult /
// syncFriendsAchievementProgress / claimWeeklyTopicCompletionReward, etc.)
// — firestore.rules locks users/{uid}/achievements/{id} to
// `allow write: if false`, and the client-side setProgress/
// syncPvpAchievements methods this used to describe were removed from
// achievement_service.dart since they could never actually write there
// anymore. Mirrors achievement_service.dart's `achievements` list
// exactly; keep both in sync.
// ============================================================

type AchievementRewardDef = {
  id: string;
  rewardCoins: number;
  rewardXp: number;
};

const ACHIEVEMENT_REWARDS: AchievementRewardDef[] = [
  {id: "first_pvp_win", rewardCoins: 10, rewardXp: 20},
  {id: "pvp_wins_10", rewardCoins: 40, rewardXp: 80},
  {id: "pvp_wins_25", rewardCoins: 100, rewardXp: 150},
  {id: "pvp_streak_5", rewardCoins: 50, rewardXp: 100},
  {id: "solo_levels_10", rewardCoins: 30, rewardXp: 60},
  {id: "solo_levels_25", rewardCoins: 60, rewardXp: 100},
  {id: "daily_streak_7", rewardCoins: 50, rewardXp: 100},
  {id: "daily_streak_21", rewardCoins: 90, rewardXp: 150},
  {id: "friends_5", rewardCoins: 25, rewardXp: 50},
  {id: "friends_10", rewardCoins: 50, rewardXp: 80},
  {id: "weekly_topics_completed_3", rewardCoins: 60, rewardXp: 100},
  {id: "categories_explored_5", rewardCoins: 40, rewardXp: 70},
];

export const claimAchievementReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const achievementId = String(request.data?.achievementId || "");
  const achievement = ACHIEVEMENT_REWARDS.find((a) => a.id === achievementId);

  if (!achievement) {
    throw new HttpsError("invalid-argument", "Achievement not found.");
  }

  const userRef = db.collection("users").doc(uid);
  const achievementRef = userRef.collection("achievements").doc(
    achievementId
  );

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(achievementRef);
    const data = snap.data();

    // localizedErrorFor's read isn't part of this transaction, which is
    // fine: it only runs on the throwing path, where the transaction is
    // about to be aborted anyway.
    if (!data) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Todavía no empezaste ese logro.",
        "Achievement not started."
      );
    }
    if (data.completed !== true) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Ese logro todavía no está completo.",
        "Achievement not completed yet."
      );
    }
    if (data.claimed === true) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Ya reclamaste esa recompensa.",
        "Reward already claimed."
      );
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(achievement.rewardCoins),
        xp: admin.firestore.FieldValue.increment(achievement.rewardXp),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      achievementRef,
      {
        claimed: true,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      rewardCoins: achievement.rewardCoins,
      rewardXp: achievement.rewardXp,
    };
  });
});

// ============================================================
// LIFE SYSTEM
//
// lifeUnits/maxLifeUnits/lifeRegenSeconds/lastLifeTickAt are protected
// fields now (see economyProtectedFields() in firestore.rules) — a
// modified client could otherwise set lifeUnits directly, bypassing the
// entire life-gating system and the buyFullLife coin sink below. Every
// mutation (regen tick, level-entry spend, wrong-answer spend, refund,
// paid refill) is a Cloud Function now; life_service.dart's client
// methods are thin wrappers around these.
// ============================================================

const BUY_FULL_LIFE_COST = 10;
// 20 units = 10 lives at UNITS_PER_LIFE. Must stay in step with
// life_service.dart's `defaultMaxLifeUnits`.
const DEFAULT_MAX_LIFE_UNITS = 20;
// Seconds per *unit* (half a life), so a full life takes 180s. Must stay in
// step with life_service.dart's `defaultRegenSeconds`.
const DEFAULT_LIFE_REGEN_SECONDS = 90;
const UNITS_PER_LIFE = 2;
const LEVEL_ENTRY_COST_UNITS = 2;
const WRONG_ANSWER_COST_UNITS = 1;
// A brand-new player learning the format can burn through their whole life
// bar failing questions before the game has hooked them — mirrors
// life_service.dart's `newPlayerGraceLevels`.
const NEW_PLAYER_GRACE_LEVELS = 2;

type LifeState = {
  lifeUnits: number;
  maxLifeUnits: number;
  lifeRegenSeconds: number;
  lastTickMs: number;
  secondsToNextHalfLife: number | null;
};

/**
 * Mirrors life_service.dart's `_stateFromData` exactly, including the
 * granular lastTickMs advance (only consumedSeconds worth, not a full
 * reset) so partial regen progress toward the next half-life isn't lost.
 * @param {Record<string, unknown>} data User document data.
 * @param {number} nowMs Current time in epoch milliseconds.
 * @return {LifeState} Current life state, accounting for regen elapsed
 * since the last tick.
 */
function computeLifeState(
  data: Record<string, unknown>, nowMs: number
): LifeState {
  let lifeUnits = safeInt(data.lifeUnits, DEFAULT_MAX_LIFE_UNITS);
  const maxLifeUnits = safeInt(data.maxLifeUnits, DEFAULT_MAX_LIFE_UNITS);
  const lifeRegenSeconds = safeInt(
    data.lifeRegenSeconds, DEFAULT_LIFE_REGEN_SECONDS
  );

  const lastTick = data.lastLifeTickAt as
    FirebaseFirestore.Timestamp | undefined;
  let lastTickMs = lastTick ? lastTick.toMillis() : nowMs;

  if (lifeUnits < maxLifeUnits) {
    const elapsedSeconds = Math.floor((nowMs - lastTickMs) / 1000);

    if (elapsedSeconds >= lifeRegenSeconds) {
      const recoveredUnits = Math.floor(elapsedSeconds / lifeRegenSeconds);
      lifeUnits = Math.min(lifeUnits + recoveredUnits, maxLifeUnits);

      const consumedSeconds = recoveredUnits * lifeRegenSeconds;
      lastTickMs = lastTickMs + consumedSeconds * 1000;

      if (lifeUnits >= maxLifeUnits) lastTickMs = nowMs;
    }
  } else {
    lifeUnits = maxLifeUnits;
    lastTickMs = nowMs;
  }

  let secondsToNextHalfLife: number | null = null;
  if (lifeUnits < maxLifeUnits) {
    const elapsedSeconds = Math.floor((nowMs - lastTickMs) / 1000);
    const remainder = elapsedSeconds % lifeRegenSeconds;
    secondsToNextHalfLife = lifeRegenSeconds - remainder;
    if (secondsToNextHalfLife <= 0) {
      secondsToNextHalfLife = lifeRegenSeconds;
    }
  }

  return {
    lifeUnits, maxLifeUnits, lifeRegenSeconds, lastTickMs,
    secondsToNextHalfLife,
  };
}

/**
 * Mirrors life_service.dart's `_stateFromData` (lifeUnits/maxLifeUnits
 * portion only — buyFullLife doesn't need the countdown fields).
 * @param {Record<string, unknown>} data User document data.
 * @return {{lifeUnits:number, maxLifeUnits:number}} Current life state,
 * accounting for regen elapsed since the last tick.
 */
function computeLifeUnits(
  data: Record<string, unknown>
): {lifeUnits: number; maxLifeUnits: number} {
  const {lifeUnits, maxLifeUnits} = computeLifeState(data, Date.now());
  return {lifeUnits, maxLifeUnits};
}

/**
 * @param {LifeState} state Computed life state.
 * @return {Record<string, unknown>} JSON-safe response shape for the
 * client — `lastLifeTickAtMs` instead of a Firestore Timestamp, since
 * callable results can't carry Timestamp objects.
 */
function lifeStateResponse(state: LifeState): Record<string, unknown> {
  return {
    lifeUnits: state.lifeUnits,
    maxLifeUnits: state.maxLifeUnits,
    lifeRegenSeconds: state.lifeRegenSeconds,
    secondsToNextHalfLife: state.secondsToNextHalfLife,
    lastLifeTickAtMs: state.lastTickMs,
  };
}

/**
 * Recomputes life state after a spend, rather than patching the pre-spend
 * one.
 *
 * `secondsToNextHalfLife` is derived from lifeUnits and lastTickMs, so
 * carrying it over from before the deduction reports the old countdown —
 * and when the player was full it reports `null`, which the UI reads as
 * "no regen pending" even though they now owe one. Harmless while callers
 * followed every spend with a refresh; wrong the moment they stopped.
 * @param {LifeState} before State as computed before the deduction.
 * @param {number} lifeUnits Units left after the deduction.
 * @param {number} lastTickMs Regen tick after the deduction.
 * @return {LifeState} Consistent state for the post-spend units.
 */
function stateAfterSpend(
  before: LifeState, lifeUnits: number, lastTickMs: number
): LifeState {
  return computeLifeState({
    lifeUnits,
    maxLifeUnits: before.maxLifeUnits,
    lifeRegenSeconds: before.lifeRegenSeconds,
    lastLifeTickAt: admin.firestore.Timestamp.fromMillis(lastTickMs),
  }, Date.now());
}

export const refreshUserLives = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};
    const nowMs = Date.now();

    const beforeUnits = safeInt(data.lifeUnits, DEFAULT_MAX_LIFE_UNITS);
    const beforeTickMissing =
      !(data.lastLifeTickAt instanceof admin.firestore.Timestamp);

    const state = computeLifeState(data, nowMs);
    const recovered = state.lifeUnits > beforeUnits;

    if (recovered || beforeTickMissing) {
      tx.set(userRef, {
        lifeUnits: state.lifeUnits,
        maxLifeUnits: state.maxLifeUnits,
        lifeRegenSeconds: state.lifeRegenSeconds,
        lastLifeTickAt:
          admin.firestore.Timestamp.fromMillis(state.lastTickMs),
      }, {merge: true});
    }

    return lifeStateResponse(state);
  });
});

export const consumeLevelEntryLife = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  // Level context is optional: Weekly Topic rounds have no level to have
  // passed, so calls without it are charged the normal way.
  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = cleanDocId(request.data?.categoryId);
  const aiTopicId = cleanDocId(request.data?.aiTopicId) || null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);

  // Answers "would this cost a life?" without spending one. The play screen
  // asks on open so it can gate a player who can't afford the level, then
  // charges for real once they actually answer — opening a level and backing
  // out used to cost a life for nothing.
  const preview = request.data?.preview === true;

  const userRef = db.collection("users").doc(uid);

  const progressRef = levelNumber < 1 ? null :
    isAiTopic && aiTopicId ?
      userRef.collection("progress_ai").doc(aiTopicId) :
      !isAiTopic && categoryId ?
        userRef.collection("progress_fixed").doc(categoryId) :
        null;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};
    const state = computeLifeState(data, Date.now());

    // Replaying a level that was already passed is free. Its one-time coin
    // payout is spent and it only pays a 20% XP trickle (see
    // submitSoloLevelResult), so charging a full life made revisiting a
    // level the worst trade in the game — and worked against the very
    // completionist play that trickle exists to reward. Decided here rather
    // than client-side: a modified client would otherwise declare every
    // level a replay and play for free.
    let replayFree = false;
    if (progressRef) {
      const progressSnap = await tx.get(progressRef);
      const passed = ((progressSnap.data()?.passedLevels as unknown[]) || [])
        .map((entry) => safeInt(entry, 0));
      replayFree = passed.includes(levelNumber);
    }

    if (replayFree) {
      return {ok: true, replayFree: true, ...lifeStateResponse(state)};
    }

    if (state.lifeUnits < LEVEL_ENTRY_COST_UNITS) {
      return {ok: false, replayFree: false, ...lifeStateResponse(state)};
    }

    if (preview) {
      return {ok: true, replayFree: false, ...lifeStateResponse(state)};
    }

    const wasFull = state.lifeUnits >= state.maxLifeUnits;
    const newUnits = state.lifeUnits - LEVEL_ENTRY_COST_UNITS;
    const newTickMs = (wasFull && newUnits < state.maxLifeUnits) ?
      Date.now() : state.lastTickMs;

    tx.set(userRef, {
      lifeUnits: newUnits,
      maxLifeUnits: state.maxLifeUnits,
      lifeRegenSeconds: state.lifeRegenSeconds,
      lastLifeTickAt: admin.firestore.Timestamp.fromMillis(newTickMs),
    }, {merge: true});

    return {ok: true, replayFree: false,
      ...lifeStateResponse(stateAfterSpend(state, newUnits, newTickMs))};
  });
});

export const buyFullLife = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const coins = safeInt(data.coins, 0);
    const {lifeUnits, maxLifeUnits} = computeLifeUnits(data);

    if (coins < BUY_FULL_LIFE_COST) {
      throw localizedError(
        data.languageCode, "failed-precondition",
        "No tienes suficientes monedas.",
        "Not enough coins."
      );
    }
    if (lifeUnits >= maxLifeUnits) {
      throw localizedError(
        data.languageCode, "failed-precondition",
        "Ya tienes las vidas completas.",
        "Life is already full."
      );
    }

    const newLifeUnits = Math.min(lifeUnits + UNITS_PER_LIFE, maxLifeUnits);
    const newCoins = coins - BUY_FULL_LIFE_COST;

    tx.set(
      userRef,
      {
        coins: newCoins,
        lifeUnits: newLifeUnits,
        maxLifeUnits,
        lastLifeTickAt: admin.firestore.Timestamp.now(),
      },
      {merge: true}
    );

    return {lifeUnits: newLifeUnits, coins: newCoins};
  });
});

// ============================================================
// THEME PURCHASES
//
// Themes are code, not data — the client renders them from its own
// catalogue in lib/theme/app_themes.dart, and Firestore only records which
// ids a player owns. So this table is the authority on *price*, never the
// client: `purchaseTheme` ignores any amount the caller sends.
//
// Mirrors AppThemes in lib/theme/app_themes.dart — the free theme isn't
// listed because nothing is charged for it and nobody needs to own it
// explicitly. `test/theme/theme_catalog_sync_test.dart` keeps the prices
// here and there from drifting apart.
// ============================================================

const THEME_PRICES: Record<string, number> = {
  "playful": 400,
  "night": 400,
  "ocean": 250,
  "sunset": 250,
  "forest": 250,
  "space": 400,
  "vintage": 400,
  "apocalypse": 400,
  "cyberpunk": 400,
  "steampunk": 400,
  "christmas": 400,
};

export const purchaseTheme = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const themeId = String(request.data?.themeId || "");
  const price = THEME_PRICES[themeId];

  if (price === undefined) {
    throw new HttpsError("invalid-argument", `Unknown theme: ${themeId}`);
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const owned: string[] = Array.isArray(data.ownedThemes) ?
      data.ownedThemes.map((id: unknown) => String(id)) :
      [];

    const coins = safeInt(data.coins, 0);

    // Idempotent rather than an error: a retry after a dropped response
    // must not charge twice, and the client can't tell the two apart.
    if (owned.includes(themeId)) {
      return {themeId, coins, alreadyOwned: true};
    }

    if (coins < price) {
      throw localizedError(
        data.languageCode, "failed-precondition",
        "No tienes suficientes monedas.",
        "Not enough coins."
      );
    }

    const newCoins = coins - price;

    tx.set(
      userRef,
      {
        coins: newCoins,
        ownedThemes: [...owned, themeId],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {themeId, coins: newCoins, alreadyOwned: false};
  });
});

// ============================================================
// COIN PURCHASES (IAP)
//
// Coins for real money are credited only after the store itself confirms
// the payment — never on the client's say-so, the same way no other
// economy path in this file trusts a client-reported amount.
//
// Google Play: the purchase token is checked with the Play Developer API
// (purchases.products.get) and recorded in `coin_purchases/{hash}`, so
// one token credits one account once. The client consumes the purchase
// only after this returns, so a failure here leaves it pending and the
// store hands it back on the next launch.
//
// App Store: still fail-closed. Verifying needs the App Store Server
// API's key, issued with the Apple Developer membership.
//
// Mirrors economy_service.dart's `EconomyService.coinPacks` exactly —
// keep both in sync. Ids must match the products configured in each
// store once those accounts exist.
// ============================================================

const PLAY_PACKAGE_NAME = "pe.massivedynamics.triviaia";

/**
 * An access token for the Play Developer API, from this function's own
 * service account.
 *
 * Taken from the metadata server with the androidpublisher scope rather
 * than through a client library, so verifying a purchase adds no
 * dependency. The service account still has to be granted access in Play
 * Console → Users and permissions, or Play answers 401/403.
 * @return {Promise<string>} Bearer token.
 */
async function playDeveloperAccessToken(): Promise<string> {
  const response = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/" +
      "service-accounts/default/token" +
      "?scopes=https://www.googleapis.com/auth/androidpublisher",
    {headers: {"Metadata-Flavor": "Google"}}
  );

  if (!response.ok) {
    throw new Error(`Metadata token request failed: ${response.status}`);
  }

  const body = await response.json() as {access_token?: unknown};
  if (typeof body.access_token !== "string") {
    throw new Error("Metadata token response had no access_token.");
  }
  return body.access_token;
}

/**
 * Asks Play about one product purchase.
 *
 * The error codes are chosen for what the client does with them: every
 * failure keeps the purchase pending, so a passing outage or a missing
 * Play Console permission costs the player a delay, not their money.
 * @param {string} uid Caller, for the localized message.
 * @param {string} productId In-app product id.
 * @param {string} purchaseToken Token from the purchase.
 * @return {Promise<unknown>} Play's ProductPurchase JSON.
 */
async function fetchPlayProductPurchase(
  uid: string,
  productId: string,
  purchaseToken: string
): Promise<unknown> {
  let response: Response;
  try {
    response = await fetch(
      playProductPurchaseUrl(PLAY_PACKAGE_NAME, productId, purchaseToken),
      {headers: {Authorization: `Bearer ${await playDeveloperAccessToken()}`}}
    );
  } catch (error) {
    console.error("Play purchase lookup could not be made", error);
    throw await localizedErrorFor(
      uid, "unavailable",
      "No se pudo verificar la compra. Se reintentará.",
      "Couldn't verify the purchase. It will be retried."
    );
  }

  if (response.ok) return response.json();

  // 401/403: this service account isn't allowed to read purchases in
  // Play Console. A setup problem, not the player's — keep it pending.
  if (response.status === 401 || response.status === 403) {
    console.error(
      "Play refused the purchase lookup; check that the functions " +
        "service account has access in Play Console.",
      response.status, await response.text()
    );
    throw await localizedErrorFor(
      uid, "unavailable",
      "No se pudo verificar la compra. Se reintentará.",
      "Couldn't verify the purchase. It will be retried."
    );
  }

  // 400/404/410: Play doesn't know this token for this product.
  if (response.status >= 400 && response.status < 500) {
    console.warn(
      "Play rejected a purchase token", productId, response.status
    );
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "La tienda no reconoce esta compra.",
      "The store doesn't recognize this purchase."
    );
  }

  console.error("Play purchase lookup failed", response.status);
  throw await localizedErrorFor(
    uid, "unavailable",
    "No se pudo verificar la compra. Se reintentará.",
    "Couldn't verify the purchase. It will be retried."
  );
}

const COIN_PACKS: Record<string, number> = {
  "coins_pack_small": 100,
  "coins_pack_ai_topic": 600,
  "coins_pack_medium": 1500,
  "coins_pack_large": 4000,
};

export const verifyCoinPurchase = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const productId = String(request.data?.productId || "");
  const source = String(request.data?.source || "");
  const verificationData = String(request.data?.verificationData || "");

  const coins = COIN_PACKS[productId];
  if (!coins) {
    throw new HttpsError("invalid-argument", "Unknown coin pack.");
  }
  if (!source || !verificationData) {
    throw new HttpsError("invalid-argument", "Missing verification data.");
  }

  if (source !== "google_play") {
    // App Store verification needs the App Store Server API key, which
    // only exists with the Apple Developer membership. Until then iOS
    // purchases stay pending rather than being trusted.
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Las compras de monedas todavía no están habilitadas en este " +
        "dispositivo.",
      "Coin purchases aren't enabled on this device yet."
    );
  }

  // On Android, serverVerificationData is the purchase token.
  const purchaseToken = verificationData;
  const verdict = judgePlayProductPurchase(
    await fetchPlayProductPurchase(uid, productId, purchaseToken)
  );

  if (!verdict.ok) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      verdict.reason === "pending" ?
        "El pago todavía está pendiente. Las monedas llegarán cuando se " +
          "confirme." :
        "Esta compra no se completó.",
      verdict.reason === "pending" ?
        "The payment is still pending. The coins will arrive once it " +
          "clears." :
        "This purchase wasn't completed."
    );
  }

  const ledgerRef = db.collection("coin_purchases")
    .doc(purchaseLedgerId(purchaseToken));
  const userRef = db.collection("users").doc(uid);

  const outcome = await db.runTransaction(async (tx) => {
    const ledgerSnap = await tx.get(ledgerRef);
    const userSnap = await tx.get(userRef);

    const ledgerUid = ledgerSnap.exists ?
      String(ledgerSnap.data()?.uid || "") : null;
    const decision = decideCoinCredit(ledgerUid, uid, verdict.consumed);
    const balance = safeInt(userSnap.data()?.coins, 0);

    if (decision !== "credit") {
      return {decision, coins: balance};
    }

    const newCoins = balance + coins;

    tx.set(ledgerRef, {
      uid,
      productId,
      coins,
      source,
      orderId: verdict.orderId,
      purchaseTimeMillis: verdict.purchaseTimeMillis,
      test: verdict.test,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(
      userRef,
      {
        coins: newCoins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {decision, coins: newCoins};
  });

  if (
    outcome.decision === "claimed-by-another-account" ||
    outcome.decision === "consumed-elsewhere"
  ) {
    console.warn(
      "Refused a coin purchase replay", outcome.decision, productId, uid
    );
    throw await localizedErrorFor(
      uid, "permission-denied",
      "Esta compra ya fue usada.",
      "This purchase has already been used."
    );
  }

  // "already-credited" answers like a fresh credit on purpose: the client
  // finishes the purchase with the store only when it hears success.
  return {
    grantedCoins: coins,
    coins: outcome.coins,
    alreadyCredited: outcome.decision === "already-credited",
  };
});

// ============================================================
// AI TOPICS ECONOMY
//
// Content generation is a real Claude call (AI_MODEL), so it can fail —
// transiently, or because the topic's title turns out to be blocked
// (blocked_ai_topics / AI_TOPIC_SYSTEM_PROMPT). `createAiTopic` still
// only charges after generation succeeds, so a failure there is free.
// `ensureAiTopicLevelsGenerated`/`regenerateAiTopicQuestions` operate on
// an *already-charged* topic though, so a failure partway through marks
// the topic `status: "blocked"` instead — `refundAiTopicCost` (called
// from `deleteAiTopic`) is how the player gets their coins back for one
// of those, not just a safety net for pre-migration topics anymore.
// ============================================================

const CREATE_AI_TOPIC_COST = 600;
// Charged instead of CREATE_AI_TOPIC_COST when the requested title+language
// already has a ready shared pool entry that's crossed the "popular" usage
// threshold (see AI_TOPIC_POPULAR_USAGE_THRESHOLD below) — no Claude call
// needed either way, but the deeper discount is reserved for genuinely
// popular reuses so per-topic revenue doesn't collapse once most requests
// start matching *something* already in the pool. Keep in sync with
// lib/services/economy_service.dart's `createAiTopicFromPoolCost`.
const CREATE_AI_TOPIC_FROM_POOL_COST = 300;
// Charged instead of CREATE_AI_TOPIC_COST when reusing an existing pool
// entry that hasn't crossed the popular threshold yet — still a real
// discount (no Claude call), just smaller than a popular reuse. Keep in
// sync with lib/services/economy_service.dart's `createAiTopicExistingCost`.
const CREATE_AI_TOPIC_EXISTING_COST = 400;
// Regenerating scales with how much content there actually is to redo —
// a flat cost let a topic buffered/expanded to 10+ levels regenerate all
// of them for the same price a fresh 2-level topic would pay. 75/level
// keeps the common case (regenerating the initial 2 levels) at the same
// 150 coins as before.
const REGENERATE_AI_QUESTIONS_COST_PER_LEVEL = 75;
const EXPAND_AI_TOPIC_COST = 300;
const MAX_AI_TOPICS_PER_USER = 20;
const FIRST_AI_TOPIC_FREE_PASSES = 1;

// Mirrors ai_topic_service.dart's `_reservedTopicNames` exactly.
const RESERVED_TOPIC_NAMES = new Set([
  "movies", "movie", "cine", "history", "historia", "science", "ciencia",
  "geography", "geografia", "geografía", "books", "libros", "video games",
  "videogames", "videojuegos", "sports", "deportes",
]);

/**
 * Mirrors ai_topic_service.dart's `normalizeTopicTitle`.
 * @param {string} title Raw title.
 * @return {string} Normalized title.
 */
function normalizeTopicTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * Lowercases, strips accents, and collapses everything but letters/digits
 * to single spaces — so blocklist matching in `matchesBlockedKeyword`
 * isn't defeated by accents, punctuation, or hyphenation
 * (e.g. "S-U-I-C-I-D-I-O" or "autolesión").
 * @param {string} title Raw title.
 * @return {string} Normalized title for moderation matching.
 */
function normalizeForModeration(title: string): string {
  const ascii = title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  if (ascii) return ascii;
  // A title with no Latin letters or digits (emoji, other scripts,
  // "¿¡?!") reduced to "", which was then used as a doc id and failed
  // every AI-topic call with INTERNAL. It keys on a digest of the title
  // instead, so it still has its own blocklist entry.
  return "u " + crypto.createHash("sha256")
    .update(title.trim().toLowerCase()).digest("hex").slice(0, 32);
}

// Deliberately narrow to bright-line categories where a plain keyword
// match is reliable — suicide/self-harm, sexual content (including
// CSAM-adjacent terms), and explicit dangerous-instructions phrasing.
// Broader judgment calls (hate speech, graphic historical violence, etc.)
// are left to AI_TOPIC_SYSTEM_PROMPT, since a blunt keyword list would
// false-positive on legitimate sensitive trivia topics (e.g. "World War
// II", "the opioid epidemic"). This is a fast, free pre-filter for the
// obvious cases, not meant to be exhaustive — normalizeForModeration
// resists simple bypasses, but a keyword list alone never will be.
const BLOCKED_TOPIC_KEYWORDS = [
  // Suicide / self-harm
  "suicide", "suicidio", "suicidal",
  "self harm", "autolesion", "autolesiones", "automutilacion",
  "kill myself", "matarme", "quitarme la vida",
  // Sexual content / pornography (including CSAM)
  "porn", "porno", "pornography", "pornografia",
  "hentai", "nsfw", "xxx",
  "nude", "nudes", "desnudo", "desnudos", "desnuda", "desnudas",
  "erotic", "erotica", "erotico",
  "incest", "incesto",
  "child porn", "csam", "pedophile", "pedophilia", "pedofilo", "pedofilia",
  // Explicit dangerous instructions
  "how to make a bomb", "como hacer una bomba",
  "how to build a bomb", "como construir una bomba",
  "how to make explosives", "como fabricar explosivos",
  "how to make meth", "como fabricar metanfetamina",
].map(normalizeForModeration);

/**
 * @param {string} normalizedTitle Title run through
 * `normalizeForModeration`.
 * @return {boolean} True if it contains a blocked keyword/phrase.
 */
function matchesBlockedKeyword(normalizedTitle: string): boolean {
  return BLOCKED_TOPIC_KEYWORDS.some((term) =>
    normalizedTitle.includes(term)
  );
}

/**
 * Whether this normalized title was already blocked before — by keyword
 * match or a prior Claude refusal — so rewording the same rejected idea
 * slightly doesn't buy unlimited retries against the API.
 * @param {string} normalizedTitle Title run through
 * `normalizeForModeration`.
 * @return {Promise<boolean>} True if previously blocked.
 */
async function isTopicPreviouslyBlocked(
  normalizedTitle: string
): Promise<boolean> {
  const snap = await db.collection("blocked_ai_topics")
    .doc(normalizedTitle).get();
  return snap.exists;
}

/**
 * Records a blocked topic attempt so future attempts — from any user —
 * with the same normalized title are rejected immediately, without
 * spending another API call.
 * @param {string} title Original (non-normalized) title, for debugging.
 * @param {string} normalizedTitle Title run through
 * `normalizeForModeration` (used as the doc id).
 * @param {"keyword" | "model_refusal"} reason How it was blocked.
 * @return {Promise<void>} Resolves once the record is written.
 */
async function recordBlockedTopic(
  title: string,
  normalizedTitle: string,
  reason: "keyword" | "model_refusal"
): Promise<void> {
  await db.collection("blocked_ai_topics").doc(normalizedTitle).set({
    title,
    normalizedTitle,
    reason,
    lastBlockedAt: admin.firestore.FieldValue.serverTimestamp(),
    blockedCount: admin.firestore.FieldValue.increment(1),
  }, {merge: true});
}

/**
 * Thrown by `requestAiQuestionsFromClaude` when the topic's title is
 * blocked (previously recorded, or refused by Claude just now) — a
 * distinct type from `HttpsError` so callers (createAiTopic,
 * ensureAiTopicLevelsGenerated, regenerateAiTopicQuestions) can tell a
 * "this exact topic is blocked" failure apart from any other error and
 * react accordingly (e.g. marking the topic doc `status: "blocked"`)
 * instead of string-matching on an error message.
 */
class TopicBlockedError extends Error {}

/**
 * @param {unknown} languageCode The caller's stored `languageCode`.
 * @return {HttpsError} The client-facing error for a blocked topic.
 */
function topicBlockedHttpsError(languageCode?: unknown): HttpsError {
  return localizedError(
    languageCode, "failed-precondition",
    "No se pudo generar ese tema. Intenta con otro título.",
    "That topic couldn't be generated. Try a different title."
  );
}

interface GeneratedAiQuestion {
  q: string;
  options: string[];
  answerIndex: number;
  explanation: string;
}

/**
 * A question as the model returns it. It names the correct answer instead
 * of giving its position — the position is ours to assign, see
 * [buildAnswerOptions].
 */
interface ModelAiQuestion {
  q: string;
  correctAnswer: string;
  wrongAnswers: string[];
  explanation: string;
}

/**
 * Difficulty label for a given AI-topic level number (1-10, scaled easy
 * to hard), localized via the recipient's stored languageCode.
 * @param {number} levelNumber Level number (1-10).
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {string} Localized difficulty label.
 */
function aiLevelDifficultyLabel(
  levelNumber: number,
  languageCode: unknown
): string {
  if (levelNumber <= 3) return pickText(languageCode, "fácil", "easy");
  if (levelNumber <= 7) return pickText(languageCode, "intermedio", "medium");
  return pickText(languageCode, "difícil", "hard");
}

/**
 * Calls Claude (AI_MODEL) to generate one level's worth of trivia questions
 * for a user-created AI topic and validates the shape of the response.
 * Retries once on a malformed/incomplete response before giving up.
 * @param {string} title Topic title (e.g. "Dinosaurios").
 * @param {number} levelNumber Level number (1-10) — scales difficulty.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @param {object} options `count` to generate (defaults to a full level)
 * and `avoidQuestions`, existing texts the model must not repeat.
 * @return {Promise<GeneratedAiQuestion[]>} Exactly `count` validated
 * questions.
 */
async function requestAiQuestionsFromClaude(
  title: string,
  levelNumber: number,
  languageCode: unknown,
  options: {count?: number; avoidQuestions?: string[]} = {}
): Promise<GeneratedAiQuestion[]> {
  const count = options.count ?? AI_QUESTIONS_PER_LEVEL;
  const avoidQuestions = options.avoidQuestions ?? [];
  const moderationKey = normalizeForModeration(title);

  // Covers regenerate/expand/buffer calls too (they all funnel through
  // here reusing the topic's already-stored title), not just the initial
  // createAiTopic check — so a topic that got refused on a later level
  // doesn't keep burning API calls on every subsequent level attempt.
  if (await isTopicPreviouslyBlocked(moderationKey)) {
    throw new TopicBlockedError("Topic previously blocked.");
  }

  const client = new Anthropic({apiKey: anthropicApiKey.value()});
  const outputLanguage = pickText(languageCode, "Spanish", "English");
  const difficulty = aiLevelDifficultyLabel(levelNumber, languageCode);

  // Questions already banked for this topic, so a top-up doesn't hand
  // back what the player has already been asked. The whole topic goes
  // in, each question cut to a recognisable prefix.
  const avoidList = avoidQuestions
    .slice(0, AI_AVOID_LIST_MAX_QUESTIONS)
    .map((q) => `- ${q.slice(0, AI_AVOID_LIST_MAX_CHARS)}`)
    .join("\n");

  const prompt = `Generate exactly ${count} multiple-choice ` +
    `trivia questions about "${title}", at ${difficulty} difficulty ` +
    `(this is level ${levelNumber} of ${AI_LEVELS_PER_TOPIC}; difficulty ` +
    "should scale up with the level number). Write every question, " +
    `answer, and explanation in ${outputLanguage}. Each question needs ` +
    "one correct answer and exactly 3 wrong answers that are plausible " +
    "but unambiguously incorrect, each different from the others. Do " +
    "not repeat questions or trivially reword the same fact twice." +
    (avoidList ?
      "\n\nThese questions already exist for this topic. Do not repeat " +
      "any of them, and do not ask the same fact in different words — " +
      `cover different ground:\n${avoidList}` :
      "");

  const schema = {
    type: "object",
    properties: {
      questions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            q: {type: "string"},
            correctAnswer: {type: "string"},
            wrongAnswers: {type: "array", items: {type: "string"}},
            explanation: {type: "string"},
          },
          required: ["q", "correctAnswer", "wrongAnswers", "explanation"],
          additionalProperties: false,
        },
      },
    },
    required: ["questions"],
    additionalProperties: false,
  };

  let lastError: unknown;

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await client.messages.create({
        model: AI_MODEL,
        max_tokens: 16000,
        system: AI_TOPIC_SYSTEM_PROMPT,
        messages: [{role: "user", content: prompt}],
        output_config: {format: {type: "json_schema", schema}},
      });

      // Claude's safety classifiers declined the topic (HTTP 200, empty
      // content) — retrying the identical prompt will refuse again, so
      // fail fast with a message the player can act on instead of burning
      // the retry budget.
      if (response.stop_reason === "refusal") {
        await recordBlockedTopic(title, moderationKey, "model_refusal");
        throw new TopicBlockedError("Topic refused by model.");
      }

      // Haiku 5.5 thinks by default, so the text is no longer guaranteed
      // to be the first block — reasoning blocks precede it.
      const block = response.content.find((b) => b.type === "text");
      if (!block) {
        throw new Error("Unexpected response block type from Claude.");
      }

      const parsed = JSON.parse(block.text) as {
        questions?: ModelAiQuestion[];
      };
      const drafts = parsed.questions || [];

      if (drafts.length !== count) {
        throw new Error(
          `Expected ${count} questions, got ` +
          `${drafts.length}.`
        );
      }

      return drafts.map((draft) => {
        // Seeded by the question text so a question always lays out the
        // same way, while different questions land on different slots.
        const built = typeof draft.q === "string" && draft.q.trim() !== "" ?
          buildAnswerOptions(
            draft.correctAnswer, draft.wrongAnswers, fnv1a32(draft.q)
          ) :
          null;

        if (!built) {
          throw new Error("Malformed question from Claude.");
        }

        return {
          q: draft.q,
          options: built.options,
          answerIndex: built.answerIndex,
          explanation: draft.explanation,
        };
      });
    } catch (error) {
      if (error instanceof HttpsError || error instanceof TopicBlockedError) {
        throw error;
      }
      lastError = error;
    }
  }

  console.error("AI topic question generation failed", lastError);
  throw localizedError(
    languageCode, "internal",
    "No se pudo generar el tema con IA. Intenta de nuevo.",
    "The topic couldn't be generated with AI. Please try again."
  );
}

/**
 * Every question text currently banked for a topic, across all its
 * levels — the "don't write these again" context for a top-up.
 *
 * Walks the pool's own levels rather than using a collection-group query:
 * `questions` is also the collection name under `fixed_pools`, so a group
 * query would span unrelated content and need its own index. Callers
 * should do this once per generation run, not once per level.
 * @param {FirebaseFirestore.DocumentReference} poolRef Pool document ref.
 * @return {Promise<string[]>} Existing question texts, ordered for
 * [capAvoidList]'s `rest`.
 */
async function existingPoolQuestionTexts(
  poolRef: FirebaseFirestore.DocumentReference
): Promise<string[]> {
  const levelsSnap = await poolRef.collection("levels").get();

  const levelDocs = [...levelsSnap.docs].sort((a, b) =>
    safeInt(b.data().levelNumber, 0) - safeInt(a.data().levelNumber, 0)
  );

  if (levelDocs.length === 0) return [];

  // Every question, not a slice of each level. A slice left the rest of
  // the bank unknown to both the model and the duplicate check on what it
  // returns, and those questions were written again verbatim. Only the
  // text is fetched: a document read each, but none of the payload.
  const perLevel = await Promise.all(levelDocs.map(async (levelDoc) => {
    const questionsSnap = await levelDoc.ref
      .collection("questions").select("q").get();

    return questionsSnap.docs
      .map((doc) => String(doc.data().q || ""))
      .filter((q) => q.length > 0);
  }));

  return interleaveByLevel(perLevel);
}

/**
 * How many questions are banked across the levels a player has unlocked.
 *
 * This is what the topics list means by "N preguntas". It has to be
 * counted rather than derived as `levels * AI_QUESTIONS_PER_LEVEL`: banks
 * accumulate past ten per level, so the arithmetic version silently
 * understated a topic and — worse — never moved after a player *paid* to
 * add questions, making the purchase look like it did nothing.
 * @param {FirebaseFirestore.DocumentReference} poolRef Pool document ref.
 * @param {number} upToLevel Highest level the player has unlocked.
 * @return {Promise<number>} Total banked questions across those levels.
 */
async function readLevelBankSizes(
  poolRef: FirebaseFirestore.DocumentReference,
  upToLevel: number
): Promise<Map<number, number>> {
  const sizeByLevel = new Map<number, number>();
  if (upToLevel <= 0) return sizeByLevel;

  const levelsSnap = await poolRef.collection("levels").get();

  for (const levelDoc of levelsSnap.docs) {
    const levelNumber = safeInt(levelDoc.data().levelNumber, 0);
    if (levelNumber >= 1 && levelNumber <= upToLevel) {
      sizeByLevel.set(levelNumber, safeInt(levelDoc.data().questionsCount, 0));
    }
  }

  return sizeByLevel;
}

/**
 * Sums the bank sizes a [readLevelBankSizes] map holds.
 * @param {Map<number, number>} sizeByLevel Bank size per level.
 * @return {number} Total banked questions.
 */
function totalBankedQuestions(sizeByLevel: Map<number, number>): number {
  let total = 0;
  for (const size of sizeByLevel.values()) total += size;
  return total;
}

/**
 * Total questions banked across the levels a player has unlocked. Callers
 * that already hold a [readLevelBankSizes] map should sum it with
 * [totalBankedQuestions] instead of paying for this second read.
 * @param {FirebaseFirestore.DocumentReference} poolRef Pool document ref.
 * @param {number} upToLevel Highest level the player has unlocked.
 * @return {Promise<number>} Total banked questions across those levels.
 */
async function countBankedQuestions(
  poolRef: FirebaseFirestore.DocumentReference,
  upToLevel: number
): Promise<number> {
  return totalBankedQuestions(await readLevelBankSizes(poolRef, upToLevel));
}

/**
 * Which of a player's unlocked levels still have room in their bank —
 * the levels an "add more questions" purchase is priced on.
 * @param {Map<number, number>} sizeByLevel Bank size per level.
 * @param {number} upToLevel Highest level the player has unlocked.
 * @return {number[]} Level numbers that still have headroom.
 */
function expandableLevelsFrom(
  sizeByLevel: Map<number, number>,
  upToLevel: number
): number[] {
  const levels: number[] = [];
  for (let level = 1; level <= upToLevel; level++) {
    if (bankHeadroom(sizeByLevel.get(level) ?? 0) > 0) levels.push(level);
  }

  return levels;
}

/**
 * Claims the exclusive right to generate into [levelRef]'s bank.
 *
 * The lock is a self-expiring timestamp rather than a flag so a crashed or
 * timed-out generation can't wedge a level permanently — worst case the
 * next caller waits out [AI_LEVEL_LOCK_MS] and retries.
 * @param {FirebaseFirestore.DocumentReference} levelRef Level doc to lock.
 * @return {Promise<boolean>} True when this caller may generate.
 */
async function acquireLevelLock(
  levelRef: FirebaseFirestore.DocumentReference
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(levelRef);
    const heldUntil = snap.data()?.generatingUntil as
      admin.firestore.Timestamp | undefined;

    if (heldUntil && heldUntil.toMillis() > Date.now()) return false;

    tx.set(levelRef, {
      generatingUntil: admin.firestore.Timestamp.fromMillis(
        Date.now() + AI_LEVEL_LOCK_MS
      ),
    }, {merge: true});
    return true;
  });
}

/**
 * Waits out whoever holds [levelRef]'s lock and reports what they added.
 *
 * Returning the new question texts (rather than an empty list) is what lets
 * the loser of the race behave exactly like the winner: callers extend
 * their avoid-list with them, and ensureSoloLevelSession sees a non-empty
 * result and serves the level instead of reporting it unpreparable.
 * @param {FirebaseFirestore.DocumentReference} levelRef Level doc to watch.
 * @param {Set<string>} knownIds Question ids already present before waiting.
 * @return {Promise<string[]>} Texts added by the lock holder, if any.
 */
async function awaitLevelGeneration(
  levelRef: FirebaseFirestore.DocumentReference,
  knownIds: Set<string>
): Promise<string[]> {
  const deadline = Date.now() + AI_LEVEL_LOCK_WAIT_MS;

  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, AI_LEVEL_LOCK_POLL_MS));

    const snap = await levelRef.get();
    const heldUntil = snap.data()?.generatingUntil as
      admin.firestore.Timestamp | undefined;
    if (heldUntil && heldUntil.toMillis() > Date.now()) continue;

    const questionsSnap = await levelRef.collection("questions").get();
    return questionsSnap.docs
      .filter((doc) => !knownIds.has(doc.id))
      .map((doc) => String(doc.data().q || ""))
      .filter((q) => q.length > 0);
  }

  return [];
}

/**
 * Appends a batch of freshly generated questions to one level's bank.
 *
 * Questions accumulate rather than overwrite: ids continue from the
 * highest existing suffix (`q_11`, `q_12`, ...), so a top-up never
 * destroys content another player is mid-way through — the reason the
 * old fixed `q_1..q_10` scheme had to go. Growth stops at
 * [AI_QUESTION_BANK_CAP].
 *
 * Always writes into the shared `ai_topic_pool` entry, never into a
 * per-user topic doc — every AI topic's question content lives in the
 * pool (see the "Shared AI-topic content pool" plan), so every caller
 * passes the resolved pool ref here.
 *
 * Serialized per level: a second caller that arrives while a generation is
 * in flight waits for it and reports its questions rather than appending a
 * duplicate batch of its own.
 * @param {string} uid Account whose daily generation budget this draws on.
 * @param {FirebaseFirestore.DocumentReference} poolRef Pool document ref.
 * @param {number} levelNumber Level to top up.
 * @param {string} title Topic title, used as the generation subject.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @param {object} options `count` to add, and existing texts to avoid.
 * @return {Promise<string[]>} Texts of the questions added to the bank.
 */
async function generateAiTopicLevel(
  uid: string,
  poolRef: FirebaseFirestore.DocumentReference,
  levelNumber: number,
  title: string,
  languageCode: unknown,
  options: {count?: number; avoidQuestions?: string[]} = {}
): Promise<string[]> {
  const levelRef = poolRef.collection("levels").doc(`level_${levelNumber}`);
  const existingSnap = await levelRef.collection("questions").get();
  const existingIds = existingSnap.docs.map((doc) => doc.id);

  const requested = options.count ?? AI_QUESTIONS_PER_LEVEL;
  const count = Math.min(requested, bankHeadroom(existingIds.length));
  if (count <= 0) return [];

  if (!await acquireLevelLock(levelRef)) {
    return awaitLevelGeneration(levelRef, new Set(existingIds));
  }

  try {
    return await generateIntoLockedLevel(
      uid, levelRef, existingIds, existingSnap, count,
      levelNumber, title, languageCode, options.avoidQuestions ?? []
    );
  } finally {
    await levelRef.set(
      {generatingUntil: admin.firestore.FieldValue.delete()},
      {merge: true}
    );
  }
}

/**
 * The generating half of `generateAiTopicLevel`, split out so the lock it
 * runs under is released on every exit path.
 * @param {string} uid Account to meter the Claude spend against.
 * @param {FirebaseFirestore.DocumentReference} levelRef Locked level doc.
 * @param {string[]} existingIds Question ids already banked.
 * @param {FirebaseFirestore.QuerySnapshot} existingSnap Those questions.
 * @param {number} count How many questions to ask Claude for.
 * @param {number} levelNumber Level being generated.
 * @param {string} title Topic title.
 * @param {unknown} languageCode Recipient's language.
 * @param {string[]} callerAvoid Cross-level questions to avoid repeating.
 * @return {Promise<string[]>} Texts of the questions just generated.
 */
async function generateIntoLockedLevel(
  uid: string,
  levelRef: FirebaseFirestore.DocumentReference,
  existingIds: string[],
  existingSnap: FirebaseFirestore.QuerySnapshot,
  count: number,
  levelNumber: number,
  title: string,
  languageCode: unknown,
  callerAvoid: string[]
): Promise<string[]> {
  // Every billable generation path in the codebase funnels through here,
  // which is the point: metering at the single choke point means a route
  // added later can't quietly bypass the cap. Charged after the headroom
  // check above, so a level that turns out to be full costs nothing.
  await consumeAiBudget(uid, "levels", 1);

  // Ordered so this level's own questions survive the prompt's truncation
  // — a caller's cross-level list is pool-wide, and trimming that blindly
  // would keep level 1's oldest questions while dropping the very ones
  // this batch sits next to.
  const avoidQuestions = capAvoidList(
    existingSnap.docs
      .map((doc) => String(doc.data().q || ""))
      .filter((q) => q.length > 0),
    callerAvoid,
    AI_AVOID_LIST_MAX_QUESTIONS
  );

  const generated = await requestAiQuestionsFromClaude(
    title, levelNumber, languageCode, {count, avoidQuestions}
  );

  // The avoid-list is an instruction, not a guarantee: the model still
  // returns the occasional question it was just told not to write. Dropping
  // it here is the difference between a duplicate that never reaches a
  // player and one banked forever. No replacement call — that would be a
  // second Claude round-trip outside the metering above, and the level
  // refills through the normal top-up path on the next play.
  // Checked against everything already in hand, not just `avoidQuestions`:
  // that list is capped for the prompt, so a question the cap trimmed would
  // otherwise slip straight back into the bank.
  const seenKeys = new Set(
    [
      ...avoidQuestions,
      ...callerAvoid,
      ...existingSnap.docs.map((doc) => String(doc.data().q || "")),
    ].map(questionDedupeKey)
  );
  const questions = generated.filter((question) => {
    const key = questionDedupeKey(question.q);
    if (!key || seenKeys.has(key)) return false;
    seenKeys.add(key);
    return true;
  });

  const dropped = generated.length - questions.length;
  if (dropped > 0) {
    console.warn(
      `AI level ${levelNumber} of "${title}": dropped ${dropped} of ` +
      `${generated.length} generated questions as duplicates`
    );
  }

  if (questions.length === 0) return [];

  const ids = nextQuestionIds(existingIds, questions.length);
  const batch = db.batch();

  batch.set(levelRef, {
    levelNumber,
    title: `Level ${levelNumber}`,
    questionsCount: existingIds.length + questions.length,
    // Kept on the level doc so starting a session can pick its slate
    // without listing the whole bank first — see ensureSoloLevelSession.
    questionIds: [...existingIds, ...ids].sort(compareQuestionIds),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(existingIds.length === 0 ?
      {createdAt: admin.firestore.FieldValue.serverTimestamp()} : {}),
  }, {merge: true});

  questions.forEach((question, index) => {
    batch.set(levelRef.collection("questions").doc(ids[index]), {
      q: question.q,
      options: question.options,
      answerIndex: question.answerIndex,
      explanation: question.explanation,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();

  // The texts, not just the count: callers generating several levels in a
  // row extend their own avoid-list with these instead of re-reading the
  // whole pool between levels.
  return questions.map((question) => question.q);
}

/**
 * Reserves [units] of a daily Claude spend meter, or throws if today's
 * budget is already gone.
 *
 * Counters live in `ai_usage/{dateId}` (project-wide) and
 * `ai_usage/{dateId}/users/{uid}`, bucketed by the *server's* date so a
 * device with a rolled-back clock can't reopen yesterday's allowance, and
 * read-then-incremented inside one transaction so two concurrent requests
 * can't both slip past a nearly-exhausted cap. Old buckets need no
 * cleanup — a new day simply reads a document that doesn't exist yet.
 *
 * The global counter is a single hot document, which at these ceilings
 * averages well under one write per second; bursts rely on normal
 * transaction retries.
 * @param {string} uid Account to charge.
 * @param {AiMeter} meter Which spend meter to charge.
 * @param {number} units How much to reserve.
 * @return {Promise<void>} Resolves once the units are reserved.
 */
async function consumeAiBudget(
  uid: string,
  meter: AiMeter,
  units: number
): Promise<void> {
  if (units <= 0) return;

  const dateId = serverDateId();
  const globalRef = db.collection("ai_usage").doc(dateId);
  const perUserRef = globalRef.collection("users").doc(uid);
  const caps = AI_METER_CAPS[meter];

  const verdict = await db.runTransaction(async (tx) => {
    const [globalSnap, userSnap] = await Promise.all([
      tx.get(globalRef),
      tx.get(perUserRef),
    ]);

    const result = checkAiBudget({
      globalUsed: safeInt(globalSnap.data()?.[meter], 0),
      userUsed: safeInt(userSnap.data()?.[meter], 0),
      units,
      caps,
    });

    if (!result.allowed) return result;

    const bump = {
      [meter]: admin.firestore.FieldValue.increment(units),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    tx.set(globalRef, bump, {merge: true});
    tx.set(perUserRef, bump, {merge: true});

    return result;
  });

  if (verdict.allowed) return;

  // Deliberately distinct messages: "the service is out" is not the
  // player's doing and shouldn't read like an accusation, whereas their
  // own limit is something they can reason about.
  if (verdict.limit === "global") {
    console.warn(`AI daily ${meter} budget exhausted project-wide`);
    throw await localizedErrorFor(
      uid, "resource-exhausted",
      "El servicio de IA alcanzó su límite diario. Intenta mañana.",
      "The AI service reached its daily limit. Please try again tomorrow."
    );
  }

  throw await localizedErrorFor(
    uid, "resource-exhausted",
    "Alcanzaste tu límite diario de generación con IA. Intenta mañana.",
    "You've reached your daily AI generation limit. Try again tomorrow."
  );
}

/**
 * Deletes every `levels/*` doc (and nested `questions/*`) under a topic
 * ref — used to clean up orphaned content when a multi-level generation
 * loop fails partway through, so a failed level 2 doesn't leave level 1's
 * questions sitting under a topic id that never gets a parent doc.
 * @param {FirebaseFirestore.DocumentReference} topicRef Topic document ref.
 * @return {Promise<void>} Resolves once cleanup commits (no-op if empty).
 */
async function deleteAiTopicLevelsSubtree(
  topicRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  const levelsSnap = await topicRef.collection("levels").get();
  if (levelsSnap.empty) return;

  const batch = db.batch();

  for (const levelDoc of levelsSnap.docs) {
    const questionsSnap = await levelDoc.ref.collection("questions").get();
    questionsSnap.docs.forEach((q) => batch.delete(q.ref));
    batch.delete(levelDoc.ref);
  }

  await batch.commit();
}

/**
 * Transactional get-or-create for the shared pool entry backing a given
 * title+language. Doesn't generate any content — callers decide whether to
 * generate against the returned ref based on `poolData.status`/
 * `generatedLevels`.
 * @param {string} normalizedTitle Title run through `normalizeTopicTitle`.
 * @param {string} title Original (non-normalized) title.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @param {string} uid Requesting user's uid (audit only, never shown).
 * @return {Promise<Object>} The resolved pool doc ref (`poolRef`), its
 * current data (`poolData`), and whether this call is what created it
 * (`created`).
 */
async function getOrCreatePoolEntry(
  normalizedTitle: string,
  title: string,
  languageCode: unknown,
  uid: string
): Promise<{
  poolRef: FirebaseFirestore.DocumentReference;
  poolData: FirebaseFirestore.DocumentData;
  created: boolean;
}> {
  const poolRef = db.collection("ai_topic_pool")
    .doc(aiTopicPoolId(normalizedTitle, languageCode));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (snap.exists) {
      return {poolRef, poolData: snap.data() || {}, created: false};
    }

    const poolData = {
      title,
      normalizedTitle,
      languageCode: languageCode === "en" ? "en" : "es",
      status: "pending_generation",
      generatedLevels: 0,
      // How deep this topic is meant to go, not how much of it exists yet
      // — that's `generatedLevels`. Seeded with
      // AI_INITIAL_GENERATED_LEVELS (2) it recorded the up-front
      // generation batch instead, so every pool claimed a 2-level target
      // while every topic adopting it targeted ten, and the only thing
      // that ever raised it afterwards was generation catching up.
      targetLevels: AI_LEVELS_PER_TOPIC,
      usageCount: 1,
      createdByUid: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(poolRef, poolData);
    return {poolRef, poolData, created: true};
  });
}

/**
 * Lazily adopts a pre-migration per-user topic into the shared content
 * pool the first time anything touches it after this migration shipped —
 * called at the top of `ensureAiTopicLevelsGenerated`,
 * `regenerateAiTopicQuestions`, and `ensureSoloLevelSession`'s AI branch,
 * before they read/generate content. No-op once `topicData.poolId` is
 * already set — this only ever runs once per legacy topic.
 *
 * If this is the first topic ever seen for its title+language, its own
 * already-generated content becomes the pool's seed content (moved, not
 * copied — the per-user copy is deleted once the pool has it). Otherwise
 * a pool entry already exists (another user's topic adopted first, or was
 * created directly post-migration): this topic's own content is simply
 * redundant and gets deleted, with no economic event either way — no
 * `usageCount` bump (this user generated their own copy originally, not a
 * new discounted reuse) and no charge/refund (pure storage cleanup).
 * @param {string} uid Topic owner's uid.
 * @param {FirebaseFirestore.DocumentReference} topicRef Per-user topic ref.
 * @param {FirebaseFirestore.DocumentData} topicData Topic's current data.
 * @param {unknown} languageCode Topic owner's stored languageCode.
 * @return {Promise<string>} The topic's (now guaranteed-set) poolId.
 */
async function ensureTopicAdoptedIntoPool(
  uid: string,
  topicRef: FirebaseFirestore.DocumentReference,
  topicData: FirebaseFirestore.DocumentData,
  languageCode: unknown
): Promise<string> {
  if (topicData.poolId) {
    return String(topicData.poolId);
  }

  const normalizedTitle = String(
    topicData.normalizedTitle ||
    normalizeTopicTitle(String(topicData.title || ""))
  );
  const title = String(topicData.title || "Custom Topic");
  const ownGeneratedLevels = safeInt(topicData.generatedLevels, 0);
  const ownTargetLevels = safeInt(topicData.targetLevels, AI_LEVELS_PER_TOPIC);

  const {poolRef, poolData, created} = await getOrCreatePoolEntry(
    normalizedTitle, title, languageCode, uid
  );

  if (ownGeneratedLevels > 0) {
    if (created) {
      const levelsSnap = await topicRef.collection("levels").get();
      const batch = db.batch();

      for (const levelDoc of levelsSnap.docs) {
        const questionsSnap = await levelDoc.ref.collection("questions").get();
        const poolLevelRef = poolRef.collection("levels").doc(levelDoc.id);
        batch.set(poolLevelRef, levelDoc.data());
        questionsSnap.docs.forEach((q) => {
          batch.set(poolLevelRef.collection("questions").doc(q.id), q.data());
        });
      }

      batch.set(poolRef, {
        status: "ready",
        generatedLevels: ownGeneratedLevels,
        targetLevels: Math.max(ownTargetLevels, ownGeneratedLevels),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      await batch.commit();
    } else {
      const poolGeneratedLevels = safeInt(poolData.generatedLevels, 0);

      if (ownGeneratedLevels > poolGeneratedLevels) {
        let avoidQuestions = await existingPoolQuestionTexts(poolRef);

        for (
          let level = poolGeneratedLevels + 1;
          level <= ownGeneratedLevels;
          level++
        ) {
          const added = await generateAiTopicLevel(
            uid, poolRef, level, title, languageCode, {avoidQuestions}
          );
          avoidQuestions = [...avoidQuestions, ...added];
        }

        await poolRef.set({
          generatedLevels: ownGeneratedLevels,
          targetLevels: Math.max(
            safeInt(poolData.targetLevels, 0), ownGeneratedLevels
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }

    await deleteAiTopicLevelsSubtree(topicRef);
  }

  await topicRef.set({
    poolId: poolRef.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return poolRef.id;
}

// Tunable knobs for the "search existing topics before creating" flow —
// retune freely once there's real usage data to look at. The similarity
// threshold itself lives next to the scoring function in
// ./ai_topic_similarity so both can be unit-tested together.
const AI_TOPIC_SIMILAR_MATCHES_LIMIT = 5;
// A fixed usage-count floor for the "trending" star, rather than "is this
// in the current top-20 Popular Topics ranking" — the latter would mean
// ranking every candidate against the whole pool per search. Purely a
// discovery signal: every returned match is priced the same regardless.
const AI_TOPIC_POPULAR_USAGE_THRESHOLD = 3;
const AI_TOPIC_SUGGESTION_COUNT = 5;

interface PoolTitleEntry {
  /** ai_topic_pool document id. */
  p: string;
  /** Display title. */
  t: string;
  /** Normalized title, what similarity is scored against. */
  n: string;
  /** Language code the entry belongs to. */
  l: string;
}

// Short by design: the index only drives *discovery*, and a topic missing
// from it is still reused at the discounted price if the player types its
// exact title, because createAiTopic resolves the pool entry by its
// deterministic id rather than through this search.
const AI_TOPIC_TITLE_INDEX_TTL_MS = 60 * 60 * 1000;
const AI_TOPIC_TITLE_INDEX_MAX_ENTRIES = 5000;

/**
 * Titles of every ready pool entry, cached so a similarity search doesn't
 * re-read the whole pool on every attempt to create a topic.
 *
 * Only the fields that don't move are cached. `usageCount` is deliberately
 * excluded: it changes on every reuse and decides the price shown, so
 * callers re-read the few entries they actually surface.
 * @return {Promise<PoolTitleEntry[]>} Cached pool titles.
 */
async function loadPoolTitleIndex(): Promise<PoolTitleEntry[]> {
  const ref = db.collection("caches").doc("ai_topic_title_index");
  const snap = await ref.get();
  const data = snap.data();

  const builtAt = data?.builtAt as admin.firestore.Timestamp | undefined;
  const cached = (data?.entries as PoolTitleEntry[] | undefined) || [];
  const isFresh = builtAt !== undefined &&
    Date.now() - builtAt.toMillis() < AI_TOPIC_TITLE_INDEX_TTL_MS;

  if (isFresh) return cached;

  const poolSnap = await db.collection("ai_topic_pool")
    .where("status", "==", "ready")
    .limit(AI_TOPIC_TITLE_INDEX_MAX_ENTRIES)
    .get();

  const entries: PoolTitleEntry[] = poolSnap.docs.map((doc) => {
    const poolData = doc.data();
    return {
      p: doc.id,
      t: String(poolData.title || ""),
      n: String(poolData.normalizedTitle || ""),
      l: poolData.languageCode === "en" ? "en" : "es",
    };
  });

  await ref.set({
    entries,
    count: entries.length,
    builtAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return entries;
}

/**
 * Rejects the call if the player is already at their active-topic cap.
 * The guided-creation endpoints check this up front so a capped player
 * hears about it immediately, instead of `suggestAiTopicTitles` spending a
 * real Claude call to disambiguate a topic `createAiTopic` would refuse to
 * create anyway. `createAiTopic` keeps its own (transactional) check —
 * this one is a fail-fast courtesy, not the authoritative guard.
 * @param {string} uid Caller's uid.
 * @return {Promise<void>} Resolves if the caller is under the cap.
 */
async function assertAiTopicCapAvailable(uid: string): Promise<void> {
  const activeTopicsSnap = await db.collection("users").doc(uid)
    .collection("ai_topics")
    .where("status", "in", ["pending_generation", "ready", "failed"])
    .limit(MAX_AI_TOPICS_PER_USER)
    .get();

  if (activeTopicsSnap.size >= MAX_AI_TOPICS_PER_USER) {
    throw await localizedErrorFor(
      uid, "resource-exhausted",
      `Puedes tener hasta ${MAX_AI_TOPICS_PER_USER} temas IA. ` +
      "Elimina uno para crear otro.",
      `You can have up to ${MAX_AI_TOPICS_PER_USER} AI topics. ` +
      "Delete one to create another."
    );
  }
}

/**
 * Annotates candidate titles with whether the shared pool already has
 * ready content for them, and what that makes them actually cost. Without
 * this the AI-suggestions picker would quote full price for every option,
 * even though `createAiTopic` silently discounts any title that already
 * exists — so a player could be quoted 600 and charged 300.
 * @param {string[]} titles Candidate titles.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {Promise<Array>} Titles with pool/pricing metadata.
 */
async function describeSuggestedTitles(
  titles: string[],
  languageCode: unknown
): Promise<{
  title: string;
  existsInPool: boolean;
  isPopular: boolean;
  cost: number;
}[]> {
  return Promise.all(titles.map(async (title) => {
    const poolId = aiTopicPoolId(normalizeTopicTitle(title), languageCode);
    const snap = await db.collection("ai_topic_pool").doc(poolId).get();
    const data = snap.data();

    const existsInPool = data?.status === "ready";
    const isPopular = existsInPool &&
      safeInt(data?.usageCount, 0) >= AI_TOPIC_POPULAR_USAGE_THRESHOLD;

    let cost = CREATE_AI_TOPIC_COST;
    if (existsInPool) {
      cost = isPopular ?
        CREATE_AI_TOPIC_FROM_POOL_COST : CREATE_AI_TOPIC_EXISTING_COST;
    }

    return {title, existsInPool, isPopular, cost};
  }));
}

/**
 * Searches the shared pool for existing topics (in the caller's own
 * language) similar to a title they're about to type/submit, so they can
 * reuse one instead of creating a near-duplicate. Read-only, no charge —
 * `createAiTopic` still does the real (transactional) reuse-or-generate
 * decision once the user actually picks a title.
 */
// The same 60 the create screen's text field allows and createAiTopic checks.
const AI_TOPIC_TITLE_MAX_LENGTH = 60;

export const findSimilarAiTopics = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertAiTopicCapAvailable(uid);

  const cleanTitle = String(request.data?.title || "").trim();
  if (cleanTitle.length < 3 || cleanTitle.length > AI_TOPIC_TITLE_MAX_LENGTH) {
    // Too short to search meaningfully, or longer than any title the app
    // lets a player type — this is a search, not a hard submit, so return
    // no matches rather than erroring.
    return {blocked: false, matches: []};
  }

  const normalizedTitle = normalizeTopicTitle(cleanTitle);
  const moderationKey = normalizeForModeration(cleanTitle);

  if (
    matchesBlockedKeyword(moderationKey) ||
    await isTopicPreviouslyBlocked(moderationKey)
  ) {
    return {blocked: true, matches: []};
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const languageCode = userSnap.data()?.languageCode === "en" ? "en" : "es";

  // Equality-only filters, no orderBy — Firestore serves this via
  // automatic indexing, unlike the Popular Topics query (which also
  // orders by usageCount and needed a manual composite index).
  // Scored against the cached title index rather than a fresh sweep of the
  // pool: every player tapping "create" used to read hundreds of pool
  // documents to surface at most five of them.
  const index = await loadPoolTitleIndex();

  const ranked = index
    .filter((entry) => entry.l === languageCode)
    .map((entry) => ({
      entry,
      score: titleSimilarity(normalizedTitle, entry.n),
    }))
    .filter(({score}) => score >= AI_TOPIC_SIMILARITY_THRESHOLD)
    .sort((a, b) => b.score - a.score)
    .slice(0, AI_TOPIC_SIMILAR_MATCHES_LIMIT);

  if (ranked.length === 0) {
    return {blocked: false, matches: []};
  }

  // `usageCount` decides the price shown, and the index is deliberately
  // allowed to go stale — so the handful of entries that made the cut are
  // re-read live. Quoting a cached count would put the dialog back out of
  // step with what createAiTopic actually charges.
  const poolDocs = await db.getAll(...ranked.map(({entry}) =>
    db.collection("ai_topic_pool").doc(entry.p)
  ));

  const matches: {
    poolId: string;
    title: string;
    usageCount: number;
    isPopular: boolean;
    cost: number;
  }[] = [];

  poolDocs.forEach((doc, i) => {
    const data = doc.data();
    // Dropped rather than surfaced from the cache: a pool entry deleted or
    // pulled out of "ready" since the index was built is not reusable.
    if (!doc.exists || data?.status !== "ready") return;

    const usageCount = safeInt(data.usageCount, 0);
    const isPopular = usageCount >= AI_TOPIC_POPULAR_USAGE_THRESHOLD;

    matches.push({
      poolId: doc.id,
      title: String(data.title || ranked[i].entry.t),
      usageCount,
      isPopular,
      cost: isPopular ?
        CREATE_AI_TOPIC_FROM_POOL_COST : CREATE_AI_TOPIC_EXISTING_COST,
    });
  });

  return {blocked: false, matches};
});

/**
 * Asks Claude for a bounded list of well-formed candidate topic titles for
 * a player's raw (possibly misspelled or too-vague) input — used when
 * `findSimilarAiTopics` found nothing close enough to reuse. The player
 * must pick one of these to actually create a topic; this call itself
 * never charges coins and never generates trivia content.
 */
export const suggestAiTopicTitles = onCall({
  secrets: AI_SECRETS,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertAiTopicCapAvailable(uid);

  const cleanTitle = String(request.data?.title || "").trim();
  if (cleanTitle.length < 3) {
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "Escribe un tema más específico.",
      "Write a more specific topic."
    );
  }
  // The meter counts calls, not tokens: an unbounded title made each
  // metered call as large a paid prompt as the caller liked.
  if (cleanTitle.length > AI_TOPIC_TITLE_MAX_LENGTH) {
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "El título es demasiado largo.",
      "The title is too long."
    );
  }

  const moderationKey = normalizeForModeration(cleanTitle);

  if (
    matchesBlockedKeyword(moderationKey) ||
    await isTopicPreviouslyBlocked(moderationKey)
  ) {
    return {blocked: true, suggestions: []};
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const languageCode = userSnap.data()?.languageCode;
  const outputLanguage = pickText(languageCode, "Spanish", "English");

  // Cheaper per call than generating a level, but still a paid Claude
  // request that costs no coins and is reachable by any anonymous account
  // — so it gets its own meter rather than riding free on the level cap
  // (or starving it, which charging it there would do).
  await consumeAiBudget(uid, "suggestions", 1);

  const client = new Anthropic({apiKey: anthropicApiKey.value()});

  const prompt = "A player typed the following trivia topic request, " +
    "which may contain typos or be too vague to generate good trivia " +
    `questions from directly: "${cleanTitle}". Suggest exactly ` +
    `${AI_TOPIC_SUGGESTION_COUNT} distinct, well-formed, specific trivia ` +
    `topic titles (2-6 words each) in ${outputLanguage} that this could ` +
    "reasonably mean. If the input is already clear and well-formed, one " +
    "suggestion should be the cleaned-up version of the same topic. Do " +
    "not repeat the exact same title twice.";

  // No minItems/maxItems on `titles`: structured outputs reject any
  // minItems other than 0 or 1, and the whole request 400s rather than
  // degrading — which is exactly how this call failed in production, with
  // both retries hitting the same deterministic rejection. The count is
  // asked for in the prompt and enforced below, where a short or long list
  // is something we can actually recover from.
  const schema = {
    type: "object",
    properties: {
      titles: {
        type: "array",
        items: {type: "string"},
      },
    },
    required: ["titles"],
    additionalProperties: false,
  };

  let lastError: unknown;

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await client.messages.create({
        model: AI_MODEL,
        max_tokens: 4096,
        system: AI_TOPIC_SYSTEM_PROMPT,
        messages: [{role: "user", content: prompt}],
        output_config: {format: {type: "json_schema", schema}},
      });

      if (response.stop_reason === "refusal") {
        await recordBlockedTopic(cleanTitle, moderationKey, "model_refusal");
        return {blocked: true, suggestions: []};
      }

      // Haiku 5.5 thinks by default, so the text is no longer guaranteed
      // to be the first block — reasoning blocks precede it.
      const block = response.content.find((b) => b.type === "text");
      if (!block) {
        throw new Error("Unexpected response block type from Claude.");
      }

      const parsed = JSON.parse(block.text) as {titles?: string[]};
      const rawTitles = parsed.titles || [];

      const seen = new Set<string>();
      const suggestions: string[] = [];

      for (const raw of rawTitles) {
        // Now that the schema no longer bounds the array, the ceiling is
        // enforced here — a model that returns more than asked would
        // otherwise fill the picker with options the player must read
        // through.
        if (suggestions.length >= AI_TOPIC_SUGGESTION_COUNT) break;

        const title = String(raw || "").trim();
        const normalized = normalizeTopicTitle(title);

        if (
          title.length < 3 || title.length > 60 ||
          RESERVED_TOPIC_NAMES.has(normalized) ||
          seen.has(normalized)
        ) {
          continue;
        }

        seen.add(normalized);
        suggestions.push(title);
      }

      if (suggestions.length === 0) {
        throw new Error("No valid suggestions from Claude.");
      }

      return {
        blocked: false,
        suggestions: await describeSuggestedTitles(suggestions, languageCode),
      };
    } catch (error) {
      lastError = error;
    }
  }

  console.error("AI topic title suggestion failed", lastError);
  throw localizedError(
    languageCode, "internal",
    "No se pudieron sugerir temas. Intenta de nuevo.",
    "Suggestions couldn't be loaded. Please try again."
  );
});

export const createAiTopic = onCall({
  secrets: AI_SECRETS,
  // Generates AI_INITIAL_GENERATED_LEVELS levels at roughly 30s each, so
  // the 60s default sat exactly on the edge of the work it has to do.
  timeoutSeconds: 300,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const cleanTitle = String(request.data?.title || "").trim();

  if (cleanTitle.length < 3) {
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "Escribe un tema más específico.",
      "Write a more specific topic."
    );
  }
  if (cleanTitle.length > 60) {
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "El tema no puede superar 60 caracteres.",
      "The topic can't be longer than 60 characters."
    );
  }

  const normalizedTitle = normalizeTopicTitle(cleanTitle);

  if (RESERVED_TOPIC_NAMES.has(normalizedTitle)) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Ese tema ya existe como categoría oficial.",
      "That topic already exists as an official category."
    );
  }

  const moderationKey = normalizeForModeration(cleanTitle);

  if (matchesBlockedKeyword(moderationKey)) {
    await recordBlockedTopic(cleanTitle, moderationKey, "keyword");
    throw await localizedErrorFor(
      uid, "invalid-argument",
      "No se pudo generar ese tema. Intenta con otro título.",
      "That topic couldn't be generated. Try a different title."
    );
  }

  // No separate isTopicPreviouslyBlocked check here — the generation loop
  // below calls requestAiQuestionsFromClaude for level 1 first, which
  // checks it before making any Claude API call, so a previously-blocked
  // title still fails fast with the same user-facing message, just via
  // topicBlockedHttpsError() in the catch block instead of a duplicate
  // read here.

  const topicsCol = db.collection("users").doc(uid).collection("ai_topics");

  const existing = await topicsCol
    .where("normalizedTitle", "==", normalizedTitle)
    .where("status", "in", ["pending_generation", "ready"])
    .limit(1)
    .get();

  if (!existing.empty) {
    throw await localizedErrorFor(
      uid, "already-exists",
      "Ya tienes un tema con ese nombre.",
      "You already have a topic with that name."
    );
  }

  const activeTopicsSnap = await topicsCol
    .where("status", "in", ["pending_generation", "ready", "failed"])
    .limit(MAX_AI_TOPICS_PER_USER)
    .get();

  if (activeTopicsSnap.size >= MAX_AI_TOPICS_PER_USER) {
    throw await localizedErrorFor(
      uid, "resource-exhausted",
      `Puedes tener hasta ${MAX_AI_TOPICS_PER_USER} temas IA. ` +
      "Elimina uno para crear otro.",
      `You can have up to ${MAX_AI_TOPICS_PER_USER} AI topics. ` +
      "Delete one to create another."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};

  const freePasses = safeInt(
    userData.freeTopicPasses, FIRST_AI_TOPIC_FREE_PASSES
  );
  const usesFreePass = freePasses > 0;

  // Resolve (or create) the shared pool entry for this title+language
  // before deciding whether any Claude call is even needed — see the
  // "Shared AI-topic content pool" plan. `status === "ready"` means
  // someone (this user or another) already generated this exact
  // title+language before, so this create can skip generation entirely
  // and charge the discounted reuse price instead.
  const {poolRef, poolData} = await getOrCreatePoolEntry(
    normalizedTitle, cleanTitle, userData.languageCode, uid
  );
  const reuseFromPool = poolData.status === "ready";
  const reuseIsPopular =
    safeInt(poolData.usageCount, 0) >= AI_TOPIC_POPULAR_USAGE_THRESHOLD;
  const reuseCost = reuseIsPopular ?
    CREATE_AI_TOPIC_FROM_POOL_COST : CREATE_AI_TOPIC_EXISTING_COST;

  const coins = safeInt(userData.coins, 0);
  const cost = usesFreePass ? 0 :
    (reuseFromPool ? reuseCost : CREATE_AI_TOPIC_COST);

  if (!usesFreePass && coins < cost) {
    throw localizedError(
      userData.languageCode, "failed-precondition",
      `Necesitas ${cost} monedas para crear un tema IA.`,
      `You need ${cost} coins to create an AI topic.`
    );
  }

  if (!reuseFromPool) {
    // Deterministic level doc ids (level_1, level_2, ...) make this
    // self-healing: unlike the old per-user flow, a failure here is never
    // cleaned up — the pool doc simply stays `pending_generation` and the
    // next attempt (by this user or anyone else typing the same title)
    // just resumes/overwrites from where it left off. Deleting shared pool
    // content on failure would risk destroying a concurrent attempt's
    // work for a title two users happened to create at the same time.
    const startLevel = safeInt(poolData.generatedLevels, 0) + 1;

    try {
      // Carried across levels: without it each level only avoided its own
      // (empty) bank, so level 2 happily re-issued level 1's questions.
      let avoidQuestions = await existingPoolQuestionTexts(poolRef);

      for (
        let level = startLevel;
        level <= AI_INITIAL_GENERATED_LEVELS;
        level++
      ) {
        const added = await generateAiTopicLevel(
          uid, poolRef, level, cleanTitle, userData.languageCode,
          {avoidQuestions}
        );
        avoidQuestions = [...avoidQuestions, ...added];
      }
    } catch (error) {
      if (error instanceof TopicBlockedError) {
        throw topicBlockedHttpsError(userData.languageCode);
      }
      throw error;
    }
  }

  // Counted before the transaction (a collection read doesn't belong
  // inside one): reusing an existing pool entry can hand the player banks
  // that already grew past ten per level, and the topics list should say
  // so from the start rather than under-reporting until first play.
  const initialBankedQuestions = await countBankedQuestions(
    poolRef, AI_INITIAL_GENERATED_LEVELS
  );

  const topicRef = topicsCol.doc();

  // Charge and create the topic doc atomically, re-reading fresh
  // free-pass/coin balance and topic count at charge time (not the
  // pre-generation snapshot read above) — two concurrent createAiTopic
  // calls (double-submit, or two devices on one account) could otherwise
  // both pass the earlier plain-read checks before either one's charge
  // lands, double-spending a single free pass or slipping both past the
  // topic cap. Mirrors the transactional charge pattern in
  // regenerateAiTopicQuestions/expandAiTopic. This can't prevent the
  // wasted Claude generation calls in a genuine race, only the
  // double-charge/double-free-pass/cap-bypass outcome.
  return db.runTransaction(async (tx) => {
    const freshUserSnap = await tx.get(userRef);
    const freshUserData = freshUserSnap.data() || {};
    const freshCoins = safeInt(freshUserData.coins, 0);
    const freshFreePasses = safeInt(
      freshUserData.freeTopicPasses, FIRST_AI_TOPIC_FREE_PASSES
    );
    const freshUsesFreePass = freshFreePasses > 0;

    const freshPoolSnap = await tx.get(poolRef);
    const freshPoolData = freshPoolSnap.data() || {};
    const freshPoolGeneratedLevels = Math.max(
      safeInt(freshPoolData.generatedLevels, 0), AI_INITIAL_GENERATED_LEVELS
    );
    // Popularity (and so which discount tier applies) is read fresh here
    // too, from the usage count as it stood *before* this creation's own
    // reuse — someone doesn't get the deeper discount for being the reuse
    // that happens to push a topic over the popular threshold themselves.
    const freshReuseIsPopular = safeInt(freshPoolData.usageCount, 0) >=
      AI_TOPIC_POPULAR_USAGE_THRESHOLD;
    const freshReuseCost = freshReuseIsPopular ?
      CREATE_AI_TOPIC_FROM_POOL_COST : CREATE_AI_TOPIC_EXISTING_COST;
    const freshCost = freshUsesFreePass ? 0 :
      (reuseFromPool ? freshReuseCost : CREATE_AI_TOPIC_COST);

    if (!freshUsesFreePass && freshCoins < freshCost) {
      throw localizedError(
        freshUserData.languageCode, "failed-precondition",
        `Necesitas ${freshCost} monedas para crear un tema IA.`,
        `You need ${freshCost} coins to create an AI topic.`
      );
    }

    const freshActiveTopicsSnap = await tx.get(
      topicsCol
        .where("status", "in", ["pending_generation", "ready", "failed"])
        .limit(MAX_AI_TOPICS_PER_USER)
    );

    if (freshActiveTopicsSnap.size >= MAX_AI_TOPICS_PER_USER) {
      throw await localizedErrorFor(
        uid, "resource-exhausted",
        `Puedes tener hasta ${MAX_AI_TOPICS_PER_USER} temas de IA. ` +
        "Borra uno para crear otro.",
        `You can have up to ${MAX_AI_TOPICS_PER_USER} AI topics. ` +
        "Delete one to create another."
      );
    }

    tx.set(topicRef, {
      topicId: topicRef.id,
      title: cleanTitle,
      normalizedTitle,
      status: "ready",
      source: "ai",
      poolId: poolRef.id,
      targetLevels: AI_LEVELS_PER_TOPIC,
      levelCount: AI_LEVELS_PER_TOPIC,
      levelsCount: AI_LEVELS_PER_TOPIC,
      generatedLevels: AI_INITIAL_GENERATED_LEVELS,
      questionsCount: initialBankedQuestions,
      generationMode: "claude_haiku_4_5",
      generationCostCoins: freshCost,
      usedFreePass: freshUsesFreePass,
      reusedFromPool: reuseFromPool,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // A pool's target is the deepest one any adopter holds, so both
    // branches raise it — a topic reusing a pool still targets
    // AI_LEVELS_PER_TOPIC, and the pool used to hear nothing about it.
    tx.set(poolRef, reuseFromPool ? {
      usageCount: admin.firestore.FieldValue.increment(1),
      targetLevels: Math.max(
        safeInt(freshPoolData.targetLevels, 0), AI_LEVELS_PER_TOPIC
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    } : {
      status: "ready",
      generatedLevels: freshPoolGeneratedLevels,
      targetLevels: Math.max(
        safeInt(freshPoolData.targetLevels, 0),
        AI_LEVELS_PER_TOPIC,
        freshPoolGeneratedLevels
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(
      userRef,
      {
        ...(freshUsesFreePass ?
          {freeTopicPasses: admin.firestore.FieldValue.increment(-1)} :
          {coins: admin.firestore.FieldValue.increment(-freshCost)}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {topicId: topicRef.id};
  });
});

export const regenerateAiTopicQuestions = onCall({
  secrets: AI_SECRETS,
  // The heaviest generation path: one batch per expandable level, up to
  // the topic's full depth, at roughly 30s each. At the 60s default it
  // died after the first couple of levels — the partial refund kept the
  // player's coins honest, but the purchase they asked for never landed.
  timeoutSeconds: 540,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw await localizedErrorFor(
      uid, "not-found",
      "Este tema ya no existe.",
      "That topic no longer exists."
    );
  }
  if (topicData.status === "blocked") {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema fue bloqueado y no se puede regenerar. Elimínalo para " +
      "recuperar tu costo.",
      "This topic was blocked and can't be regenerated. Delete it to get " +
      "your coins back."
    );
  }
  if (topicData.status !== "ready") {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "El tema todavía se está preparando.",
      "This topic is still being prepared."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const languageCode = userSnap.data()?.languageCode;

  // This topic's content is shared with every other player who reused it
  // from the pool, so regeneration *adds* to each level's bank instead of
  // rewriting it: nobody mid-topic has the ground moved under them, and
  // the extra questions become replay material for everyone. It also
  // makes the purchase actually do something for the buyer — overwriting
  // left anyone who had already opened a level seeing their old slate,
  // because sessions snapshot their questions.
  const poolId = await ensureTopicAdoptedIntoPool(
    uid, topicRef, topicData, languageCode
  );
  const poolRef = db.collection("ai_topic_pool").doc(poolId);

  const generatedLevels = safeInt(topicData.generatedLevels, 0);
  const title = String(topicData.title || "Custom Topic");

  // Only levels with room left are charged for — a topic whose banks are
  // all at AI_QUESTION_BANK_CAP has nothing left to sell. Shares its
  // arithmetic with getAiTopicRegenerateQuote so the price the player was
  // shown is the price they get charged.
  const bankSizes = await readLevelBankSizes(poolRef, generatedLevels);
  const expandableLevels = expandableLevelsFrom(bankSizes, generatedLevels);

  if (expandableLevels.length === 0) {
    throw localizedError(
      languageCode, "failed-precondition",
      "Este tema ya tiene el máximo de preguntas por nivel.",
      "This topic already has the maximum number of questions per level."
    );
  }

  const cost =
    REGENERATE_AI_QUESTIONS_COST_PER_LEVEL * expandableLevels.length;

  // Charge first (atomically) — generating first and charging after, as
  // this used to, left a window where a concurrent balance change could
  // grant a free regeneration since the already-generated content was
  // durably written regardless of whether the later charge succeeded.
  // Refund below if generation then fails.
  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(userRef);
    const freshCoins = safeInt(freshSnap.data()?.coins, 0);

    if (freshCoins < cost) {
      throw localizedError(
        languageCode, "failed-precondition",
        `Necesitas ${cost} monedas para ampliar las preguntas.`,
        `You need ${cost} coins to add more questions.`
      );
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(-cost),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });

  let paidLevelsDelivered = 0;
  let questionsAdded = 0;

  try {
    let avoidQuestions = await existingPoolQuestionTexts(poolRef);

    for (const level of expandableLevels) {
      // Each level's new questions join the avoid-list, so level N doesn't
      // re-issue what levels 1..N-1 just added — the buyer paid per level
      // for distinct content, not the same batch repeated.
      const added = await generateAiTopicLevel(
        uid, poolRef, level, title, languageCode,
        {count: AI_QUESTIONS_PER_LEVEL, avoidQuestions}
      );

      avoidQuestions = [...avoidQuestions, ...added];
      questionsAdded += added.length;
      paidLevelsDelivered++;
    }
  } catch (error) {
    // Refund only what wasn't delivered. Generated questions are already
    // durable in the shared pool, so refunding the full price after a
    // failure partway through would hand over those levels for free — to
    // this player and to everyone else reusing the same pool entry.
    const refund =
      cost - paidLevelsDelivered * REGENERATE_AI_QUESTIONS_COST_PER_LEVEL;

    if (refund > 0) {
      await userRef.set(
        {
          coins: admin.firestore.FieldValue.increment(refund),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }

    if (error instanceof TopicBlockedError) {
      await topicRef.set(
        {
          status: "blocked",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      throw topicBlockedHttpsError(languageCode);
    }
    throw error;
  }

  // Reflect the bigger banks on the player's own topic doc, so the topics
  // list shows the purchase actually landed instead of the same numbers
  // it showed before paying. Derived from the sizes already read above
  // plus what was just generated — re-reading the whole levels collection
  // here would only restate what we already know.
  const bankedQuestions =
    totalBankedQuestions(bankSizes) + questionsAdded;

  await topicRef.set({
    questionsCount: bankedQuestions,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {success: true, questionsCount: bankedQuestions};
});

/**
 * Prices an "add more questions" purchase without committing to it.
 *
 * The client can't work this out on its own: levels already at
 * AI_QUESTION_BANK_CAP aren't charged for, and bank sizes live on the
 * shared pool rather than the player's topic doc. Quoting
 * `costPerLevel * generatedLevels` client-side overcharged in the dialog
 * and, once every level was full, let the player confirm a purchase that
 * could only fail.
 */
export const getAiTopicRegenerateQuote = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData || topicData.status !== "ready") {
    return {cost: 0, levels: 0, allFull: false, available: false};
  }

  const poolId = topicData.poolId ? String(topicData.poolId) : null;
  const generatedLevels = safeInt(topicData.generatedLevels, 0);

  // A topic that hasn't been adopted into the pool yet still has its
  // content per-user; it gets adopted on the next play. Quote the plain
  // per-level price for it rather than forcing an adoption from a
  // read-only endpoint.
  if (!poolId) {
    return {
      cost: REGENERATE_AI_QUESTIONS_COST_PER_LEVEL * generatedLevels,
      levels: generatedLevels,
      allFull: false,
      available: generatedLevels > 0,
    };
  }

  const expandableLevels = expandableLevelsFrom(
    await readLevelBankSizes(
      db.collection("ai_topic_pool").doc(poolId), generatedLevels
    ),
    generatedLevels
  );

  return {
    cost: REGENERATE_AI_QUESTIONS_COST_PER_LEVEL * expandableLevels.length,
    levels: expandableLevels.length,
    allFull: expandableLevels.length === 0 && generatedLevels > 0,
    available: expandableLevels.length > 0,
  };
});

export const expandAiTopic = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw await localizedErrorFor(
      uid, "not-found",
      "Este tema ya no existe.",
      "That topic no longer exists."
    );
  }
  if (topicData.status === "blocked") {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema fue bloqueado y no se puede ampliar. Elimínalo para " +
      "recuperar tu costo.",
      "This topic was blocked and can't be expanded. Delete it to get " +
      "your coins back."
    );
  }
  if (topicData.status !== "ready") {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "El tema todavía se está preparando.",
      "This topic is still being prepared."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const coins = safeInt(userSnap.data()?.coins, 0);
  const languageCode = userSnap.data()?.languageCode;

  if (coins < EXPAND_AI_TOPIC_COST) {
    throw localizedError(
      languageCode, "failed-precondition",
      `Necesitas ${EXPAND_AI_TOPIC_COST} monedas para ampliar este tema.`,
      `You need ${EXPAND_AI_TOPIC_COST} coins to expand this topic.`
    );
  }

  // Only adopts (no generation) — bumping targetLevels here doesn't
  // itself generate anything; ensureAiTopicLevelsGenerated does that
  // lazily as the player progresses, against the pool once adopted. If
  // the pool already covers the new target (another user expanded it
  // further already), buffering finds nothing left to generate and this
  // expand is still charged the same — paying to raise your own ceiling,
  // not for the generation itself.
  const poolId = await ensureTopicAdoptedIntoPool(
    uid, topicRef, topicData, userSnap.data()?.languageCode
  );
  const poolRef = db.collection("ai_topic_pool").doc(poolId);

  const currentTarget = safeInt(topicData.targetLevels, AI_LEVELS_PER_TOPIC);
  const newTarget = currentTarget + AI_LEVELS_PER_TOPIC;

  return db.runTransaction(async (tx) => {
    const [freshSnap, poolSnap] = await tx.getAll(userRef, poolRef);
    const freshCoins = safeInt(freshSnap.data()?.coins, 0);

    if (freshCoins < EXPAND_AI_TOPIC_COST) {
      throw localizedError(
        languageCode, "failed-precondition",
        `Necesitas ${EXPAND_AI_TOPIC_COST} monedas para ampliar este tema.`,
        `You need ${EXPAND_AI_TOPIC_COST} coins to expand this topic.`
      );
    }

    tx.set(
      topicRef,
      {
        targetLevels: newTarget,
        levelCount: newTarget,
        levelsCount: newTarget,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    // The pool tracks the deepest target any of its adopters holds, and
    // this player just paid to raise theirs past it. Nothing generates as
    // a result — buffering is still bounded by each topic's own target
    // (see ensureAiTopicLevelsGenerated) — but leaving it out is what let
    // a pool sit at a target its adopters had long since passed.
    tx.set(
      poolRef,
      {
        targetLevels: Math.max(
          safeInt(poolSnap.data()?.targetLevels, 0), newTarget
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(-EXPAND_AI_TOPIC_COST),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {newTarget};
  });
});

/**
 * Server-side replacement for the old client-side `ensureAiTopicBuffer` —
 * generates real AI levels ahead of the player as they progress, instead
 * of trusting the client to write mock question content directly. Mirrors
 * ai_topic_service.dart's buffering math (generate up to
 * `completedLevel + AI_GENERATION_BUFFER_LEVELS`, clamped to
 * `targetLevels`) but calls Claude server-side via `generateAiTopicLevel`.
 */
/**
 * Which levels are worth pre-filling after a level is completed: the one
 * just finished (the likeliest replay) plus everything newly unlocked.
 * @param {number} completedLevel Level the player just finished.
 * @param {number} desiredGeneratedLevel Deepest level now unlocked.
 * @return {number[]} Level numbers to top up.
 */
function bankTopUpLevels(
  completedLevel: number,
  desiredGeneratedLevel: number
): number[] {
  const first = Math.max(1, completedLevel);
  const levels: number[] = [];
  for (let level = first; level <= desiredGeneratedLevel; level++) {
    levels.push(level);
  }
  return levels;
}

/**
 * Grows the question banks of [levels] so this player has a full unseen
 * slate waiting for each.
 *
 * This is the "generate ahead of the player" half of the accumulating
 * bank, and the path generation is *supposed* to take: it runs while the
 * player is answering, so the next level is already banked when they get
 * there. `ensureSoloLevelSession` can also generate, but only to self-heal
 * a level whose bank is empty — that path costs the player a wait, so
 * reaching it means this one didn't run in time. A level is topped up only
 * when this player's unseen count has dropped below a slate and the bank
 * is still under [AI_QUESTION_BANK_CAP].
 * @param {object} params Topic, pool and level context.
 * @return {Promise<void>} Resolves once every eligible level is topped up.
 */
async function topUpAiLevelBanks(params: {
  uid: string;
  topicId: string;
  poolRef: FirebaseFirestore.DocumentReference;
  title: string;
  languageCode: unknown;
  levels: number[];
}): Promise<void> {
  const {uid, topicId, poolRef, title, languageCode, levels} = params;
  if (levels.length === 0) return;

  // Gathered once for the whole run: the avoid-list spans the topic, and
  // re-reading it per level would multiply the cost of a top-up. Newly
  // generated questions are appended in memory as we go, so later levels
  // still avoid what earlier ones just added without another pool read.
  let avoidQuestions: string[] | null = null;

  for (const levelNumber of levels) {
    const levelRef = poolRef.collection("levels").doc(`level_${levelNumber}`);
    const [levelSnap, seenSnap] = await db.getAll(
      levelRef,
      db.collection("users").doc(uid)
        .collection("ai_topic_seen").doc(`${topicId}_${levelNumber}`)
    );

    // Deciding whether a level needs topping up only needs its ids, and the
    // level doc already carries them — so measuring a bank costs one read
    // instead of one per banked question, on a loop that runs for every
    // level the player is about to replay. Levels written before
    // `questionIds` existed fall back to listing the collection once.
    let bankedIds = ((levelSnap.data()?.questionIds as unknown[]) || [])
      .map(String);
    if (bankedIds.length === 0) {
      const questionsSnap = await levelRef.collection("questions").get();
      bankedIds = questionsSnap.docs.map((doc) => doc.id);
    }

    if (bankedIds.length === 0) continue;

    const seenIds = new Set(
      ((seenSnap.data()?.questionIds as unknown[]) || []).map(String)
    );
    const unseen = bankedIds.filter((id) => !seenIds.has(id)).length;

    const shortfall = AI_QUESTIONS_PER_SESSION - unseen;
    const room = bankHeadroom(bankedIds.length);
    const toGenerate = Math.min(shortfall, room);

    if (toGenerate <= 0) continue;

    if (avoidQuestions === null) {
      avoidQuestions = await existingPoolQuestionTexts(poolRef);
    }

    const added = await generateAiTopicLevel(
      uid, poolRef, levelNumber, title, languageCode,
      {count: toGenerate, avoidQuestions}
    );

    avoidQuestions = [...avoidQuestions, ...added];
  }
}

export const ensureAiTopicLevelsGenerated = onCall({
  secrets: AI_SECRETS,
  // A real generation measured ~30s per level and this buffers up to
  // AI_GENERATION_BUFFER_LEVELS of them, so the platform's 60s default
  // killed it right as it was finishing — which is why levels kept
  // arriving empty and players hit the slow on-demand path instead.
  // Nothing waits on this call, so a generous ceiling costs nothing.
  timeoutSeconds: 300,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }
  const completedLevel = safeInt(request.data?.completedLevel, 0);

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData || topicData.status !== "ready") {
    return {generatedLevels: safeInt(topicData?.generatedLevels, 0)};
  }

  // `generatedLevels` on the per-user topic doc means "how deep *this
  // user* has unlocked" — it's capped by, but doesn't have to equal,
  // `generatedLevels` on the shared pool doc ("how deep *anyone* has
  // generated"). Unlocking a level the pool already has costs nothing
  // (no Claude call); only unlocking past the pool's current depth
  // actually generates anything, deepening the pool for every future
  // reuser too.
  const userSnap = await db.collection("users").doc(uid).get();
  const languageCode = userSnap.data()?.languageCode;
  const title = String(topicData.title || "Custom Topic");

  const poolId = await ensureTopicAdoptedIntoPool(
    uid, topicRef, topicData, languageCode
  );
  const poolRef = db.collection("ai_topic_pool").doc(poolId);

  const generatedLevels = safeInt(topicData.generatedLevels, 0);
  const targetLevels = safeInt(topicData.targetLevels, AI_LEVELS_PER_TOPIC);
  const desiredGeneratedLevel = Math.max(0, Math.min(
    completedLevel + AI_GENERATION_BUFFER_LEVELS, targetLevels
  ));

  if (generatedLevels >= desiredGeneratedLevel) {
    return {generatedLevels};
  }

  const poolSnap = await poolRef.get();
  const poolGeneratedLevels = safeInt(poolSnap.data()?.generatedLevels, 0);
  const poolTargetLevels = safeInt(poolSnap.data()?.targetLevels, 0);

  let lastSuccessfulUserLevel = generatedLevels;
  let lastSuccessfulPoolLevel = poolGeneratedLevels;

  // Buffering generates the levels a player is about to reach, so without
  // a pool-wide avoid list each new level only dodged its own empty bank
  // and freely repeated questions from the levels already played.
  let avoidQuestions: string[] | null = null;

  try {
    for (
      let level = generatedLevels + 1;
      level <= desiredGeneratedLevel;
      level++
    ) {
      if (level > lastSuccessfulPoolLevel) {
        if (avoidQuestions === null) {
          avoidQuestions = await existingPoolQuestionTexts(poolRef);
        }

        const added = await generateAiTopicLevel(
          uid, poolRef, level, title, languageCode, {avoidQuestions}
        );

        avoidQuestions = [...avoidQuestions, ...added];
        lastSuccessfulPoolLevel = level;
      }
      lastSuccessfulUserLevel = level;
    }
  } catch (error) {
    // Persist whatever succeeded before the failure so `generatedLevels`
    // never understates what's actually in Firestore. This call is
    // best-effort from the client (errors are swallowed as "buffering
    // will retry next time" — see ensureAiTopicBuffer), so for a blocked
    // topic the `status: "blocked"` write below — not the thrown error —
    // is what actually reaches the player, via the reactive topics list.
    await topicRef.set({
      generatedLevels: lastSuccessfulUserLevel,
      questionsCount: await countBankedQuestions(
        poolRef, lastSuccessfulUserLevel
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(error instanceof TopicBlockedError ? {status: "blocked"} : {}),
    }, {merge: true});

    if (lastSuccessfulPoolLevel > poolGeneratedLevels) {
      await poolRef.set({
        generatedLevels: lastSuccessfulPoolLevel,
        targetLevels: Math.max(poolTargetLevels, lastSuccessfulPoolLevel),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    if (error instanceof TopicBlockedError) {
      throw topicBlockedHttpsError(languageCode);
    }
    throw error;
  }

  await topicRef.set({
    generatedLevels: desiredGeneratedLevel,
    questionsCount: await countBankedQuestions(
      poolRef, desiredGeneratedLevel
    ),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  if (lastSuccessfulPoolLevel > poolGeneratedLevels) {
    await poolRef.set({
      generatedLevels: lastSuccessfulPoolLevel,
      targetLevels: Math.max(poolTargetLevels, lastSuccessfulPoolLevel),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  // Top up the banks the player is about to replay, so
  // ensureSoloLevelSession always has an unseen slate ready and never has
  // to make them wait on a Claude call at level start. Best-effort: a
  // failure here just means the next replay may reuse a question, which
  // is a far better outcome than blocking the buffering call the client
  // already treats as fire-and-forget.
  try {
    await topUpAiLevelBanks({
      uid, topicId, poolRef, title, languageCode,
      levels: bankTopUpLevels(completedLevel, desiredGeneratedLevel),
    });
  } catch (error) {
    console.error("AI question bank top-up failed", error);
  }

  return {generatedLevels: desiredGeneratedLevel};
});

/**
 * Refunds the coins/free pass spent creating a topic that never became
 * (or stopped being) usable — called by `deleteAiTopic` for any topic
 * whose `status` isn't `"ready"` (including `"blocked"`, set by
 * `ensureAiTopicLevelsGenerated`/`regenerateAiTopicQuestions` when a
 * later level gets refused). Also the safety net for topics stuck
 * `failed`/`invalid` from the old client-side flow, before this
 * migration. Mirrors ai_topic_service.dart's `refundAiTopicCostIfNeeded`
 * exactly, including the `costRefunded` guard against a double refund on
 * repeated retries, plus a `status === "ready"` guard so a topic that
 * actually generated fine can't be refunded — only Cloud Functions may
 * write `status`, so that check is authoritative.
 */
// "blocked": a later level was refused after the topic was paid for.
// "failed"/"invalid": left over from the old client-side generation flow.
const REFUNDABLE_AI_TOPIC_STATUSES = new Set(["blocked", "failed", "invalid"]);

export const refundAiTopicCost = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const topicSnap = await tx.get(topicRef);
    const topicData = topicSnap.data();

    // Only the statuses the server itself sets when a paid topic stops
    // working. `"deleted"` is the one status a client may write, and the
    // guard used to be "anything but ready": marking a topic that worked
    // fine as deleted, then calling this, refunded a topic already played.
    if (
      !topicData ||
      topicData.costRefunded === true ||
      !REFUNDABLE_AI_TOPIC_STATUSES.has(String(topicData.status))
    ) {
      return {refunded: false};
    }

    const usedFreePass = topicData.usedFreePass === true;
    const cost = safeInt(topicData.generationCostCoins, 0);

    if (!usedFreePass && cost <= 0) {
      return {refunded: false};
    }

    tx.set(
      userRef,
      {
        ...(usedFreePass ?
          {freeTopicPasses: admin.firestore.FieldValue.increment(1)} : {}),
        ...(!usedFreePass && cost > 0 ?
          {coins: admin.firestore.FieldValue.increment(cost)} : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(topicRef, {costRefunded: true}, {merge: true});

    return {refunded: true};
  });
});

// A question hitting this many reports (from replays of the same level, or
// any future case where reports on the same questionId accumulate) gets
// excluded from that level's question pool going forward — see
// reportAiQuestion below.
const AI_QUESTION_REPORT_THRESHOLD = 3;

/**
 * Logs a player's report of a bad AI-generated question (wrong answer
 * marked correct, confusing, inappropriate, etc.) to a global collection
 * for reviewing AI-generation quality, and — once the same questionId
 * within a level has been reported [AI_QUESTION_REPORT_THRESHOLD] times —
 * invalidates that level's cached session so the next play rebuilds the
 * question set excluding it (see level_play_screen.dart's _ensureSession,
 * which already filters by this same reportedQuestionCounts field).
 */
export const reportAiQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = cleanDocId(request.data?.topicId);
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  const questionId = cleanDocId(request.data?.questionId);
  const questionText = String(request.data?.questionText || "").slice(0, 500);
  const reason = String(request.data?.reason || "");
  const details = String(request.data?.details || "").slice(0, 500);

  if (
    !topicId || levelNumber < 1 || !questionId ||
    !QUESTION_REPORT_REASONS.has(reason)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report.");
  }

  return recordAiQuestionReport(uid, {
    topicId, levelNumber, questionId, questionText, reason, details,
  });
});

/**
 * The body of [reportAiQuestion], shared with [reportQuestion]'s AI mode.
 * @param {string} uid Reporter.
 * @param {object} report The validated report.
 * @return {Promise<object>} The question's report count and whether it is
 *     now excluded from its level.
 */
async function recordAiQuestionReport(uid: string, report: {
  topicId: string; levelNumber: number; questionId: string;
  questionText: string; reason: string; details: string;
}): Promise<{reportCount: number; excluded: boolean;
  alreadyReported: boolean}> {
  const {
    topicId, levelNumber, questionId, questionText, reason, details,
  } = report;
  const userRef = db.collection("users").doc(uid);
  const topicRef = userRef.collection("ai_topics").doc(topicId);
  const sessionRef = userRef.collection("sessions_ai")
    .doc(`${topicId}_${levelNumber}`);

  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();
  if (!topicData) {
    throw new HttpsError("not-found", "Topic not found.");
  }

  // reportedQuestionCounts lives on the shared pool's level doc (not the
  // per-user topic's, which no longer holds content once adopted) —
  // ensureSoloLevelSession has always already adopted this topic by the
  // time a report can happen (you can't report a question you haven't
  // played), so this is a no-op read in the common case.
  const ownerSnap = await userRef.get();
  const poolId = await ensureTopicAdoptedIntoPool(
    uid, topicRef, topicData, ownerSnap.data()?.languageCode
  );
  const levelRef = db.collection("ai_topic_pool").doc(poolId)
    .collection("levels").doc(`level_${levelNumber}`);

  // Deterministic id keyed on (reporter, pool level, question) so one
  // player can only ever contribute a single report to a given question's
  // count. The count lives on the *shared* pool level doc and crossing
  // AI_QUESTION_REPORT_THRESHOLD hides the question for everyone who
  // reuses that topic — with an auto-id per report, one user calling this
  // callable three times could bury any question in the shared pool.
  // Keyed by poolId rather than topicId because the count is pool-scoped:
  // deleting and re-creating the same topic yields a new topicId but the
  // same pool entry, and that shouldn't buy a second vote.
  const reportRef = db.collection("ai_question_reports")
    .doc(`${uid}__${poolId}__${levelNumber}__${questionId}`);

  const quotaRef = db.collection("question_report_quotas").doc(uid);

  return db.runTransaction(async (tx) => {
    const [levelSnap, existingReportSnap, quotaSnap] = await Promise.all([
      tx.get(levelRef),
      tx.get(reportRef),
      tx.get(quotaRef),
    ]);

    // Only a question that is really in this level: the count lives on the
    // shared level doc, and made-up ids grew it until no write to that
    // level could succeed for anyone.
    const levelQuestionIds = (levelSnap.data()?.questionIds as unknown[]) || [];
    if (!levelQuestionIds.map(String).includes(questionId)) {
      throw new HttpsError("not-found", "Question not found.");
    }

    const reportedCounts: Record<string, number> = {
      ...(levelSnap.data()?.reportedQuestionCounts || {}),
    };
    const currentCount = safeInt(reportedCounts[questionId], 0);

    // Already reported by this user: refresh the report's own details
    // (they may have picked a different reason on the second pass) but
    // leave the shared count untouched.
    if (existingReportSnap.exists) {
      tx.set(
        reportRef,
        {
          reason,
          // An empty comment keeps the earlier one rather than erasing it.
          ...(details ? {details} : {}),
          questionText,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      return {
        reportCount: currentCount,
        excluded: currentCount >= AI_QUESTION_REPORT_THRESHOLD,
        alreadyReported: true,
      };
    }

    // Same daily allowance as fixed-bank reports (reportQuestion).
    const quota = reportQuotaAfter(
      quotaSnap.data(), serverDateId(), MAX_QUESTION_REPORTS_PER_DAY
    );
    if (!quota.allowed) {
      throw await localizedErrorFor(
        uid, "resource-exhausted",
        "Ya enviaste muchos reportes hoy. Gracias; puedes seguir mañana.",
        "You've sent a lot of reports today. Thanks — you can send more " +
          "tomorrow."
      );
    }
    tx.set(quotaRef, quota.next);

    const newCount = currentCount + 1;
    reportedCounts[questionId] = newCount;

    tx.set(reportRef, {
      uid,
      poolId,
      topicId,
      levelNumber,
      questionId,
      questionText,
      reason,
      details,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(
      levelRef,
      {reportedQuestionCounts: reportedCounts},
      {merge: true}
    );

    const excluded = newCount >= AI_QUESTION_REPORT_THRESHOLD;
    if (excluded) {
      tx.delete(sessionRef);
    }

    return {reportCount: newCount, excluded, alreadyReported: false};
  });
}

/**
 * Files a player's report of a bad question from the end-of-level review.
 *
 * The question is read from where the server put it — the player's own
 * Solo session or Daily Challenge doc, or the pool itself for a Weekly
 * Topic round — never taken from the client, so a report always names a
 * real question and says what it read. Fixed-bank reports are only
 * collected, for tools/export_question_reports.js to put in front of a
 * person; unlike AI questions, nothing is hidden automatically, since one
 * player could otherwise bury any question in the shared bank. AI-topic
 * questions go through the same path as [reportAiQuestion].
 */
export const reportQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const data = request.data || {};
  const mode = String(data.mode || "");
  const reason = String(data.reason || "");
  const details = cleanReportDetails(data.details);

  if (!QUESTION_REPORT_REASONS.has(reason)) {
    throw new HttpsError("invalid-argument", "Invalid report.");
  }

  if (mode === "ai") {
    const topicId = cleanDocId(data.topicId);
    const levelNumber = safeInt(data.levelNumber, -1);
    const questionId = cleanDocId(data.questionId);
    if (!topicId || levelNumber < 1 || !questionId) {
      throw new HttpsError("invalid-argument", "Invalid report.");
    }
    return recordAiQuestionReport(uid, {
      topicId, levelNumber, questionId, reason, details,
      questionText: String(data.questionText || "").slice(0, 500),
    });
  }

  const userRef = db.collection("users").doc(uid);
  let question: ReportedQuestion | null = null;
  let categoryId = "";
  let difficulty = 0;
  let docId = "";

  if (mode === "solo") {
    categoryId = cleanDocId(data.categoryId);
    const levelNumber = safeInt(data.levelNumber, -1);
    if (!categoryId || levelNumber < 1) {
      throw new HttpsError("invalid-argument", "Invalid report.");
    }
    const snap = await userRef.collection("sessions_fixed")
      .doc(`${categoryId}_${levelNumber}`).get();
    question = questionAt(
      snap.exists ? await keyedQuestions(snap.ref, snap.data() || {}) : [],
      safeInt(data.questionIndex, -1)
    );
    difficulty = safeInt(snap.data()?.difficulty, 0);
  } else if (mode === "daily") {
    const dateId = String(data.dateId || "");
    await assertPlausibleDateId(uid, dateId);
    const snap = await userRef.collection("daily_challenges")
      .doc(dateId).get();
    question = questionAt(
      snap.exists ? await keyedQuestions(snap.ref, snap.data() || {}) : [],
      safeInt(data.questionIndex, -1)
    );
    categoryId = String(question?.raw.sourceCategoryId || "");
    difficulty = safeInt(question?.raw.sourceDifficulty, 0);
    docId = String(question?.raw.sourceQuestionId || "");
  } else if (mode === "weekly") {
    categoryId = cleanDocId(data.categoryId);
    difficulty = safeInt(data.difficulty, 0);
    docId = cleanDocId(data.questionId);
    if (!categoryId || difficulty < 1 || !docId) {
      throw new HttpsError("invalid-argument", "Invalid report.");
    }
    const snap = await fixedPoolQuestions(categoryId, difficulty)
      .doc(docId).get();
    question = questionAt([snap.data()], 0);
  } else {
    throw new HttpsError("invalid-argument", "Invalid report.");
  }

  if (!question || !categoryId || difficulty < 1) {
    throw new HttpsError("not-found", "Question not found.");
  }

  // Solo sessions keep each question's content but not its id in the
  // pool; its text finds it. One edited since then is still reported, by
  // what the player saw, just without a doc to point at.
  if (!docId) {
    const match = await fixedPoolQuestions(categoryId, difficulty)
      .where("q", "==", question.q).limit(1).get();
    docId = match.empty ? "" : match.docs[0].id;
  }

  const reportRef = db.collection("question_reports").doc(fixedReportDocId(
    uid, categoryId, difficulty, docId || `text_${fnv1a32(question.q)}`
  ));
  const quotaRef = db.collection("question_report_quotas").doc(uid);
  const reported = question;

  const alreadyReported = await db.runTransaction(async (tx) => {
    const [existing, quotaSnap] = await Promise.all([
      tx.get(reportRef),
      tx.get(quotaRef),
    ]);

    // A second report on the same question updates the first: the player
    // may have picked a better reason, and it costs no allowance.
    if (existing.exists) {
      tx.set(reportRef, {
        reason,
        // An empty comment keeps the earlier one rather than erasing it.
        ...(details ? {details} : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return true;
    }

    const quota = reportQuotaAfter(
      quotaSnap.data(), serverDateId(), MAX_QUESTION_REPORTS_PER_DAY
    );
    if (!quota.allowed) {
      throw await localizedErrorFor(
        uid, "resource-exhausted",
        "Ya enviaste muchos reportes hoy. Gracias; puedes seguir mañana.",
        "You've sent a lot of reports today. Thanks — you can send more " +
          "tomorrow."
      );
    }

    tx.set(quotaRef, quota.next);
    tx.set(reportRef, {
      uid,
      mode,
      reason,
      details,
      status: "open",
      categoryId,
      difficulty,
      docId: docId || null,
      question: {
        q: reported.q,
        options: reported.options,
        answerIndex: reported.answerIndex,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return false;
  });

  return {alreadyReported};
});

/**
 * A fixed pool's questions for one category and difficulty.
 * @param {string} categoryId Pool category.
 * @param {number} difficulty Pool difficulty.
 * @return {FirebaseFirestore.CollectionReference} The questions.
 */
function fixedPoolQuestions(categoryId: string, difficulty: number) {
  return db.collection("fixed_pools").doc(categoryId)
    .collection(`difficulty_${difficulty}`).doc("pool")
    .collection("questions");
}

// ============================================================
// WEEKLY TOPIC
//
// `users/{uid}/weekly_participation/{weekId}` is now fully
// Cloud-Function-only (write:false) since submitDailyChallengeResult also
// writes there for weekly-league scoring — so weekly-topic progress and
// reward claims move here too, even though only the reward-claim half
// actually touches `coins`.
// ============================================================

// Mirrors lib/features/home/home_screen.dart's Weekly Topic card and the
// 9 fixed_categories seeded by tools/seed_categories.js — rotating through
// real, already-seeded question pools instead of authoring separate
// weekly-only content. Each entry's rewardAvatarId matches an AvatarInfo in
// lib/services/avatar_service.dart's weeklyAvatars list.
const WEEKLY_TOPIC_CATEGORIES: {
  categoryId: string;
  titleEs: string;
  titleEn: string;
  descriptionEs: string;
  descriptionEn: string;
  rewardAvatarId: string;
}[] = [
  {
    categoryId: "cine",
    titleEs: "Semana del cine", titleEn: "Movie Week",
    descriptionEs: "Completa niveles de cine y gana recompensas.",
    descriptionEn: "Complete cinema levels and earn rewards.",
    rewardAvatarId: "weekly_cine",
  },
  {
    categoryId: "historia",
    titleEs: "Semana de la historia", titleEn: "History Week",
    descriptionEs: "Completa niveles de historia y gana recompensas.",
    descriptionEn: "Complete history levels and earn rewards.",
    rewardAvatarId: "weekly_history",
  },
  {
    categoryId: "ciencia",
    titleEs: "Semana de la ciencia", titleEn: "Science Week",
    descriptionEs: "Completa niveles de ciencia y gana recompensas.",
    descriptionEn: "Complete science levels and earn rewards.",
    rewardAvatarId: "weekly_science",
  },
  {
    categoryId: "musica",
    titleEs: "Semana de la música", titleEn: "Music Week",
    descriptionEs: "Completa niveles de música y gana recompensas.",
    descriptionEn: "Complete music levels and earn rewards.",
    rewardAvatarId: "weekly_music",
  },
  {
    categoryId: "arte",
    titleEs: "Semana del arte", titleEn: "Art Week",
    descriptionEs: "Completa niveles de arte y gana recompensas.",
    descriptionEn: "Complete art levels and earn rewards.",
    rewardAvatarId: "weekly_art",
  },
  {
    categoryId: "geografia",
    titleEs: "Semana de la geografía", titleEn: "Geography Week",
    descriptionEs: "Completa niveles de geografía y gana recompensas.",
    descriptionEn: "Complete geography levels and earn rewards.",
    rewardAvatarId: "weekly_geography",
  },
  {
    categoryId: "deportes",
    titleEs: "Semana del deporte", titleEn: "Sports Week",
    descriptionEs: "Completa niveles de deportes y gana recompensas.",
    descriptionEn: "Complete sports levels and earn rewards.",
    rewardAvatarId: "weekly_sports",
  },
  {
    categoryId: "videojuegos",
    titleEs: "Semana de los videojuegos", titleEn: "Gaming Week",
    descriptionEs: "Completa niveles de videojuegos y gana recompensas.",
    descriptionEn: "Complete video game levels and earn rewards.",
    rewardAvatarId: "weekly_videogames",
  },
  {
    categoryId: "libros",
    titleEs: "Semana de los libros", titleEn: "Books Week",
    descriptionEs: "Completa niveles de libros y gana recompensas.",
    descriptionEn: "Complete book levels and earn rewards.",
    rewardAvatarId: "weekly_books",
  },
];

const WEEKLY_TOPIC_REWARD_COINS = 10;

// Weekly Topic used to just reuse Solo's own fixed levels 1-10 for the
// chosen category — meaning a repeat occurrence of the same category
// (every 9 weeks) showed the exact same 10 question sets a player had
// already seen in Solo. These constants back a decoupled flow instead:
// rounds draw a fresh random sample from the category's difficulty pools
// (mirrors Daily Challenge's own sourcing), and progress is measured in
// correct answers rather than levels completed.
const WEEKLY_TOPIC_ROUND_SIZE = 10;
const WEEKLY_TOPIC_COIN_THRESHOLD = 25;
const WEEKLY_TOPIC_COMPLETION_THRESHOLD = 50;

/**
 * Deterministic weekly rotation index — a pure function of the week's
 * Monday date, so no extra "which week did we last rotate" bookkeeping is
 * needed and re-running this function mid-week is a safe no-op.
 * @param {string} weekId Monday-of-week date string (YYYY-MM-DD).
 * @param {number} categoryCount Number of rotation slots.
 * @return {number} Index into WEEKLY_TOPIC_CATEGORIES for this week.
 */
function weeklyTopicCategoryIndex(
  weekId: string,
  categoryCount: number
): number {
  const monday = new Date(`${weekId}T00:00:00Z`);
  const epoch = new Date("2024-01-01T00:00:00Z");
  const diffWeeks = Math.floor(
    (monday.getTime() - epoch.getTime()) / (7 * 24 * 60 * 60 * 1000)
  );
  return ((diffWeeks % categoryCount) + categoryCount) % categoryCount;
}

/**
 * Rotates weekly_topics/current to the next category every Monday, so the
 * Weekly Topic card never goes stale waiting on a manual update — see the
 * dead-end audit that flagged this doc as having no automated writer
 * before this function existed.
 */
export const rotateWeeklyTopic = onSchedule(
  {schedule: "0 0 * * 1", timeZone: "America/Lima"},
  async () => {
    const weekId = currentWeekId();
    const topicRef = db.collection("weekly_topics").doc("current");
    const snap = await topicRef.get();

    if (snap.data()?.weekId === weekId) return;

    const idx = weeklyTopicCategoryIndex(
      weekId, WEEKLY_TOPIC_CATEGORIES.length
    );
    const chosen = WEEKLY_TOPIC_CATEGORIES[idx];

    await topicRef.set({
      active: true,
      weekId,
      // `title` stays for app versions that only read that field.
      title: chosen.titleEn,
      title_es: chosen.titleEs,
      title_en: chosen.titleEn,
      description_es: chosen.descriptionEs,
      description_en: chosen.descriptionEn,
      categoryId: chosen.categoryId,
      rewardCoins: WEEKLY_TOPIC_REWARD_COINS,
      rewardAvatarId: chosen.rewardAvatarId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

/**
 * Draws one Weekly Topic round for the caller.
 *
 * The client used to draw it itself, which meant reading every question
 * of the category — answers included — on each round: 300 reads per
 * round, and the reason the fixed bank had to be readable at all. Now the
 * bank is closed (firestore.rules) and only the round's own questions
 * leave the server. Questions this player already got this week go to the
 * back, as the client did (see selectDailyEntries).
 */
export const drawWeeklyTopicRound = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = cleanDocId(request.data?.weekId);
  const categoryId = cleanDocId(request.data?.categoryId);
  if (!weekId || !categoryId) {
    throw new HttpsError("invalid-argument", "Invalid round request.");
  }

  const [topicSnap, participationSnap] = await Promise.all([
    db.collection("weekly_topics").doc("current").get(),
    db.collection("users").doc(uid)
      .collection("weekly_participation").doc(weekId).get(),
  ]);
  const topicData = topicSnap.data();
  if (
    !topicData || String(topicData.weekId || "") !== weekId ||
    String(topicData.categoryId || "") !== categoryId
  ) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema de la semana ya terminó.",
      "This weekly topic has ended."
    );
  }

  const used = new Set<string>(
    ((participationSnap.data()?.usedQuestionIds as unknown[]) || [])
      .map((id) => String(id))
  );

  // The daily index already lists every question's location; only a
  // category it doesn't fully cover needs the pool listed.
  const index = await loadDailyQuestionIndex()
    .catch(() => ({entries: [], completeCategories: []} as DailyQuestionIndex));
  let entries: DailyPoolEntry[];
  if (index.completeCategories.includes(categoryId)) {
    entries = index.entries.filter((entry) => entry.c === categoryId);
  } else {
    entries = [];
    for (const d of [1, 2, 3]) {
      const snap = await fixedPoolQuestions(categoryId, d).select().get();
      snap.forEach((doc) => entries.push({c: categoryId, d, q: doc.id}));
    }
  }

  if (entries.length === 0) {
    throw new HttpsError("failed-precondition", "No questions available.");
  }

  const order = seededShuffleIndices(
    entries.length, crypto.randomBytes(4).readUInt32LE(0)
  );
  const picked = selectDailyEntries(
    order.map((i) => entries[i]), used, WEEKLY_TOPIC_ROUND_SIZE
  );

  const docs = await db.getAll(...picked.map((entry) =>
    fixedPoolQuestions(entry.c, entry.d).doc(entry.q)
  ));

  const questions: Record<string, unknown>[] = [];
  docs.forEach((doc, i) => {
    if (!doc.exists) return;
    questions.push({
      ...doc.data(),
      sourceDifficulty: picked[i].d,
      sourceQuestionId: picked[i].q,
    });
  });

  if (questions.length === 0) {
    throw new HttpsError("failed-precondition", "No questions available.");
  }

  // The round is kept here, with its answers in `secret/answers`: the app
  // gets the questions without them and learns each verdict from
  // answerWeeklyQuestion. Drawing pays the entry, as opening a Solo level
  // does on its first answer.
  const userRef = db.collection("users").doc(uid);
  const roundRef = weeklyRoundRef(uid);
  const split = splitAnswerKey(questions);

  const lives = await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const userData = userSnap.data() || {};
    const nowMs = Date.now();
    const state = computeLifeState(userData, nowMs);
    const charge = answerCharge({
      chargeEntry: true,
      lifeUnits: state.lifeUnits,
      entryCost: LEVEL_ENTRY_COST_UNITS,
      wrongCost: WRONG_ANSWER_COST_UNITS,
      gamesPlayed: safeInt(userData.gamesPlayed, 0),
      graceLevels: NEW_PLAYER_GRACE_LEVELS,
      correct: true,
    });
    if (charge.refused) throw noLivesError(userData.languageCode);

    const after = writeLifeUnits(tx, userRef, state, charge.newUnits, nowMs);
    tx.set(answerKeyRef(roundRef), {answerIndices: split.answerIndices});
    tx.set(roundRef, {
      weekId,
      categoryId,
      questions: split.publicQuestions,
      answers: {},
      results: {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return lifeStateResponse(after);
  });

  return {questions: split.publicQuestions, ...lives};
});

/**
 * The player's Weekly Topic round in progress. Server-only: no rule
 * matches it, so the app can't read its answers or write its own.
 * @param {string} uid The player.
 * @return {FirebaseFirestore.DocumentReference} The round doc.
 */
function weeklyRoundRef(uid: string): FirebaseFirestore.DocumentReference {
  return db.collection("users").doc(uid)
    .collection("weekly_rounds").doc("current");
}

/**
 * Stores a new life balance, starting the regen clock if it just left
 * full.
 * @param {FirebaseFirestore.Transaction} tx The transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef The player.
 * @param {LifeState} state The balance before.
 * @param {number} newUnits The balance after.
 * @param {number} nowMs Now.
 * @return {LifeState} The state after the change.
 */
function writeLifeUnits(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  state: LifeState,
  newUnits: number,
  nowMs: number
): LifeState {
  if (newUnits === state.lifeUnits) return state;
  const wasFull = state.lifeUnits >= state.maxLifeUnits;
  const newTickMs = (wasFull && newUnits < state.maxLifeUnits) ?
    nowMs : state.lastTickMs;
  tx.set(userRef, {
    lifeUnits: newUnits,
    maxLifeUnits: state.maxLifeUnits,
    lifeRegenSeconds: state.lifeRegenSeconds,
    lastLifeTickAt: admin.firestore.Timestamp.fromMillis(newTickMs),
  }, {merge: true});
  return stateAfterSpend(state, newUnits, newTickMs);
}

/**
 * Judges one Weekly Topic answer, banks it and charges a wrong one, like
 * answerSoloQuestion does for a level.
 */
export const answerWeeklyQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const questionIndex = safeInt(request.data?.questionIndex, -1);
  const selectedIndex = safeInt(
    request.data?.selectedIndex, TIMED_OUT_ANSWER
  );
  if (questionIndex < 0) {
    throw new HttpsError("invalid-argument", "Invalid answer.");
  }

  const userRef = db.collection("users").doc(uid);
  const roundRef = weeklyRoundRef(uid);

  return db.runTransaction(async (tx) => {
    const [roundSnap, userSnap] = await tx.getAll(roundRef, userRef);
    const round = roundSnap.data();
    if (!round) {
      throw new HttpsError("failed-precondition", "No open round.");
    }
    const keyed = await keyedQuestions(roundRef, round, tx);
    if (questionIndex >= keyed.length) {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }
    const correctIndex = safeInt(keyed[questionIndex]?.answerIndex, -1);
    const userData = userSnap.data() || {};
    const nowMs = Date.now();
    const state = computeLifeState(userData, nowMs);

    const banked = (round.answers && typeof round.answers === "object") ?
      round.answers as Record<string, unknown> : {};
    const key = String(questionIndex);
    if (Object.prototype.hasOwnProperty.call(banked, key)) {
      const stored = safeInt(banked[key], TIMED_OUT_ANSWER);
      return {
        correct: stored === correctIndex, correctIndex, lifeLost: false,
        ...lifeStateResponse(state),
      };
    }

    const correct = selectedIndex === correctIndex;
    const charge = answerCharge({
      chargeEntry: false,
      lifeUnits: state.lifeUnits,
      entryCost: LEVEL_ENTRY_COST_UNITS,
      wrongCost: WRONG_ANSWER_COST_UNITS,
      gamesPlayed: safeInt(userData.gamesPlayed, 0),
      graceLevels: NEW_PLAYER_GRACE_LEVELS,
      correct,
    });
    if (charge.refused) throw noLivesError(userData.languageCode);

    tx.set(roundRef, {
      answers: {[key]: selectedIndex},
      results: {[key]: {correct, correctIndex}},
    }, {merge: true});
    const after = writeLifeUnits(tx, userRef, state, charge.newUnits, nowMs);

    return {
      correct, correctIndex, lifeLost: charge.lifeLost,
      ...lifeStateResponse(after),
    };
  });
});

/**
 * Server-authoritative Weekly Topic round grant. Draws for the round come
 * from the client (see WeeklyTopicService.loadRandomRound), each tagged
 * with its own difficulty/questionId — this refetches each one directly
 * from fixed_pools and compares against its stored answerIndex, so a
 * modified client reporting an inflated correct count can't affect the
 * real result, exactly like submitDailyChallengeResult/
 * submitSoloLevelResult.
 */
export const submitWeeklyTopicRound = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = cleanDocId(request.data?.weekId);
  const categoryId = cleanDocId(request.data?.categoryId);
  if (!weekId || !categoryId) {
    throw new HttpsError("invalid-argument", "Invalid round submission.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();
  if (
    !topicData || String(topicData.weekId || "") !== weekId ||
    String(topicData.categoryId || "") !== categoryId
  ) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema de la semana ya terminó.",
      "This weekly topic has ended."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);

  const roundRef = weeklyRoundRef(uid);

  return db.runTransaction(async (tx) => {
    const [snap, roundSnap] = await tx.getAll(participationRef, roundRef);
    const data = snap.data() || {};

    // Scored from the round the server drew and judged, not from a list
    // of answers the client sends.
    const roundData = roundSnap.data();
    if (!roundData || roundData.weekId !== weekId ||
        roundData.categoryId !== categoryId) {
      throw new HttpsError("failed-precondition", "No open round.");
    }
    const roundQuestions = Array.isArray(roundData.questions) ?
      roundData.questions as Record<string, unknown>[] : [];
    const results = (roundData.results &&
      typeof roundData.results === "object") ?
      roundData.results as Record<string, {correct?: unknown}> : {};
    const judged = Object.entries(results).map(([index, verdict]) => ({
      questionId: String(
        roundQuestions[safeInt(index, -1)]?.sourceQuestionId || ""
      ),
      correct: verdict?.correct === true,
    })).filter((entry) => entry.questionId);
    tx.delete(answerKeyRef(roundRef));
    tx.delete(roundRef);

    const usedQuestionIds = new Set<string>(
      ((data.usedQuestionIds as unknown[]) || []).map((e) => String(e))
    );
    // Each question counts once per week — see scoreNewAnswers.
    const round = scoreNewAnswers(judged, usedQuestionIds);
    const correct = round.correct;
    const totalAnswered = round.answered;

    const newCorrectAnswers = safeInt(data.correctAnswers, 0) + correct;
    const newTotalAnswered = safeInt(data.totalAnswered, 0) + totalAnswered;

    round.questionIds.forEach((id) => usedQuestionIds.add(id));

    tx.set(
      participationRef,
      {
        weekId,
        categoryId,
        correctAnswers: newCorrectAnswers,
        totalAnswered: newTotalAnswered,
        usedQuestionIds: Array.from(usedQuestionIds),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(snap.exists ?
          {} : {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
      },
      {merge: true}
    );

    return {correct, totalAnswered, correctAnswers: newCorrectAnswers};
  });
});

export const claimWeeklyTopicCoinReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = cleanDocId(request.data?.weekId);
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema de la semana ya terminó.",
      "This weekly topic has ended."
    );
  }

  const rewardCoins = safeInt(topicData.rewardCoins, 0);

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(participationRef);
    const data = snap.data() || {};

    const correctAnswers = safeInt(data.correctAnswers, 0);
    const claimed = data.coinRewardClaimed === true;

    if (correctAnswers < WEEKLY_TOPIC_COIN_THRESHOLD || claimed) {
      return {claimed: false, rewardCoins: 0};
    }

    tx.set(
      participationRef,
      {
        coinRewardClaimed: true,
        coinRewardClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        coinRewardCoins: rewardCoins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(rewardCoins),
        lastWeeklyTopicRewardWeekId: weekId,
        lastWeeklyTopicRewardCoins: rewardCoins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {claimed: true, rewardCoins};
  });
});

export const claimWeeklyTopicCompletionReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = cleanDocId(request.data?.weekId);
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw await localizedErrorFor(
      uid, "failed-precondition",
      "Este tema de la semana ya terminó.",
      "This weekly topic has ended."
    );
  }

  const rewardAvatarId = String(topicData.rewardAvatarId || "");
  if (!rewardAvatarId) {
    throw new HttpsError(
      "failed-precondition", "No avatar reward configured."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);
  const weeklyTopicsAchievementRef = userRef
    .collection("achievements").doc("weekly_topics_completed_3");

  return db.runTransaction(async (tx) => {
    const participationSnap = await tx.get(participationRef);
    const participationData = participationSnap.data() || {};

    const correctAnswers = safeInt(participationData.correctAnswers, 0);
    const claimed = participationData.completionRewardClaimed === true;

    if (correctAnswers < WEEKLY_TOPIC_COMPLETION_THRESHOLD || claimed) {
      return {claimed: false};
    }

    const userSnap = await tx.get(userRef);
    const userData = userSnap.data() || {};
    const weeklyTopicsAchievementSnap =
      await tx.get(weeklyTopicsAchievementRef);

    const unlockedAvatars = new Set<string>(
      ((userData.unlockedAvatars as unknown[]) || []).map((e) => String(e))
    );
    const alreadyUnlocked = unlockedAvatars.has(rewardAvatarId);
    unlockedAvatars.add(rewardAvatarId);

    const newWeeklyTopicsCompletedCount =
      safeInt(userData.weeklyTopicsCompletedCount, 0) + 1;
    applyPvpAchievementProgress(
      tx, uid,
      {
        id: "weekly_topics_completed_3",
        title: "Weekly Explorer",
        target: 3,
      },
      newWeeklyTopicsCompletedCount, weeklyTopicsAchievementSnap,
      userData.languageCode
    );

    tx.set(
      participationRef,
      {
        completionRewardClaimed: true,
        completionRewardClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        completionRewardAvatarId: rewardAvatarId,
        completionRewardAlreadyUnlocked: alreadyUnlocked,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        unlockedAvatars: Array.from(unlockedAvatars).sort(),
        lastUnlockedAvatarId: rewardAvatarId,
        lastUnlockedAvatarReason: "Weekly Topic completed",
        lastUnlockedAvatarAt: admin.firestore.FieldValue.serverTimestamp(),
        lastWeeklyTopicCompletionRewardWeekId: weekId,
        weeklyTopicsCompletedCount: newWeeklyTopicsCompletedCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {claimed: true, rewardAvatarId, alreadyUnlocked};
  });
});

// ============================================================
// FRIENDS
//
// users/{uid}/friends/{friendId} is Cloud-Function-only (write:false) —
// the rule that let either side of a friendship write there (needed so
// accepting could write both mirror docs in one transaction) also let a
// client fabricate a "friend" doc directly, with no real request/accept
// ever happening, inflating friend counts and polluting friend lists.
// sendFriendRequest/rejectFriendRequest stay client-side (they only touch
// friend_requests/sent_friend_requests, which aren't part of this trust
// boundary); only the two writes that touch `friends` itself move here.
// ============================================================

/**
 * Recomputes and applies the friends_5 achievement's progress for a
 * player, using their real friends subcollection count as the source of
 * truth (rather than a client-reported number).
 * @param {string} uid Player id.
 */
async function syncFriendsAchievementProgress(uid: string): Promise<void> {
  const friendsSnap = await db
    .collection("users").doc(uid).collection("friends").get();
  const friendCount = friendsSnap.size;

  const achRef = db.collection("users").doc(uid)
    .collection("achievements").doc("friends_5");
  const ach10Ref = db.collection("users").doc(uid)
    .collection("achievements").doc("friends_10");

  await db.runTransaction(async (tx) => {
    const achSnap = await tx.get(achRef);
    const ach10Snap = await tx.get(ach10Ref);
    const userSnap = await tx.get(db.collection("users").doc(uid));
    const languageCode = userSnap.data()?.languageCode;

    applyPvpAchievementProgress(
      tx, uid, {id: "friends_5", title: "Social Player", target: 5},
      friendCount, achSnap, languageCode
    );
    applyPvpAchievementProgress(
      tx, uid, {id: "friends_10", title: "Social Circle", target: 10},
      friendCount, ach10Snap, languageCode
    );
  });
}

// A player can have this many requests waiting for an answer.
const MAX_PENDING_FRIEND_REQUESTS = 50;
// A rejected request can't be sent again for this long.
const FRIEND_REQUEST_RESEND_DAYS = 7;

/**
 * Sends a friend request. Cloud-Function-only, like accepting and
 * rejecting: the client used to write the request straight into the other
 * player's inbox, with any name it liked on it, and could flip a rejected
 * request back to pending to notify them again and again.
 */
export const sendFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const targetUid = cleanDocId(request.data?.targetUid);
  if (!targetUid || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid player.");
  }

  const myRef = db.collection("users").doc(uid);
  const targetRef = db.collection("users").doc(targetUid);
  const requestRef = targetRef.collection("friend_requests").doc(uid);
  const sentRef = myRef.collection("sent_friend_requests").doc(targetUid);
  const reverseRef = myRef.collection("friend_requests").doc(targetUid);

  const pendingCount = await myRef.collection("sent_friend_requests")
    .where("status", "==", "pending").count().get();

  await db.runTransaction(async (tx) => {
    const [mySnap, targetSnap, friendSnap, requestSnap, reverseSnap] =
      await tx.getAll(
        myRef, targetRef, myRef.collection("friends").doc(targetUid),
        requestRef, reverseRef
      );
    const lang = mySnap.data()?.languageCode;

    if (!targetSnap.exists) {
      throw localizedError(lang, "not-found",
        "Ese jugador ya no existe.", "That player no longer exists.");
    }
    if (friendSnap.exists) {
      throw localizedError(lang, "already-exists",
        "Ya son amigos.", "You're already friends.");
    }
    if (reverseSnap.data()?.status === "pending") {
      throw localizedError(lang, "already-exists",
        "Ese jugador ya te envió una solicitud. Revísala en Recibidas.",
        "That player already sent you a request. Check Received.");
    }

    const existing = requestSnap.data();
    if (existing?.status === "pending") {
      throw localizedError(lang, "already-exists",
        "Ya le enviaste una solicitud.", "You already sent them a request.");
    }
    if (existing?.status === "rejected") {
      const at = existing.updatedAt as admin.firestore.Timestamp | undefined;
      const waitMs = FRIEND_REQUEST_RESEND_DAYS * 86400000;
      if (at && Date.now() - at.toMillis() < waitMs) {
        throw localizedError(lang, "failed-precondition",
          "Ese jugador rechazó tu solicitud. Podrás volver a enviarla en " +
            "unos días.",
          "That player declined your request. You can send it again in " +
            "a few days.");
      }
    }
    if ((pendingCount.data().count || 0) >= MAX_PENDING_FRIEND_REQUESTS) {
      throw localizedError(lang, "resource-exhausted",
        "Tienes demasiadas solicitudes sin respuesta.",
        "You have too many unanswered requests.");
    }

    const me = mySnap.data() || {};
    const them = targetSnap.data() || {};
    const myName = String(me.displayName || me.username || "");
    const theirName = String(them.displayName || them.username || "");
    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(requestRef, {
      requesterUid: uid,
      requesterDisplayName: myName,
      requesterUsername: String(me.username || myName),
      requesterAvatarId: String(me.avatarId || "avatar_1"),
      requesterEquippedFrame: String(me.equippedFrame || "bronze"),
      requesterBestLeagueId: String(me.bestLeagueId || "bronze"),
      status: "pending",
      createdAt: now,
      updatedAt: now,
    });
    tx.set(sentRef, {
      targetUid,
      targetDisplayName: theirName,
      targetUsername: String(them.username || theirName),
      targetAvatarId: String(them.avatarId || "avatar_1"),
      targetEquippedFrame: String(them.equippedFrame || "bronze"),
      targetBestLeagueId: String(them.bestLeagueId || "bronze"),
      status: "pending",
      createdAt: now,
      updatedAt: now,
    });
  });

  // One notification per sender, ever (notifyOnce): re-sending after a
  // rejection doesn't push again.
  await notifyOnce(targetUid, uid, "friend_request", {});
  return {sent: true};
});

export const acceptFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const requesterUid = cleanDocId(request.data?.requesterUid);
  if (!requesterUid || requesterUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid request.");
  }

  const myRef = db.collection("users").doc(uid);
  const requesterRef = db.collection("users").doc(requesterUid);
  const requestRef = myRef.collection("friend_requests").doc(requesterUid);
  const myFriendRef = myRef.collection("friends").doc(requesterUid);
  const requesterFriendRef = requesterRef.collection("friends").doc(uid);
  const requesterSentRequestRef = requesterRef
    .collection("sent_friend_requests").doc(uid);

  await db.runTransaction(async (tx) => {
    const mySnap = await tx.get(myRef);
    const requesterSnap = await tx.get(requesterRef);
    const requestSnap = await tx.get(requestRef);

    const myLanguageCode = mySnap.data()?.languageCode;

    if (!requestSnap.exists) {
      throw localizedError(
        myLanguageCode, "failed-precondition",
        "Esa solicitud ya no existe.",
        "The request no longer exists."
      );
    }

    const requestStatus = String(requestSnap.data()?.status || "pending");
    if (requestStatus !== "pending") {
      throw localizedError(
        myLanguageCode, "failed-precondition",
        "Esa solicitud ya fue procesada.",
        "The request was already processed."
      );
    }

    if (!requesterSnap.exists) {
      throw await localizedErrorFor(
        uid, "not-found",
        "Ese jugador ya no existe.",
        "That player no longer exists."
      );
    }

    const myData = mySnap.data() || {};
    const requesterData = requesterSnap.data() || {};

    const myDisplayName = String(
      myData.displayName || myData.username || `Player${uid.slice(0, 4)}`
    );
    const requesterDisplayName = String(
      requesterData.displayName || requesterData.username ||
        `Player${requesterUid.slice(0, 4)}`
    );

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(myFriendRef, {
      uid: requesterUid,
      displayName: requesterDisplayName,
      username: String(requesterData.username || requesterDisplayName),
      avatarId: String(requesterData.avatarId || "avatar_1"),
      equippedFrame: requesterData.equippedFrame || "bronze",
      bestLeagueId: requesterData.bestLeagueId || "bronze",
      pvpRating: requesterData.pvpRating || 1000,
      pvpLeagueId: requesterData.pvpLeagueId || "bronze",
      pvpLeagueName: requesterData.pvpLeagueName || "Bronze",
      pvpLeagueEmoji: requesterData.pvpLeagueEmoji || "🥉",
      createdAt: now,
      updatedAt: now,
    }, {merge: true});

    tx.set(requesterFriendRef, {
      uid,
      displayName: myDisplayName,
      username: String(myData.username || myDisplayName),
      avatarId: String(myData.avatarId || "avatar_1"),
      equippedFrame: myData.equippedFrame || "bronze",
      bestLeagueId: myData.bestLeagueId || "bronze",
      pvpRating: myData.pvpRating || 1000,
      pvpLeagueId: myData.pvpLeagueId || "bronze",
      pvpLeagueName: myData.pvpLeagueName || "Bronze",
      pvpLeagueEmoji: myData.pvpLeagueEmoji || "🥉",
      createdAt: now,
      updatedAt: now,
    }, {merge: true});

    tx.update(requestRef, {status: "accepted", updatedAt: now});
    tx.set(requesterSentRequestRef, {status: "accepted", updatedAt: now},
      {merge: true});
  });

  await Promise.all([
    syncFriendsAchievementProgress(uid),
    syncFriendsAchievementProgress(requesterUid),
  ]);

  return {accepted: true};
});

/**
 * Rejects a pending friend request. Cloud-Function-only (like
 * acceptFriendRequest) since firestore.rules no longer lets the target of
 * a request write into either mirror doc directly — the target used to
 * write `sent_friend_requests` under the *requester's* own collection,
 * which also meant a client could write into a stranger's outgoing list.
 */
export const rejectFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const requesterUid = cleanDocId(request.data?.requesterUid);
  if (!requesterUid || requesterUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid request.");
  }

  const requestRef = db.collection("users").doc(uid)
    .collection("friend_requests").doc(requesterUid);
  const requesterSentRequestRef = db.collection("users").doc(requesterUid)
    .collection("sent_friend_requests").doc(uid);

  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);

    if (!requestSnap.exists) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Esa solicitud ya no existe.",
        "The request no longer exists."
      );
    }

    const requestStatus = String(requestSnap.data()?.status || "pending");
    if (requestStatus !== "pending") {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Esa solicitud ya fue procesada.",
        "The request was already processed."
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(requestRef, {status: "rejected", updatedAt: now}, {merge: true});
    tx.set(requesterSentRequestRef, {status: "rejected", updatedAt: now},
      {merge: true});
  });

  return {rejected: true};
});

export const removeFriend = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const friendUid = cleanDocId(request.data?.friendUid);
  if (!friendUid || friendUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid friend.");
  }

  const myFriendRef = db.collection("users").doc(uid)
    .collection("friends").doc(friendUid);
  const theirFriendRef = db.collection("users").doc(friendUid)
    .collection("friends").doc(uid);

  await db.runTransaction(async (tx) => {
    tx.delete(myFriendRef);
    tx.delete(theirFriendRef);
  });

  return {removed: true};
});

/**
 * Sweeps pending realtime-invite docs older than 5 minutes to
 * `status: "expired"`, so an unanswered live-challenge invite doesn't sit
 * at "pending" forever. This has to run server-side: firestore.rules only
 * lets a player touch an invite where they're fromUid/toUid, but a global
 * sweep needs to touch every stale pending invite regardless of who's on
 * it — a client-side version of this (which existed before, unreachable
 * from any screen) could never have actually worked for that reason.
 */
export const expireStaleRealtimeInvites = onSchedule(
  {schedule: "*/10 * * * *"},
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 5 * 60 * 1000
    );

    const snap = await db.collection("realtime_invites")
      .where("status", "==", "pending")
      .where("createdAt", "<", cutoff)
      .limit(200)
      .get();

    if (snap.empty) return;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
);

/**
 * Deletes the caller's account: their `users/{uid}` doc and every
 * subcollection under it (ai_topics, match_history, friends, notifications,
 * etc.), their reserved `usernames/{usernameLower}` doc, and their Firebase
 * Auth record. Required by Apple/Google app-store policy — any app that
 * lets a user create an account must let them delete it from within the
 * app. Doesn't touch other users' `friends`/`match_history` entries that
 * reference this uid — those become harmless dangling references to a
 * deleted account, same as any other player who stops playing.
 */
export const deleteMyAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const usernameLower = userSnap.data()?.usernameLower;

  await db.recursiveDelete(userRef);

  if (usernameLower) {
    const usernameRef = db.collection("usernames").doc(String(usernameLower));
    const usernameSnap = await usernameRef.get();
    if (usernameSnap.exists && usernameSnap.data()?.uid === uid) {
      await usernameRef.delete();
    }
  }

  // recursiveDelete(userRef) only clears this account's own subtree. Two
  // kinds of cross-user orphan survive it: a live_search entry other
  // players' tryFindLiveOpponent could still match against, and pending
  // friend-request mirror docs sitting in *other* users' subtrees that
  // point at this now-deleted account (friend_requests/sent_friend_requests
  // are two-sided — one doc per side, each stored under its own owner's
  // subtree, so deleting only this user's side leaves the other player's
  // mirror pointing at a ghost).
  await db.collection("live_search").doc(uid).delete();

  // Question reports carry the reporter's uid in their id and fields;
  // they go with the account (the reported question itself is unaffected).
  const reports = await db.collection("question_reports")
    .where("uid", "==", uid).get();
  const reportRefs = [
    ...reports.docs.map((doc) => doc.ref),
    db.collection("question_report_quotas").doc(uid),
  ];

  // Topics this player created stay in the shared pool for whoever already
  // plays them, but no longer point back at the account.
  const createdPools = await db.collection("ai_topic_pool")
    .where("createdByUid", "==", uid).get();
  for (let i = 0; i < createdPools.docs.length; i += 400) {
    const batch = db.batch();
    createdPools.docs.slice(i, i + 400).forEach((doc) =>
      batch.update(doc.ref, {
        createdByUid: admin.firestore.FieldValue.delete(),
      })
    );
    await batch.commit();
  }
  for (let i = 0; i < reportRefs.length; i += 400) {
    const batch = db.batch();
    reportRefs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }

  // Best-effort: by this point the account's own data is already gone, so
  // failing here would leave the caller with a live Auth record pointing at
  // nothing — deleted in every way except the one that lets them sign in
  // again. Both queries need collection-group indexes (see fieldOverrides
  // in firestore.indexes.json); if one is still building, or anything else
  // goes wrong, the leftovers are dangling references no worse than those
  // deleteMyAccount already tolerates, and the Auth record still has to go.
  try {
    const [incomingMirrors, outgoingMirrors] = await Promise.all([
      db.collectionGroup("sent_friend_requests")
        .where("targetUid", "==", uid).get(),
      db.collectionGroup("friend_requests")
        .where("requesterUid", "==", uid).get(),
    ]);

    const staleMirrorRefs = [
      ...incomingMirrors.docs.map((d) => d.ref),
      ...outgoingMirrors.docs.map((d) => d.ref),
    ];

    if (staleMirrorRefs.length > 0) {
      const batch = db.batch();
      for (const ref of staleMirrorRefs) batch.delete(ref);
      await batch.commit();
    }
  } catch (e) {
    console.warn(`Friend-request mirror cleanup failed for ${uid}: ${e}`);
  }

  await admin.auth().deleteUser(uid);

  return {deleted: true};
});
