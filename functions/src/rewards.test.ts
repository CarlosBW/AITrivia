import {test} from "node:test";
import assert from "node:assert";

import {
  SOLO_PERFECT_LEVEL_COINS,
  SOLO_GREAT_LEVEL_COINS,
  SOLO_GOOD_LEVEL_COINS,
  DAILY_STREAK_3_DAYS_COINS,
  DAILY_STREAK_7_DAYS_COINS,
  DAILY_STREAK_14_DAYS_COINS,
  xpRequiredForLevel,
  levelForXp,
  calculateLevelRewards,
  calculateDailyCoinsEarned,
  calculateDailyXpEarned,
  calculateDailyScore,
  calculateDailyStreakBonusCoins,
} from "./rewards";

/**
 * Estas funciones deciden lo que cobra el jugador. Las pruebas apuntan a
 * propiedades —monotonía, bordes, terminación— y no a repetir la
 * aritmética: repetirla solo comprobaría que sé copiar una fórmula, y
 * pasaría igual con la fórmula equivocada.
 */

// --- Solo ---

test("solo: los umbrales caen del lado correcto", () => {
  // 90/70/40% son bordes: un `>` en vez de `>=` cambia el pago de miles de
  // partidas sin romper nada visible.
  const monedas = (c: number) => calculateLevelRewards(c, 10).coins;

  assert.strictEqual(monedas(9), SOLO_PERFECT_LEVEL_COINS);
  assert.strictEqual(monedas(8), SOLO_GREAT_LEVEL_COINS);
  assert.strictEqual(monedas(7), SOLO_GREAT_LEVEL_COINS);
  assert.strictEqual(monedas(6), SOLO_GOOD_LEVEL_COINS);
  assert.strictEqual(monedas(4), SOLO_GOOD_LEVEL_COINS);
  assert.strictEqual(monedas(3), 0);
});

test("solo: acertar más nunca paga menos", () => {
  // Un pago no monótono es un bug que solo se ve en agregado: nadie
  // reporta "acerté una más y me dieron menos", pero pasa.
  for (const total of [5, 10, 20]) {
    let previo = -1;
    for (let correct = 0; correct <= total; correct++) {
      const {coins, xp} = calculateLevelRewards(correct, total);
      assert.ok(
        coins >= previo,
        `${correct}/${total} pagó menos que ${correct - 1}`
      );
      assert.strictEqual(xp, correct * 10);
      previo = coins;
    }
  }
});

test("solo: cero preguntas no divide por cero", () => {
  const r = calculateLevelRewards(0, 0);
  assert.strictEqual(r.coins, 0);
  assert.strictEqual(r.xp, 0);
});

test("solo: el perfecto paga más que el bueno", () => {
  assert.ok(SOLO_PERFECT_LEVEL_COINS > SOLO_GREAT_LEVEL_COINS);
  assert.ok(SOLO_GREAT_LEVEL_COINS > SOLO_GOOD_LEVEL_COINS);
  assert.ok(SOLO_GOOD_LEVEL_COINS > 0);
});

// --- Reto diario ---

test("diario: las monedas van por bloques completos de 10", () => {
  assert.strictEqual(calculateDailyCoinsEarned(0), 0);
  assert.strictEqual(calculateDailyCoinsEarned(9), 0);
  assert.strictEqual(calculateDailyCoinsEarned(10), 5);
  assert.strictEqual(calculateDailyCoinsEarned(19), 5);
  assert.strictEqual(calculateDailyCoinsEarned(20), 10);
});

test("diario: acertar más nunca paga menos", () => {
  let previo = -1;
  for (let correct = 0; correct <= 60; correct++) {
    const coins = calculateDailyCoinsEarned(correct);
    assert.ok(
      coins >= previo,
      `${correct} aciertos pagaron menos que ${correct - 1}`
    );
    previo = coins;
  }
});

test("diario: el XP premia participar y no fallar ninguna", () => {
  // Sin jugar, nada.
  assert.strictEqual(calculateDailyXpEarned(0, 0), 0);

  // Participar vale 5 aunque falles todas.
  assert.strictEqual(calculateDailyXpEarned(0, 10), 5);

  const conFallo = calculateDailyXpEarned(9, 10);
  const pleno = calculateDailyXpEarned(10, 10);
  assert.strictEqual(
    pleno - conFallo,
    2 + 5,
    "el pleno debería sumar el bonus"
  );
});

test("diario: el puntaje sube con aciertos y con racha", () => {
  const base = calculateDailyScore(5, 10, 0);
  assert.ok(calculateDailyScore(6, 10, 0) > base, "más aciertos, más puntaje");
  assert.ok(calculateDailyScore(5, 10, 5) > base, "más racha, más puntaje");
});

test("diario: la racha deja de sumar puntaje a los 30 días", () => {
  // El tope existe para que una racha muy larga no aplaste el ranking.
  assert.strictEqual(
    calculateDailyScore(5, 10, 30),
    calculateDailyScore(5, 10, 300)
  );
});

test("diario: cero respondidas no divide por cero", () => {
  assert.strictEqual(calculateDailyScore(0, 0, 0), 0);
});

test("diario: los hitos de racha pagan el mayor que aplique", () => {
  assert.strictEqual(calculateDailyStreakBonusCoins(0), 0);
  assert.strictEqual(calculateDailyStreakBonusCoins(1), 0);
  const bono = calculateDailyStreakBonusCoins;

  assert.strictEqual(bono(3), DAILY_STREAK_3_DAYS_COINS);
  assert.strictEqual(bono(7), DAILY_STREAK_7_DAYS_COINS);
  assert.strictEqual(bono(14), DAILY_STREAK_14_DAYS_COINS);

  // 21 es múltiplo de 3 y de 7: debe pagar el de 7, no el de 3.
  assert.strictEqual(bono(21), DAILY_STREAK_7_DAYS_COINS);
  // 42 lo es de 3, 7 y 14: paga el de 14.
  assert.strictEqual(bono(42), DAILY_STREAK_14_DAYS_COINS);
});

// --- Nivel del jugador ---

test("nivel: la curva nunca pide menos de 100 XP", () => {
  // Es lo que garantiza que `levelForXp` termine: cada vuelta descuenta
  // al menos 100.
  for (let level = 1; level <= 200; level++) {
    assert.ok(
      xpRequiredForLevel(level) >= 100,
      `el nivel ${level} pide ${xpRequiredForLevel(level)}`
    );
  }
});

test("nivel: la curva no baja al avanzar", () => {
  for (let level = 2; level <= 200; level++) {
    assert.ok(
      xpRequiredForLevel(level) >= xpRequiredForLevel(level - 1),
      `el nivel ${level} pide menos que el ${level - 1}`
    );
  }
});

test("nivel: es la inversa de la curva", () => {
  // Justo el XP acumulado para llegar al nivel N debe dar N; uno menos,
  // N-1.
  let acumulado = 0;
  for (let level = 1; level <= 60; level++) {
    assert.strictEqual(levelForXp(acumulado), level, `en el nivel ${level}`);
    acumulado += xpRequiredForLevel(level);
    assert.strictEqual(
      levelForXp(acumulado - 1),
      level,
      `justo antes de ${level + 1}`
    );
  }
});

test("nivel: empieza en 1 y nunca retrocede", () => {
  assert.strictEqual(levelForXp(0), 1);

  let previo = 0;
  for (let xp = 0; xp <= 50000; xp += 137) {
    const nivel = levelForXp(xp);
    assert.ok(nivel >= previo, `el XP ${xp} bajó de nivel`);
    previo = nivel;
  }
});

// El bucle no tiene cota y corre dentro de una transacción de Firestore en
// cada resultado de Solo y de Diario. Un dato corrupto no puede colgarlo.
test("nivel: termina con entradas absurdas", () => {
  assert.strictEqual(levelForXp(-1), 1);
  assert.strictEqual(levelForXp(-999999), 1);
  assert.strictEqual(levelForXp(NaN), 1);
  assert.strictEqual(levelForXp(Infinity), 1);
  assert.ok(levelForXp(10_000_000) > 1);
});
