/**
 * Lo que paga cada partida: monedas, XP, puntaje y nivel del jugador.
 *
 * Vivía dentro de `index.ts` sin una sola prueba, y casi todo esto es la
 * mitad de un espejo: los comentarios de abajo dicen "Mirrors
 * DailyChallengeService" y "Mirrors player_level_service.dart" porque el
 * cliente calcula lo mismo para enseñarlo antes de que el servidor lo
 * acredite. Ese patrón ya salió caro con las vidas —el cliente cambió de 5
 * a 10 y el servidor se quedó atrás—, y aquí fallaría más callado todavía:
 * la app promete un número y el servidor abona otro. Nadie reporta eso.
 *
 * `economy_sync_test.dart` contrasta estas constantes con las del cliente;
 * `player_level_sync_test.dart` hace lo propio con la curva de nivel.
 */

// --- Solo ---

export const SOLO_PERFECT_LEVEL_COINS = 3;
export const SOLO_GREAT_LEVEL_COINS = 2;
export const SOLO_GOOD_LEVEL_COINS = 1;

// --- Reto diario ---

export const DAILY_COINS_PER_BLOCK = 5;
export const DAILY_CORRECT_PER_COIN_BLOCK = 10;
export const DAILY_STREAK_3_DAYS_COINS = 5;
export const DAILY_STREAK_7_DAYS_COINS = 15;
export const DAILY_STREAK_14_DAYS_COINS = 30;

/**
 * Mirrors lib/services/player_level_service.dart's `xpRequiredForLevel`.
 * @param {number} level Player level.
 * @return {number} XP required to complete that level.
 */
export function xpRequiredForLevel(level: number): number {
  if (level <= 1) return 100;
  return Math.round(100 * (1.18 * (level - 1)));
}

/**
 * Tope del XP que `levelForXp` acepta consumir.
 *
 * No es una cota de juego, es lo que hace que su bucle termine. Descontar
 * el coste de un nivel de un total lo bastante grande no cambia el total:
 * el sumando se pierde en la precisión del double y `remainingXp` se queda
 * clavado para siempre — con `Number.MAX_VALUE` sigue idéntico tras dos
 * millones de vueltas. `Number.isFinite` no cubre este caso, porque
 * `MAX_VALUE` es finito.
 *
 * 1e8 deja el bucle en ~1300 vueltas con toda la aritmética en enteros
 * exactos. Como cota de juego sobra: son ~10 millones de respuestas
 * correctas, muy por encima de cualquier cuenta real.
 */
export const MAX_TOTAL_XP = 100_000_000;

/**
 * Mirrors lib/services/player_level_service.dart's `getLevelInfo` — only
 * the `level` field is needed here.
 *
 * El bucle avanza mientras quede XP por consumir. Termina porque
 * `xpRequiredForLevel` nunca devuelve menos de 100 y porque la entrada
 * viene acotada a `MAX_TOTAL_XP`, así que cada vuelta descuenta de verdad;
 * un XP no finito o negativo sale en la primera comparación con el nivel
 * 1. Corre dentro de una transacción de Firestore en cada resultado de
 * Solo y de Diario, así que no puede depender de que el dato de entrada
 * sea sensato.
 * @param {number} totalXp Player's total XP.
 * @return {number} Player level for that XP total.
 */
export function levelForXp(totalXp: number): number {
  let level = 1;
  let remainingXp = Number.isFinite(totalXp) ?
    Math.min(totalXp, MAX_TOTAL_XP) :
    0;

  for (;;) {
    const needed = xpRequiredForLevel(level);
    if (remainingXp < needed) return level;
    remainingXp -= needed;
    level++;
  }
}

/**
 * Reward math for a single Solo level attempt — fully server-side now,
 * no client-side equivalent to mirror.
 * @param {number} correct Correct answers in this level attempt.
 * @param {number} total Total questions in this level attempt.
 * @return {{xp:number, coins:number}} Reward for this attempt.
 */
export function calculateLevelRewards(
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

/**
 * Mirrors DailyChallengeService's `calculateCoinsEarned`.
 * @param {number} correct Correct answers.
 * @return {number} Coins earned.
 */
export function calculateDailyCoinsEarned(correct: number): number {
  return Math.floor(correct / DAILY_CORRECT_PER_COIN_BLOCK) *
    DAILY_COINS_PER_BLOCK;
}

/**
 * Mirrors DailyChallengeService's `calculateXpEarned`.
 * @param {number} correct Correct answers.
 * @param {number} totalAnswered Total questions answered.
 * @return {number} XP earned.
 */
export function calculateDailyXpEarned(
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
export function calculateDailyScore(
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
export function calculateDailyStreakBonusCoins(streak: number): number {
  if (streak > 0 && streak % 14 === 0) return DAILY_STREAK_14_DAYS_COINS;
  if (streak > 0 && streak % 7 === 0) return DAILY_STREAK_7_DAYS_COINS;
  if (streak > 0 && streak % 3 === 0) return DAILY_STREAK_3_DAYS_COINS;
  return 0;
}
