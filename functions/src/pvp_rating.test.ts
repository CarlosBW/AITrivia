import {test} from "node:test";
import assert from "node:assert";

import {
  PVP_LEAGUES,
  DEFAULT_RATING,
  K_FACTOR,
  RATING_FLOOR,
  RATING_CEILING,
  leagueForRating,
  leagueRank,
  bestLeaguePatch,
  calculateRatings,
} from "./pvp_rating";

/**
 * Esto decide el rating de cada jugador, su liga y —a través de la liga— lo
 * que cobra al cerrar la temporada. Estuvo dentro de `index.ts` sin una
 * sola prueba: un signo cambiado habría repartido rating al revés durante
 * días sin que nada fallara de forma visible.
 */

test("calculateRatings: quien gana sube y quien pierde baja", () => {
  const {newA, newB} = calculateRatings({
    playerARating: 1000,
    playerBRating: 1000,
    playerAScore: 8,
    playerBScore: 3,
  });

  assert.ok(newA > 1000, `A debería subir, quedó en ${newA}`);
  assert.ok(newB < 1000, `B debería bajar, quedó en ${newB}`);
});

test("calculateRatings: entre iguales se reparte medio K", () => {
  // Con el mismo rating la expectativa es 0.5, así que ganar vale K/2.
  const {newA, newB} = calculateRatings({
    playerARating: 1200,
    playerBRating: 1200,
    playerAScore: 10,
    playerBScore: 0,
  });

  assert.strictEqual(newA, 1200 + K_FACTOR / 2);
  assert.strictEqual(newB, 1200 - K_FACTOR / 2);
});

test("calculateRatings: el empate no mueve a dos iguales", () => {
  const {newA, newB} = calculateRatings({
    playerARating: 1500,
    playerBRating: 1500,
    playerAScore: 5,
    playerBScore: 5,
  });

  assert.strictEqual(newA, 1500);
  assert.strictEqual(newB, 1500);
});

test("calculateRatings: es de suma cero", () => {
  // Lo que gana uno lo pierde el otro; si no, el rating del sistema se
  // infla solo y las ligas dejan de significar nada con el tiempo.
  for (const [ra, rb] of [[1000, 1000], [1400, 1100], [900, 1800]]) {
    const {newA, newB} = calculateRatings({
      playerARating: ra,
      playerBRating: rb,
      playerAScore: 7,
      playerBScore: 2,
    });

    assert.strictEqual(
      newA - ra + (newB - rb),
      0,
      `no suma cero partiendo de ${ra}/${rb}`
    );
  }
});

test("calculateRatings: ganar al favorito paga más", () => {
  const sorpresa = calculateRatings({
    playerARating: 1000,
    playerBRating: 1800,
    playerAScore: 6,
    playerBScore: 4,
  });

  const esperado = calculateRatings({
    playerARating: 1800,
    playerBRating: 1000,
    playerAScore: 6,
    playerBScore: 4,
  });

  assert.ok(
    sorpresa.newA - 1000 > esperado.newA - 1800,
    "batir a alguien muy superior debería dar más rating"
  );
});

test("calculateRatings: el empate favorece al peor clasificado", () => {
  const {newA, newB} = calculateRatings({
    playerARating: 1000,
    playerBRating: 1600,
    playerAScore: 5,
    playerBScore: 5,
  });

  assert.ok(newA > 1000, "el de menos rating debería subir al empatar");
  assert.ok(newB < 1600, "el favorito debería bajar al empatar");
});

test("calculateRatings: no baja del suelo ni pasa del techo", () => {
  const suelo = calculateRatings({
    playerARating: RATING_FLOOR,
    playerBRating: 5000,
    playerAScore: 0,
    playerBScore: 10,
  });
  assert.ok(suelo.newA >= RATING_FLOOR);

  const techo = calculateRatings({
    playerARating: RATING_CEILING,
    playerBRating: 100,
    playerAScore: 10,
    playerBScore: 0,
  });
  assert.ok(techo.newA <= RATING_CEILING);
});

test("leagueForRating: los bordes caen del lado correcto", () => {
  // Un borde mal puesto deja a un jugador en la liga de abajo cobrando de
  // menos al cerrar la temporada.
  assert.strictEqual(leagueForRating(0).id, "bronze");
  assert.strictEqual(leagueForRating(999).id, "bronze");
  assert.strictEqual(leagueForRating(1000).id, "silver");
  assert.strictEqual(leagueForRating(1199).id, "silver");
  assert.strictEqual(leagueForRating(1200).id, "gold");
  assert.strictEqual(leagueForRating(1399).id, "gold");
  assert.strictEqual(leagueForRating(1400).id, "platinum");
  assert.strictEqual(leagueForRating(1599).id, "platinum");
  assert.strictEqual(leagueForRating(1600).id, "diamond");
  assert.strictEqual(leagueForRating(1899).id, "diamond");
  assert.strictEqual(leagueForRating(1900).id, "master");
});

test("leagueForRating: fuera de rango no se queda sin liga", () => {
  assert.strictEqual(leagueForRating(-500).id, "bronze");
  assert.strictEqual(leagueForRating(999999).id, "master");
});

test("leagueForRating: el rating inicial cae en plata", () => {
  // Es el valor que `firestore.rules` fija al crear la cuenta.
  assert.strictEqual(leagueForRating(DEFAULT_RATING).id, "silver");
});

test("las ligas cubren el rango sin huecos ni solapes", () => {
  for (let i = 1; i < PVP_LEAGUES.length; i++) {
    assert.strictEqual(
      PVP_LEAGUES[i].minRating,
      PVP_LEAGUES[i - 1].maxRating + 1,
      `hueco o solape entre ${PVP_LEAGUES[i - 1].id} y ${PVP_LEAGUES[i].id}`
    );
  }
});

test("el techo del rating coincide con el de la última liga", () => {
  // Si no, un rating alcanzable quedaría fuera de toda liga.
  assert.strictEqual(
    PVP_LEAGUES[PVP_LEAGUES.length - 1].maxRating,
    RATING_CEILING
  );
});

test("leagueRank: ordena de peor a mejor", () => {
  assert.ok(leagueRank("master") > leagueRank("bronze"));
  assert.ok(leagueRank("gold") > leagueRank("silver"));
  assert.strictEqual(leagueRank("no-existe"), -1);
});

test("bestLeaguePatch: solo sube, nunca baja", () => {
  const oro = leagueForRating(1250);

  // Alguien que llegó a oro y cayó a plata conserva su mejor liga.
  assert.deepStrictEqual(
    bestLeaguePatch({bestLeagueId: "master"}, oro),
    {},
    "no debería rebajar la mejor liga alcanzada"
  );

  const patch = bestLeaguePatch({bestLeagueId: "silver"}, oro);
  assert.strictEqual(patch.bestLeagueId, "gold");
  assert.strictEqual(patch.bestLeagueColorValue, oro.colorValue);
});

test("bestLeaguePatch: la misma liga no genera escritura", () => {
  assert.deepStrictEqual(
    bestLeaguePatch({bestLeagueId: "gold"}, leagueForRating(1250)),
    {}
  );
});

test("bestLeaguePatch: sin mejor liga previa acepta cualquiera", () => {
  // Una cuenta recién creada no trae `bestLeagueId`; `leagueRank` devuelve
  // -1 para el vacío, así que cualquier liga real gana.
  const patch = bestLeaguePatch({}, leagueForRating(0));
  assert.strictEqual(patch.bestLeagueId, "bronze");
});

test("bestLeaguePatch: cae a pvpLeagueId si no hay bestLeagueId", () => {
  assert.deepStrictEqual(
    bestLeaguePatch({pvpLeagueId: "diamond"}, leagueForRating(1250)),
    {}
  );
});
