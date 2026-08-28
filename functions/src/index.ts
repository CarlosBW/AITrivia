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
  isPlausibleDateId,
  weekIdForDateId,
} from "./daily_challenge_dates";
import {
  AI_QUESTIONS_PER_SESSION,
  bankHeadroom,
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
  mergeRecordedAnswers,
} from "./quiz_answers";
import {
  openTurn,
  resolveAnswer,
} from "./async_pvp_turns";
import {resolveWrongAnswerSpend} from "./life_costs";
import {
  DailyPoolEntry,
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

// Bounds on the "don't repeat these" list sent to Claude when topping up
// a level's bank: enough context to actually avoid duplicates, not so
// much that the avoid-list dwarfs the generation request itself.
const AI_AVOID_LIST_MAX_QUESTIONS = 60;
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
  return new HttpsError(code, pickText(languageCode, es, en));
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

const DEFAULT_RATING = 1000;
const K_FACTOR = 32;

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

type PvpLeagueInfo = {
  id: string;
  name: string;
  emoji: string;
  minRating: number;
  maxRating: number;
  colorValue: number;
};

// Mirrors lib/services/pvp_league_service.dart's `leagues` list exactly,
// including colorValue — keep both in sync.
const PVP_LEAGUES: PvpLeagueInfo[] = [
  {
    id: "bronze",
    name: "Bronze",
    emoji: "🥉",
    minRating: 0,
    maxRating: 999,
    colorValue: 0xFF8D6E63,
  },
  {
    id: "silver",
    name: "Silver",
    emoji: "🥈",
    minRating: 1000,
    maxRating: 1199,
    colorValue: 0xFF78909C,
  },
  {
    id: "gold",
    name: "Gold",
    emoji: "🥇",
    minRating: 1200,
    maxRating: 1399,
    colorValue: 0xFFFFA000,
  },
  {
    id: "platinum",
    name: "Platinum",
    emoji: "💎",
    minRating: 1400,
    maxRating: 1599,
    colorValue: 0xFF00ACC1,
  },
  {
    id: "diamond",
    name: "Diamond",
    emoji: "🔷",
    minRating: 1600,
    maxRating: 1899,
    colorValue: 0xFF5E35B1,
  },
  {
    id: "master",
    name: "Master",
    emoji: "👑",
    minRating: 1900,
    maxRating: 5000,
    colorValue: 0xFFD81B60,
  },
];

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
 * Recomputes a live-PvP player's real score from their actual submitted
 * answers, ignoring the `score` field a client wrote during play (which
 * was only ever an unverified, optimistic live-display value — see
 * match_service.dart's submitAnswer). `questions` lives on the match doc
 * itself (the same data the client already reads to render the quiz), so
 * this needs no extra fetch: a question counts only if the player's
 * recorded answers map picked the exact stored answerIndex for it.
 * @param {unknown} questions The match doc's `questions` array.
 * @param {unknown} answers The player's `players.{uid}.answers` map.
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
 * @param {string} dateId Client-supplied date id.
 */
function assertPlausibleDateId(dateId: string): void {
  if (!isPlausibleDateId(dateId, serverDateId())) {
    throw new HttpsError("invalid-argument", "Invalid dateId.");
  }
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
 * Returns the PvP league for a rating.
 * @param {number} rating Player rating.
 * @return {PvpLeagueInfo} League information.
 */
function leagueForRating(rating: number): PvpLeagueInfo {
  const league = PVP_LEAGUES.find((item) => {
    return rating >= item.minRating && rating <= item.maxRating;
  });

  if (league) return league;

  if (rating < PVP_LEAGUES[0].minRating) {
    return PVP_LEAGUES[0];
  }

  return PVP_LEAGUES[PVP_LEAGUES.length - 1];
}

/**
 * Returns a league's ordinal rank (index in PVP_LEAGUES), used to compare
 * "how good" two leagues are relative to each other.
 * @param {string} id League id.
 * @return {number} Ordinal rank, or -1 if unknown.
 */
function leagueRank(id: string): number {
  return PVP_LEAGUES.findIndex((item) => item.id === id);
}

/**
 * Mirrors match_service.dart's `_bestLeaguePatch` — only patches the user's
 * "best league ever reached" fields if the candidate league actually ranks
 * higher than what's already stored.
 * @param {Record<string, unknown>} userData Current user document data.
 * @param {PvpLeagueInfo} candidateLeague League to compare against the
 * stored best.
 * @return {Record<string, unknown>} Fields to merge, or {} if unchanged.
 */
function bestLeaguePatch(
  userData: Record<string, unknown>,
  candidateLeague: PvpLeagueInfo
): Record<string, unknown> {
  const currentBestLeagueId = String(
    userData.bestLeagueId || userData.pvpLeagueId || ""
  );

  if (leagueRank(candidateLeague.id) <= leagueRank(currentBestLeagueId)) {
    return {};
  }

  return {
    bestLeagueId: candidateLeague.id,
    bestLeagueName: candidateLeague.name,
    bestLeagueEmoji: candidateLeague.emoji,
    bestLeagueColorValue: candidateLeague.colorValue,
  };
}

/**
 * Calculates ELO rating changes.
 * @param {{
 *   playerARating:number,
 *   playerBRating:number,
 *   playerAScore:number,
 *   playerBScore:number
 * }} params Match parameters.
 * @return {{newA:number,newB:number}} New ratings.
 */
function calculateRatings(params: {
  playerARating: number;
  playerBRating: number;
  playerAScore: number;
  playerBScore: number;
}): {newA: number; newB: number} {
  let resultA = 0.5;

  if (params.playerAScore > params.playerBScore) resultA = 1.0;
  if (params.playerBScore > params.playerAScore) resultA = 0.0;

  const expectedA =
    1 / (1 + Math.pow(10, (params.playerBRating - params.playerARating) / 400));

  const expectedB = 1 - expectedA;
  const resultB = 1 - resultA;

  const newA = Math.max(
    100,
    Math.min(
      5000,
      Math.round(params.playerARating + K_FACTOR * (resultA - expectedA))
    )
  );

  const newB = Math.max(
    100,
    Math.min(
      5000,
      Math.round(params.playerBRating + K_FACTOR * (resultB - expectedB))
    )
  );

  return {newA, newB};
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
      Math.max(100, Math.min(5000, params.oldRating + bonus)) :
      Math.max(100, Math.min(5000, params.oldRating - penalty));
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

      const hostScore = computeVerifiedPvpScore(
        fresh.questions, freshHost.answers
      );
      const guestScore = computeVerifiedPvpScore(
        fresh.questions, freshGuest.answers
      );
      const matchQuestionCount = Array.isArray(fresh.questions) ?
        fresh.questions.length : 0;
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

  const matchId = String(request.data?.matchId || "");
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

    const opponentSnap = await tx.get(
      db.collection("users").doc(opponentUid)
    );
    const presence = (opponentSnap.data() || {}).presence || {};

    const presenceStatus = String(presence.status || "offline");
    const inMatch = presence.inMatch === true;
    const updatedAt = presence.updatedAt;

    const isFresh = updatedAt instanceof admin.firestore.Timestamp &&
      (Date.now() - updatedAt.toMillis()) <= PRESENCE_ONLINE_MAX_AGE_MS;

    const opponentLooksActive =
      isFresh && presenceStatus === "in_match" && inMatch;

    if (opponentLooksActive) {
      throw await localizedErrorFor(
        uid, "failed-precondition",
        "Tu rival todavía parece activo. Inténtalo en un momento.",
        "Your opponent still looks active. Try again in a moment."
      );
    }

    const players = matchData.players || {};
    if (!players[uid]) {
      throw new HttpsError(
        "failed-precondition", "You're not seated in this match."
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

  const matchesQuery = await db.collection("matches")
    .where("matchCode", "==", code)
    .limit(1)
    .get();

  if (matchesQuery.empty) {
    throw new HttpsError("not-found", "Code not found.");
  }

  const matchRef = matchesQuery.docs[0].ref;

  const userSnap = await db.collection("users").doc(uid).get();
  const userData = userSnap.data() || {};

  const displayName = String(
    userData.displayName || userData.username || "Guest"
  );
  const avatarId = String(userData.avatarId || "avatar_1");
  const frameId = String(userData.equippedFrame || "");
  const bestLeagueId = String(userData.bestLeagueId || "");

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const data = snap.data();

    if (!data) {
      throw new HttpsError("not-found", "Room not found.");
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
      [`players.${uid}`]: {
        displayName,
        avatarId,
        equippedFrame: frameId,
        bestLeagueId,
        score: 0,
        ready: false,
        finished: false,
      },
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

  const categoryId = String(meData?.categoryId || "");
  const difficulty = safeInt(meData?.difficulty, 1);
  const ranked = meData?.ranked === true;
  const totalQuestions = safeInt(meData?.totalQuestions, 10);
  const timePerQuestionSec = safeInt(meData?.timePerQuestionSec, 15);
  const winReward = clampWinReward(safeInt(meData?.winReward, 2));

  const candidatesSnap = await db.collection("live_search")
    .where("status", "==", "searching")
    .where("categoryId", "==", categoryId)
    .where("difficulty", "==", difficulty)
    .where("ranked", "==", ranked)
    .limit(20)
    .get();

  const candidates = candidatesSnap.docs.filter((d) => d.id !== uid);

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
      const meUser = meUserSnap.data();
      const oppUser = oppUserSnap.data();

      if (!isLiveQueueEntryValid(meTx)) return false;
      if (!isLiveQueueEntryValid(oppTx)) return false;
      if (!isAvailableForLiveMatch(meUser)) return false;
      if (!isAvailableForLiveMatch(oppUser)) return false;
      if ((meTx?.ranked === true) !== ranked) return false;
      if ((oppTx?.ranked === true) !== ranked) return false;
      if (ranked && !ratingsAreCompatible(meTx, oppTx)) return false;

      const now = admin.firestore.FieldValue.serverTimestamp();

      tx.update(meRef, {
        status: "matched", matchId: matchRef.id, opponentUid: oppUid,
        updatedAt: now,
      });
      tx.update(oppRef, {
        status: "matched", matchId: matchRef.id, opponentUid: uid,
        updatedAt: now,
      });

      tx.set(meUserRef, {
        presence: {
          status: "in_match", inMatch: true, lastSeenAt: now, updatedAt: now,
        },
        updatedAt: now,
      }, {merge: true});

      tx.set(oppUserRef, {
        presence: {
          status: "in_match", inMatch: true, lastSeenAt: now, updatedAt: now,
        },
        updatedAt: now,
      }, {merge: true});

      return true;
    });

    if (!claimed) continue;

    const oppData = oppDoc.data();

    const myRating = safeInt(meData?.pvpRating, DEFAULT_RATING);
    const oppRating = safeInt(oppData.pvpRating, DEFAULT_RATING);
    const myLeague = leagueForRating(myRating);
    const oppLeague = leagueForRating(oppRating);

    const questions = await selectFixedMatchQuestions(
      categoryId, difficulty, totalQuestions
    );

    const myName = String(meData?.displayName || "Player").trim() ||
      "Player";
    const oppName = String(oppData.displayName || "Player").trim() ||
      "Player";

    await matchRef.set({
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: "waiting",
      mode: "fixed",
      matchmakingType: ranked ? "ranked_flexible_mmr" : "casual_public",
      ranked,
      affectsPvpRating: ranked,
      hostInitialPvpRating: myRating,
      guestInitialPvpRating: oppRating,
      matchmakingRatingGap: Math.abs(myRating - oppRating),
      hostPvpLeagueId: myLeague.id,
      guestPvpLeagueId: oppLeague.id,
      hostPvpLeagueName: myLeague.name,
      guestPvpLeagueName: oppLeague.name,
      matchmakingWaitSec: Math.max(
        searchAgeSeconds(meData), searchAgeSeconds(oppData)
      ),
      categoryId,
      difficulty,
      aiTopic: null,
      entryFee: 0,
      winReward,
      loseReward: 0,
      totalQuestions,
      timePerQuestionSec,
      questions,
      hostUid: uid,
      guestUid: oppUid,
      players: {
        [uid]: {
          displayName: myName,
          avatarId: String(meData?.avatarId || "avatar_1"),
          equippedFrame: String(meData?.equippedFrame || ""),
          bestLeagueId: String(meData?.bestLeagueId || ""),
          score: 0, ready: false, finished: false,
        },
        [oppUid]: {
          displayName: oppName,
          avatarId: String(oppData.avatarId || "avatar_1"),
          equippedFrame: String(oppData.equippedFrame || ""),
          bestLeagueId: String(oppData.bestLeagueId || ""),
          score: 0, ready: false, finished: false,
        },
      },
      startAt: null,
      endedAt: null,
      winnerUid: null,
      rewarded: false,
      matchCode: randomMatchCode(5),
    });

    return {matchId: matchRef.id};
  }

  return {matchId: null};
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

      const challengerScore = computeVerifiedPvpScore(
        fresh.questions, fresh.challenger?.answers
      );
      const challengedScore = computeVerifiedPvpScore(
        fresh.questions, fresh.challenged?.answers
      );
      const matchQuestionCount = Array.isArray(fresh.questions) ?
        fresh.questions.length : 0;
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
export const createAsyncPvpMatch = onCall({
  // Selecting questions reads a whole category pool, which is slower than
  // a plain write — the client gives up well before this.
  timeoutSeconds: 60,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const challengedUid = String(request.data?.challengedUid || "");

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
    throw new HttpsError("not-found", "That player no longer exists.");
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

  await matchRef.set({
    createdAt: now,
    lastUpdatedAt: now,

    status: "waiting_challenged",
    mode: "fixed",
    categoryId,
    difficulty,
    totalQuestions: questions.length,
    timePerQuestionSec,
    questions,

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
  const challengedUid = String(data.challengedUid || "");

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

  const matchId = String(request.data?.matchId || "");
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const matchRef = db.collection("async_matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const ctx = asyncMatchContextFor(snap.data(), uid);

    if (ctx.finishedAlready) {
      return {
        index: ctx.questionCount,
        finished: true,
        remainingMs: 0,
        answers: ctx.answers,
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
      tx.update(matchRef, patch);
    }

    return {
      index: turn.index,
      finished: turn.finished,
      remainingMs: turn.remainingMs,
      answers,
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

  const matchId = String(request.data?.matchId || "");
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
    };

    if (resolution.nextDeadlineMs !== null) {
      patch[`${ctx.role}.deadlines.${resolution.nextIndex}`] =
        resolution.nextDeadlineMs;
    }

    tx.update(matchRef, patch);

    return {
      storedIndex: resolution.storedIndex,
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

  const matchId = String(request.data?.matchId || "");
  if (!matchId) {
    throw new HttpsError("invalid-argument", "Missing matchId.");
  }

  const matchRef = db.collection("async_matches").doc(matchId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    const ctx = asyncMatchContextFor(snap.data(), uid);

    if (ctx.finishedAlready) {
      return {
        alreadyFinished: true,
        score: computeVerifiedPvpScore(ctx.data.questions, ctx.answers),
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

    const score = computeVerifiedPvpScore(ctx.data.questions, answers);
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
    if (data.status === "declined") return;

    const challengerFinished = data.challengerStatus === "finished";
    const challengedFinished = data.challengedStatus === "finished";

    // Only forfeit the one-sided case — if neither side ever played,
    // there's nothing to award; if both finished, finalizeAsyncPvpMatch's
    // own trigger already handled it and rewarded would be true by now.
    if (challengerFinished === challengedFinished) return;

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
    const winnerScore = safeInt(
      challengerFinished ? data.challengerScore : data.challengedScore, 0
    );
    const loserScore = safeInt(
      challengerFinished ? data.challengedScore : data.challengerScore, 0
    );

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

const DAILY_COINS_PER_BLOCK = 5;
const DAILY_CORRECT_PER_COIN_BLOCK = 10;
const DAILY_STREAK_3_DAYS_COINS = 5;
const DAILY_STREAK_7_DAYS_COINS = 15;
const DAILY_STREAK_14_DAYS_COINS = 30;
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
 * Mirrors lib/services/player_level_service.dart's `xpRequiredForLevel`.
 * @param {number} level Player level.
 * @return {number} XP required to complete that level.
 */
function xpRequiredForLevel(level: number): number {
  if (level <= 1) return 100;
  return Math.round(100 * (1.18 * (level - 1)));
}

/**
 * Mirrors lib/services/player_level_service.dart's `getLevelInfo` — only
 * the `level` field is needed here.
 * @param {number} totalXp Player's total XP.
 * @return {number} Player level for that XP total.
 */
function levelForXp(totalXp: number): number {
  let level = 1;
  let remainingXp = totalXp;

  for (;;) {
    const needed = xpRequiredForLevel(level);
    if (remainingXp < needed) return level;
    remainingXp -= needed;
    level++;
  }
}

/**
 * Mirrors DailyChallengeService's `calculateCoinsEarned`.
 * @param {number} correct Correct answers.
 * @return {number} Coins earned.
 */
function calculateDailyCoinsEarned(correct: number): number {
  return Math.floor(correct / DAILY_CORRECT_PER_COIN_BLOCK) *
    DAILY_COINS_PER_BLOCK;
}

/**
 * Mirrors DailyChallengeService's `calculateXpEarned`.
 * @param {number} correct Correct answers.
 * @param {number} totalAnswered Total questions answered.
 * @return {number} XP earned.
 */
function calculateDailyXpEarned(
  correct: number,
  totalAnswered: number
): number {
  const wrong = Math.max(totalAnswered - correct, 0);
  const baseXp = correct * 2;
  const participationXp = totalAnswered > 0 ? 5 : 0;
  const accuracyBonus = totalAnswered > 0 && wrong === 0 ? 5 : 0;
  return baseXp + participationXp + accuracyBonus;
}

/**
 * Mirrors DailyChallengeService's `calculateScore`.
 * @param {number} correct Correct answers.
 * @param {number} totalAnswered Total questions answered.
 * @param {number} streak Daily streak after this play.
 * @return {number} Daily score.
 */
function calculateDailyScore(
  correct: number,
  totalAnswered: number,
  streak: number
): number {
  const accuracyBonus = totalAnswered <= 0 ?
    0 : Math.round((correct / totalAnswered) * 100);
  const streakBonus = Math.min(streak, 30) * 2;
  return correct * 10 + accuracyBonus + streakBonus;
}

/**
 * Mirrors DailyChallengeService's `calculateStreakBonusCoins`.
 * @param {number} streak Daily streak after this play.
 * @return {number} Bonus coins for hitting a streak milestone.
 */
function calculateDailyStreakBonusCoins(streak: number): number {
  if (streak > 0 && streak % 14 === 0) return DAILY_STREAK_14_DAYS_COINS;
  if (streak > 0 && streak % 7 === 0) return DAILY_STREAK_7_DAYS_COINS;
  if (streak > 0 && streak % 3 === 0) return DAILY_STREAK_3_DAYS_COINS;
  return 0;
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
 * Parses client-submitted per-question answers (Daily Challenge and Solo
 * Levels both use this exact shape), dropping anything malformed rather
 * than throwing — an invalid/missing entry for a given question just
 * never counts toward correct or totalAnswered below.
 * @param {unknown} raw The raw `request.data.answers` value.
 * @return {QuestionAnswer[]} The well-formed entries.
 */
function parseQuestionAnswers(raw: unknown): QuestionAnswer[] {
  if (!Array.isArray(raw)) return [];

  const out: QuestionAnswer[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const questionIndex = safeInt(e.questionIndex, -1);
    const selectedIndex = safeInt(e.selectedIndex, -1);
    if (questionIndex < 0 || selectedIndex < 0) continue;
    out.push({questionIndex, selectedIndex});
  }
  return out;
}

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
  // below from `answers` against the session's own stored `questions`.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotalAnswered = safeInt(request.data?.totalAnswered, -1);
  const answers = parseQuestionAnswers(request.data?.answers);
  const dateId = String(request.data?.dateId || "");
  const weekId = String(request.data?.weekId || "");

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
  assertPlausibleDateId(dateId);
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

    const {correct, totalAnswered} = computeVerifiedQuizResult(
      dailySnap.data()?.questions, answers, DAILY_QUESTION_LIMIT
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

    const weeklyRef = db
      .collection("weekly_leagues").doc(weekId)
      .collection(league.id).doc(uid);

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
      maxDailyStreak: Math.max(previousStreak, newStreak),
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
      leagueId: league.id,
      leagueName: league.name,
      weeklyScore: admin.firestore.FieldValue.increment(score),
      level: newLevel,
      streak: newStreak,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(weeklyParticipationRef, {
      weekId,
      leagueId: league.id,
      leagueName: league.name,
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
  assertPlausibleDateId(dateId);

  const userRef = db.collection("users").doc(uid);
  const dailyRef = userRef.collection("daily_challenges").doc(dateId);

  const existing = await dailyRef.get();
  if (existing.exists) {
    return {created: false};
  }

  // Everyone who plays today gets this same set, in this same order.
  const questions = await loadSharedDailyQuestions(dateId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(dailyRef);
    if (snap.exists) return;

    tx.set(dailyRef, {
      dateId,
      played: false,
      durationSeconds: DAILY_DURATION_SECONDS,
      questions,
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
  const currentSeasonId = currentWeekId();

  const userSnap = await userRef.get();
  const languageCode = userSnap.data()?.languageCode;

  const participationSnap = await userRef
    .collection("weekly_participation")
    .orderBy("weekId", "desc")
    .limit(8)
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

    if (seasonId === currentSeasonId) continue;
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

  const batch = db.batch();
  let totalCoins = 0;

  for (const reward of pending) {
    const historyRef = userRef.collection("season_history").doc(
      reward.seasonId
    );

    batch.set(historyRef, {
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
    batch.set(userRef, {
      coins: admin.firestore.FieldValue.increment(totalCoins),
      lastSeasonRewardClaimed: pending[pending.length - 1].seasonId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  await batch.commit();

  return {claimedCount: pending.length, totalCoins};
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
    const snap = await db.collection("matches")
      .doc(String(data.matchId || "")).get();
    const m = snap.data();
    if (!m) return false;
    const uids = [m.hostUid, m.guestUid];
    return uids.includes(uid) && uids.includes(targetUid);
  }

  if (type === "match_invite" || type === "match_turn") {
    const snap = await db.collection("async_matches")
      .doc(String(data.matchId || "")).get();
    const m = snap.data();
    if (!m) return false;
    const uids = [m.challengerUid, m.challengedUid];
    return uids.includes(uid) && uids.includes(targetUid);
  }

  if (type === "realtime_invite_accepted") {
    const snap = await db.collection("realtime_invites")
      .doc(String(data.inviteId || "")).get();
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

  const targetUid = String(request.data?.targetUid || "");
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
  const senderName = String(
    senderData.displayName || senderData.username || "?"
  );

  const {title, body} = crossUserNotificationText(
    type, targetSnap.data()?.languageCode, senderName
  );

  await db.collection("users").doc(targetUid)
    .collection("notifications").add({
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
    // doc, which any signed-in user may read (that read is what the
    // friends list, leaderboards and profile views rely on). The user doc
    // is still checked as a fallback so devices that haven't opened the
    // app since the move keep receiving pushes; that branch can go once
    // the old field has aged out.
    const [pushSnap, userSnap] = await db.getAll(
      db.collection("users").doc(uid).collection("private").doc("push"),
      db.collection("users").doc(uid)
    );

    const token = pushSnap.data()?.fcmToken ?? userSnap.data()?.fcmToken;

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
    const now = new Date();
    const dateId = `${now.getFullYear()}-${String(
      now.getMonth() + 1
    ).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

    // Paged rather than one unbounded read: every player with a live streak
    // matches this query, so a single `.get()` grows with the whole active
    // player base and lands in one invocation's memory. Writes go out in
    // batches for the same reason — one `add()` per user through an
    // unbounded Promise.all opened as many concurrent writes as there were
    // users.
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    for (;;) {
      let page = db
        .collection("users")
        .where("dailyStreak", ">", 0)
        .orderBy("dailyStreak")
        .limit(STREAK_NOTIFY_PAGE_SIZE);

      if (cursor) page = page.startAfter(cursor);

      const snap = await page.get();
      if (snap.empty) break;

      const batch = db.batch();
      let queued = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        if (data.lastDailyPlayed === dateId) continue;

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
            `Tienes una racha de ${streak} días. Juega el Daily ` +
              "Challenge de hoy antes de perderla.",
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
  if (!/^\d{4}-\d{2}-\d{2}$/.test(todayDateId)) {
    throw new HttpsError("invalid-argument", "Invalid todayDateId.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const lastLoginDate = data.lastLoginDate ?
      String(data.lastLoginDate) : null;
    const previousStreak = safeInt(data.loginStreak, 0);

    if (lastLoginDate === todayDateId) {
      return {
        streak: previousStreak,
        coinsEarned: 0,
        alreadyProcessedToday: true,
      };
    }

    const newStreak = lastLoginDate && isYesterday(lastLoginDate, todayDateId) ?
      previousStreak + 1 : 1;

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

const SOLO_PERFECT_LEVEL_COINS = 3;
const SOLO_GREAT_LEVEL_COINS = 2;
const SOLO_GOOD_LEVEL_COINS = 1;
const COMPLETE_FIXED_CATEGORY_COINS = 10;
const AI_LEVELS_PER_TOPIC = 10;
const AI_QUESTIONS_PER_LEVEL = 10;
const AI_INITIAL_GENERATED_LEVELS = 2;
const AI_GENERATION_BUFFER_LEVELS = 2;
const AI_MODEL = "claude-haiku-4-5";

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

/**
 * Reward math for a single Solo level attempt — fully server-side now,
 * no client-side equivalent to mirror.
 * @param {number} correct Correct answers in this level attempt.
 * @param {number} total Total questions in this level attempt.
 * @return {{xp:number, coins:number}} Reward for this attempt.
 */
function calculateLevelRewards(
  correct: number,
  total: number
): {xp: number; coins: number} {
  const pct = total === 0 ? 0 : correct / total;
  const xp = correct * 10;

  let coins = 0;
  if (pct >= 0.9) coins = SOLO_PERFECT_LEVEL_COINS;
  else if (pct >= 0.7) coins = SOLO_GREAT_LEVEL_COINS;
  else if (pct >= 0.4) coins = SOLO_GOOD_LEVEL_COINS;

  return {xp, coins};
}

export const submitSoloLevelResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = String(request.data?.categoryId || "");
  const aiTopicId = request.data?.aiTopicId ?
    String(request.data.aiTopicId) : null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  // `correct`/`total` are only used for a fast request-shape check here —
  // the real, reward-determining values are recomputed below from
  // `answers` against the level session's own stored `questions`.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotal = safeInt(request.data?.total, -1);
  const answers = parseQuestionAnswers(request.data?.answers);

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

    // Answers banked by `recordSoloLevelAnswer` as the player went beat
    // whatever the client reports now — that is what stops a player from
    // backing out, looking the answers up and re-entering to the same
    // questions. The submission still fills in anything that never got
    // banked, so a run with a dropped call is scored on what was played.
    const scoredAnswers = mergeRecordedAnswers(
      sessionData?.answers as Record<string, unknown> | undefined,
      answers
    );

    const {correct} = computeVerifiedQuizResult(
      sessionQuestions, scoredAnswers, total
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
    // would only churn reads for no new content.
    if (isAiTopic) {
      tx.delete(sessionRef);
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
  const categoryId = String(request.data?.categoryId || "");
  const aiTopicId = request.data?.aiTopicId ?
    String(request.data.aiTopicId) : null;
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
      throw new HttpsError("not-found", "This topic no longer exists.");
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
          avoidQuestions: await existingPoolQuestionTexts(
            poolRef, AI_AVOID_LIST_MAX_QUESTIONS
          ),
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
      throw new HttpsError(
        "not-found", "No questions found for this level."
      );
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
      throw new HttpsError(
        "not-found", "No questions found for this level."
      );
    }

    await db.runTransaction(async (tx) => {
      const sesSnap = await tx.get(sessionRef);
      if (sesSnap.exists) return;

      tx.set(sessionRef, {
        categoryId: aiTopicId,
        levelNumber,
        difficulty: 1,
        total: chosen.length,
        questions: chosen,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

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
    throw new HttpsError(
      "not-found", `No questions available for ${categoryId}.`
    );
  }

  await db.runTransaction(async (tx) => {
    const sesSnap = await tx.get(sessionRef);
    if (sesSnap.exists) return;

    tx.set(sessionRef, {
      categoryId,
      levelNumber,
      difficulty: usedDifficulty,
      total: chosen.length,
      seed,
      questions: chosen,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return {created: true};
});

/**
 * Banks one Solo/AI-topic answer the moment it is given.
 *
 * Solo levels were scored purely from the list the client sent when the
 * level ended, and nothing was written before that — so backing out
 * mid-level threw the run away, and re-entering served the same questions
 * with a clean slate. The only cost was a life, which is not much of a
 * deterrent against stepping out to look an answer up. Banking each answer
 * here makes the first one final: `submitSoloLevelResult` scores from
 * these (see `mergeRecordedAnswers`), so a replay can re-see a question
 * but not change what it scored.
 *
 * First write per question index wins; later ones are accepted and
 * ignored, so a client retrying a dropped call is not an error. Sessions
 * are client-read-only (`firestore.rules` denies update on
 * sessions_fixed/sessions_ai), which is why this has to be a callable.
 */
export const recordSoloLevelAnswer = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = String(request.data?.categoryId || "");
  const aiTopicId = request.data?.aiTopicId ?
    String(request.data.aiTopicId) : null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  const questionIndex = safeInt(request.data?.questionIndex, -1);
  // TIMED_OUT_ANSWER (-1) is a legitimate value: it closes the question as
  // wrong so running the clock out isn't a way to keep it open.
  const selectedIndex = safeInt(
    request.data?.selectedIndex, TIMED_OUT_ANSWER
  );

  if (levelNumber < 1 || questionIndex < 0) {
    throw new HttpsError("invalid-argument", "Invalid answer.");
  }
  if (isAiTopic && !aiTopicId) {
    throw new HttpsError("invalid-argument", "Missing aiTopicId.");
  }
  if (!isAiTopic && !categoryId) {
    throw new HttpsError("invalid-argument", "Missing categoryId.");
  }

  const sessionId = isAiTopic ?
    `${aiTopicId}_${levelNumber}` : `${categoryId}_${levelNumber}`;
  const sessionRef = db.collection("users").doc(uid)
    .collection(isAiTopic ? "sessions_ai" : "sessions_fixed").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(sessionRef);
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "No open session.");
    }

    const data = snap.data() || {};
    const banked = (data.answers && typeof data.answers === "object") ?
      data.answers as Record<string, unknown> : {};

    const key = String(questionIndex);
    if (Object.prototype.hasOwnProperty.call(banked, key)) {
      return {answers: banked};
    }

    // Bounded by the session's own question count so a client can't grow
    // the doc with indices that don't exist.
    const questionCount = Array.isArray(data.questions) ?
      data.questions.length : 0;
    if (questionIndex >= questionCount) {
      throw new HttpsError("invalid-argument", "Question out of range.");
    }

    tx.set(sessionRef, {answers: {[key]: selectedIndex}}, {merge: true});

    return {answers: {...banked, [key]: selectedIndex}};
  });
});

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
  const categoryId = String(request.data?.categoryId || "");
  const aiTopicId = request.data?.aiTopicId ?
    String(request.data.aiTopicId) : null;
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

export const consumeWrongAnswerLife = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};
    const nowMs = Date.now();

    const gamesPlayed = safeInt(data.gamesPlayed, 0);
    const state = computeLifeState(data, nowMs);

    const spend = resolveWrongAnswerSpend(
      state.lifeUnits, WRONG_ANSWER_COST_UNITS,
      gamesPlayed, NEW_PLAYER_GRACE_LEVELS
    );

    // Covers the grace window and, previously missed, a player already at
    // zero: the deduction clamped to zero but this still answered
    // `lifeLost: true`, so a wrong answer that cost them nothing was
    // reported as one that did — and the "no life lost" message it
    // suppresses is exactly the one that case should show. Skipping the
    // write too, since it would only rewrite the values it just read.
    if (!spend.lifeLost) {
      return {lifeLost: false, ...lifeStateResponse(state)};
    }

    const wasFull = state.lifeUnits >= state.maxLifeUnits;
    const newTickMs = (wasFull && spend.newUnits < state.maxLifeUnits) ?
      nowMs : state.lastTickMs;

    tx.set(userRef, {
      lifeUnits: spend.newUnits,
      maxLifeUnits: state.maxLifeUnits,
      lifeRegenSeconds: state.lifeRegenSeconds,
      lastLifeTickAt: admin.firestore.Timestamp.fromMillis(newTickMs),
    }, {merge: true});

    return {lifeLost: true, ...lifeStateResponse(stateAfterSpend(state,
      spend.newUnits, newTickMs))};
  });
});

/**
 * Refunds a level-entry charge (see consumeLevelEntryLife) when session
 * creation fails after the life was already spent, so the player isn't
 * left with nothing to show for it — mirrors life_service.dart's
 * `refundLevelEntry`.
 */
export const refundLevelEntryLife = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};
    const state = computeLifeState(data, Date.now());

    const newUnits = Math.min(
      state.lifeUnits + LEVEL_ENTRY_COST_UNITS, state.maxLifeUnits
    );

    tx.set(userRef, {
      lifeUnits: newUnits,
      maxLifeUnits: state.maxLifeUnits,
      lifeRegenSeconds: state.lifeRegenSeconds,
      lastLifeTickAt: admin.firestore.Timestamp.fromMillis(state.lastTickMs),
    }, {merge: true});
  });

  return {ok: true};
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
// Structure only — Google Play Console / App Store Connect aren't set up
// yet, so there is no real receipt to verify against. This function must
// stay fail-closed (reject every call) until that's wired up; it must
// NEVER credit coins based on the client's say-so alone, the same way no
// other economy path in this file trusts a client-reported amount.
//
// Mirrors economy_service.dart's `EconomyService.coinPacks` exactly —
// keep both in sync. Ids must match the products configured in each
// store once those accounts exist.
// ============================================================

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

  // TODO(store-setup): once both store accounts exist and the packs
  // above are configured as real products, verify `verificationData`
  // against the actual store before granting `coins`:
  //  - source === "google_play": call the Google Play Developer API's
  //    purchases.products.get with a service-account credential,
  //    confirm purchaseState is "purchased", and acknowledge/consume the
  //    token so it can't be replayed.
  //  - source === "app_store": call the App Store Server API (or the
  //    legacy verifyReceipt endpoint) with the app's shared secret,
  //    confirm the transaction is valid, and track its transaction id in
  //    Firestore so the same receipt can't be replayed for a second
  //    payout.
  // Only after that check passes should this run a transaction crediting
  // `coins` to the user doc — exactly like every other reward path in
  // this file, never trust a client-supplied amount directly.
  throw await localizedErrorFor(
    uid, "failed-precondition",
    "Las compras de monedas todavía no están habilitadas.",
    "Coin purchases aren't enabled yet."
  );
});

// ============================================================
// AI TOPICS ECONOMY
//
// Content generation is a real Claude Haiku 4.5 call, so it can fail —
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
  return title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
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
 * Calls Claude Haiku 4.5 to generate one level's worth of trivia questions
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
  // back what the player has already been asked. Capped and truncated
  // because the bank spans every level and grows to
  // AI_QUESTION_BANK_CAP per level — sending all of it verbatim would
  // dominate the prompt and cost more than the generation itself.
  const avoidList = avoidQuestions
    .slice(0, AI_AVOID_LIST_MAX_QUESTIONS)
    .map((q) => `- ${q.slice(0, AI_AVOID_LIST_MAX_CHARS)}`)
    .join("\n");

  const prompt = `Generate exactly ${count} multiple-choice ` +
    `trivia questions about "${title}", at ${difficulty} difficulty ` +
    `(this is level ${levelNumber} of ${AI_LEVELS_PER_TOPIC}; difficulty ` +
    "should scale up with the level number). Write every question, " +
    `option, and explanation in ${outputLanguage}. Each question needs ` +
    "exactly 4 answer options with exactly one correct answer. Vary the " +
    "position of the correct answer across questions instead of always " +
    "using the same index. Do not repeat questions or trivially reword " +
    "the same fact twice." +
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
            options: {type: "array", items: {type: "string"}},
            answerIndex: {type: "integer"},
            explanation: {type: "string"},
          },
          required: ["q", "options", "answerIndex", "explanation"],
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
        max_tokens: 4096,
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

      const block = response.content[0];
      if (!block || block.type !== "text") {
        throw new Error("Unexpected response block type from Claude.");
      }

      const parsed = JSON.parse(block.text) as {
        questions?: GeneratedAiQuestion[];
      };
      const questions = parsed.questions || [];

      if (questions.length !== count) {
        throw new Error(
          `Expected ${count} questions, got ` +
          `${questions.length}.`
        );
      }

      for (const question of questions) {
        if (
          typeof question.q !== "string" || question.q.trim() === "" ||
          !Array.isArray(question.options) ||
          question.options.length !== 4 ||
          question.options.some((o) => typeof o !== "string") ||
          !Number.isInteger(question.answerIndex) ||
          question.answerIndex < 0 || question.answerIndex > 3
        ) {
          throw new Error("Malformed question from Claude.");
        }
      }

      return questions;
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
 * @param {number} maxQuestions Ceiling on how many texts are collected.
 * @return {Promise<string[]>} Existing question texts, ordered for
 * [capAvoidList]'s `rest`.
 */
async function existingPoolQuestionTexts(
  poolRef: FirebaseFirestore.DocumentReference,
  maxQuestions: number
): Promise<string[]> {
  const levelsSnap = await poolRef.collection("levels").get();

  const levelDocs = [...levelsSnap.docs].sort((a, b) =>
    safeInt(b.data().levelNumber, 0) - safeInt(a.data().levelNumber, 0)
  );

  if (levelDocs.length === 0) return [];

  // A slice of every level rather than everything from the newest few.
  // This used to read whole levels until the budget ran out, which meant
  // banks grown to AI_QUESTION_BANK_CAP let three or four recent levels
  // consume the entire allowance — the older ones were never sent, so the
  // model happily rewrote them. Same read cost, spread evenly.
  const perLevelBudget = Math.max(
    1, Math.ceil(maxQuestions / levelDocs.length)
  );

  const perLevel = await Promise.all(levelDocs.map(async (levelDoc) => {
    const questionsSnap = await levelDoc.ref
      .collection("questions").limit(perLevelBudget).get();

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
        let avoidQuestions = await existingPoolQuestionTexts(
          poolRef, AI_AVOID_LIST_MAX_QUESTIONS
        );

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
export const findSimilarAiTopics = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertAiTopicCapAvailable(uid);

  const cleanTitle = String(request.data?.title || "").trim();
  if (cleanTitle.length < 3) {
    // Too short to search meaningfully — this is a search, not a hard
    // submit, so return no matches rather than erroring.
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
        max_tokens: 512,
        system: AI_TOPIC_SYSTEM_PROMPT,
        messages: [{role: "user", content: prompt}],
        output_config: {format: {type: "json_schema", schema}},
      });

      if (response.stop_reason === "refusal") {
        await recordBlockedTopic(cleanTitle, moderationKey, "model_refusal");
        return {blocked: true, suggestions: []};
      }

      const block = response.content[0];
      if (!block || block.type !== "text") {
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
      let avoidQuestions = await existingPoolQuestionTexts(
        poolRef, AI_AVOID_LIST_MAX_QUESTIONS
      );

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
      throw new HttpsError(
        "resource-exhausted",
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

  const topicId = String(request.data?.topicId || "");
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
    let avoidQuestions = await existingPoolQuestionTexts(
      poolRef, AI_AVOID_LIST_MAX_QUESTIONS
    );

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

  const topicId = String(request.data?.topicId || "");
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

  const topicId = String(request.data?.topicId || "");
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
      avoidQuestions = await existingPoolQuestionTexts(
        poolRef, AI_AVOID_LIST_MAX_QUESTIONS
      );
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

  const topicId = String(request.data?.topicId || "");
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
          avoidQuestions = await existingPoolQuestionTexts(
            poolRef, AI_AVOID_LIST_MAX_QUESTIONS
          );
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
export const refundAiTopicCost = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const topicSnap = await tx.get(topicRef);
    const topicData = topicSnap.data();

    if (
      !topicData ||
      topicData.costRefunded === true ||
      topicData.status === "ready"
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

const AI_QUESTION_REPORT_REASONS = new Set([
  "wrong_answer",
  "confusing",
  "inappropriate",
  "other",
]);

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

  const topicId = String(request.data?.topicId || "");
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  const questionId = String(request.data?.questionId || "");
  const questionText = String(request.data?.questionText || "");
  const reason = String(request.data?.reason || "");
  const details = String(request.data?.details || "").slice(0, 500);

  if (
    !topicId || levelNumber < 1 || !questionId ||
    !AI_QUESTION_REPORT_REASONS.has(reason)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report.");
  }

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

  return db.runTransaction(async (tx) => {
    const [levelSnap, existingReportSnap] = await Promise.all([
      tx.get(levelRef),
      tx.get(reportRef),
    ]);

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
          details,
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
});

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
  title: string;
  descriptionEs: string;
  descriptionEn: string;
  rewardAvatarId: string;
}[] = [
  {
    categoryId: "cine", title: "Cine Week",
    descriptionEs: "Completa niveles de cine y gana recompensas.",
    descriptionEn: "Complete cinema levels and earn rewards.",
    rewardAvatarId: "weekly_cine",
  },
  {
    categoryId: "historia", title: "History Week",
    descriptionEs: "Completa niveles de historia y gana recompensas.",
    descriptionEn: "Complete history levels and earn rewards.",
    rewardAvatarId: "weekly_history",
  },
  {
    categoryId: "ciencia", title: "Science Week",
    descriptionEs: "Completa niveles de ciencia y gana recompensas.",
    descriptionEn: "Complete science levels and earn rewards.",
    rewardAvatarId: "weekly_science",
  },
  {
    categoryId: "musica", title: "Music Week",
    descriptionEs: "Completa niveles de música y gana recompensas.",
    descriptionEn: "Complete music levels and earn rewards.",
    rewardAvatarId: "weekly_music",
  },
  {
    categoryId: "arte", title: "Art Week",
    descriptionEs: "Completa niveles de arte y gana recompensas.",
    descriptionEn: "Complete art levels and earn rewards.",
    rewardAvatarId: "weekly_art",
  },
  {
    categoryId: "geografia", title: "Geography Week",
    descriptionEs: "Completa niveles de geografía y gana recompensas.",
    descriptionEn: "Complete geography levels and earn rewards.",
    rewardAvatarId: "weekly_geography",
  },
  {
    categoryId: "deportes", title: "Sports Week",
    descriptionEs: "Completa niveles de deportes y gana recompensas.",
    descriptionEn: "Complete sports levels and earn rewards.",
    rewardAvatarId: "weekly_sports",
  },
  {
    categoryId: "videojuegos", title: "Gaming Week",
    descriptionEs: "Completa niveles de videojuegos y gana recompensas.",
    descriptionEn: "Complete video game levels and earn rewards.",
    rewardAvatarId: "weekly_videogames",
  },
  {
    categoryId: "libros", title: "Books Week",
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
      title: chosen.title,
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

  const weekId = String(request.data?.weekId || "");
  const categoryId = String(request.data?.categoryId || "");
  const rawAnswers = Array.isArray(request.data?.answers) ?
    request.data.answers : [];

  if (
    !weekId || !categoryId || rawAnswers.length === 0 ||
    rawAnswers.length > WEEKLY_TOPIC_ROUND_SIZE
  ) {
    throw new HttpsError("invalid-argument", "Invalid round submission.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();
  if (
    !topicData || String(topicData.weekId || "") !== weekId ||
    String(topicData.categoryId || "") !== categoryId
  ) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
    );
  }

  type RoundAnswer = {
    difficulty: number; questionId: string; selectedIndex: number;
  };

  const answers: RoundAnswer[] = rawAnswers.map(
    (a: Record<string, unknown>): RoundAnswer => ({
      difficulty: safeInt(a?.sourceDifficulty, 0),
      questionId: String(a?.sourceQuestionId || ""),
      selectedIndex: safeInt(a?.selectedIndex, -1),
    })
  ).filter((a: RoundAnswer) =>
    a.questionId && [1, 2, 3].includes(a.difficulty)
  );

  if (answers.length === 0) {
    throw new HttpsError("invalid-argument", "No valid answers submitted.");
  }

  const questionSnaps = await Promise.all(answers.map((a) =>
    db.collection("fixed_pools").doc(categoryId)
      .collection(`difficulty_${a.difficulty}`).doc("pool")
      .collection("questions").doc(a.questionId).get()
  ));

  let correct = 0;
  const answeredQuestionIds: string[] = [];

  answers.forEach((a, i) => {
    const data = questionSnaps[i].data();
    if (!data) return;

    answeredQuestionIds.push(a.questionId);
    const correctIndex = safeInt(data.answerIndex ?? data.correctIndex, -1);
    if (a.selectedIndex === correctIndex) correct++;
  });

  const totalAnswered = answeredQuestionIds.length;

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(participationRef);
    const data = snap.data() || {};

    const newCorrectAnswers = safeInt(data.correctAnswers, 0) + correct;
    const newTotalAnswered = safeInt(data.totalAnswered, 0) + totalAnswered;

    const usedQuestionIds = new Set<string>(
      ((data.usedQuestionIds as unknown[]) || []).map((e) => String(e))
    );
    answeredQuestionIds.forEach((id) => usedQuestionIds.add(id));

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

  const weekId = String(request.data?.weekId || "");
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
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

  const weekId = String(request.data?.weekId || "");
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
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

export const acceptFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const requesterUid = String(request.data?.requesterUid || "");
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
      throw new HttpsError("not-found", "That player no longer exists.");
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

  const requesterUid = String(request.data?.requesterUid || "");
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

  const friendUid = String(request.data?.friendUid || "");
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
