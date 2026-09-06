/**
 * `firestore.rules` sobre lo que un cliente modificado podría falsear.
 *
 * Cada caso de aquí corresponde a un agujero que las reglas ya cerraron —
 * los comentarios de `firestore.rules` los describen uno por uno: un
 * jugador reescribiendo las preguntas a mitad de partida, otro
 * auto-declarándose ganador, otro fabricando su entrada en el ranking. Sin
 * tests, aflojar cualquiera de esas líneas no rompe nada visible: el juego
 * sigue funcionando, solo que se puede hacer trampa.
 *
 * Distinto de `users.test.js`, que cubre la cuenta propia. Esto cubre lo
 * compartido: rankings, partidas, el contador de gasto en IA y el banco de
 * preguntas.
 */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, deleteDoc} = require("firebase/firestore");

const YO = "jugador";
const RIVAL = "rival";
const AJENO = "mirón";

let env;

const como = (uid) => env.authenticatedContext(uid).firestore();

async function sembrar(ruta, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), ...ruta), data);
  });
}

/** Una partida en curso entre YO y RIVAL. */
function partida(extra = {}) {
  return {
    hostUid: YO,
    guestUid: RIVAL,
    winReward: 2,
    questions: [{q: "¿2+2?", options: ["3", "4", "5", "6"], answerIndex: 1}],
    winnerUid: null,
    finishReason: null,
    rewarded: false,
    players: {
      [YO]: {ready: true, answers: [], score: 0, finished: false},
      [RIVAL]: {ready: true, answers: [], score: 0, finished: false},
    },
    ...extra,
  };
}

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-triviaia",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "firestore.rules"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

// Serial a propósito (ver `--test-concurrency=1` en package.json): los dos
// archivos comparten un emulador, y en paralelo el `clearFirestore` de uno
// borraba los datos sembrados por el otro a media prueba. Salían fallos
// intermitentes, que es peor que no tener test.
test.beforeEach(async () => env.clearFirestore());
test.after(async () => env && env.cleanup());

test("rankings", async (t) => {
  await t.test("nadie escribe en el ranking diario", async () => {
    // Lo llena submitDailyChallengeResult con el Admin SDK. Si el cliente
    // pudiera escribir, publicaría el puntaje que quisiera.
    await assertFails(
      setDoc(doc(como(YO), "daily_leaderboards", "2026-09-06", "players", YO), {
        score: 999,
        username: "Yo",
      })
    );
  });

  await t.test("el ranking diario sí se lee", async () => {
    await sembrar(["daily_leaderboards", "2026-09-06", "players", RIVAL], {
      score: 10,
    });
    await assertSucceeds(
      getDoc(doc(como(YO), "daily_leaderboards", "2026-09-06", "players", RIVAL))
    );
  });

  await t.test("no puede inflar su puntaje semanal", async () => {
    // weeklyScore decide el pago de la temporada.
    await sembrar(["weekly_leagues", "2026-09-01", "bronze", YO], {
      weeklyScore: 10,
      username: "Yo",
    });

    await assertFails(
      setDoc(
        doc(como(YO), "weekly_leagues", "2026-09-01", "bronze", YO),
        {weeklyScore: 99999},
        {merge: true}
      )
    );
  });

  await t.test("sí puede actualizar su nombre en el ranking", async () => {
    await sembrar(["weekly_leagues", "2026-09-01", "bronze", YO], {
      weeklyScore: 10,
      username: "Yo",
    });

    await assertSucceeds(
      setDoc(
        doc(como(YO), "weekly_leagues", "2026-09-01", "bronze", YO),
        {username: "Nuevo", displayName: "Nuevo"},
        {merge: true}
      )
    );
  });

  await t.test("no puede tocar la fila de otro jugador", async () => {
    await sembrar(["weekly_leagues", "2026-09-01", "bronze", RIVAL], {
      weeklyScore: 500,
      username: "Rival",
    });

    await assertFails(
      setDoc(
        doc(como(YO), "weekly_leagues", "2026-09-01", "bronze", RIVAL),
        {username: "hackeado"},
        {merge: true}
      )
    );
  });
});

test("partidas 1v1", async (t) => {
  await t.test("un tercero no puede ni leerla", async () => {
    await sembrar(["matches", "m1"], partida());
    await assertFails(getDoc(doc(como(AJENO), "matches", "m1")));
  });

  await t.test("los dos jugadores sí la leen", async () => {
    await sembrar(["matches", "m1"], partida());
    await assertSucceeds(getDoc(doc(como(YO), "matches", "m1")));
    await assertSucceeds(getDoc(doc(como(RIVAL), "matches", "m1")));
  });

  await t.test("puede escribir sus propias respuestas", async () => {
    await sembrar(["matches", "m1"], partida());
    const p = partida().players;

    await assertSucceeds(
      setDoc(
        doc(como(YO), "matches", "m1"),
        {players: {...p, [YO]: {...p[YO], answers: [1], score: 1}}},
        {merge: true}
      )
    );
  });

  // El agujero: puntuar se hace desde `players.{uid}.answers`, así que
  // reescribir las del rival era un modo verificado de ganar.
  await t.test("no puede reescribir las respuestas del rival", async () => {
    await sembrar(["matches", "m1"], partida());
    const p = partida().players;

    await assertFails(
      setDoc(
        doc(como(YO), "matches", "m1"),
        {players: {...p, [RIVAL]: {...p[RIVAL], answers: [0], score: 0}}},
        {merge: true}
      )
    );
  });

  // El otro agujero: cambiar las preguntas por otras cuya respuesta ya sabe.
  await t.test("no puede cambiar las preguntas a mitad de partida", async () => {
    await sembrar(["matches", "m1"], partida());

    await assertFails(
      setDoc(
        doc(como(YO), "matches", "m1"),
        {questions: [{q: "fácil", options: ["a", "b", "c", "d"], answerIndex: 0}]},
        {merge: true}
      )
    );
  });

  await t.test("no puede declararse ganador", async () => {
    await sembrar(["matches", "m1"], partida());

    await assertFails(
      setDoc(
        doc(como(YO), "matches", "m1"),
        {winnerUid: YO, finishReason: "opponent_left"},
        {merge: true}
      )
    );
  });

  await t.test("no puede marcarse como ya recompensado", async () => {
    await sembrar(["matches", "m1"], partida());
    await assertFails(
      setDoc(doc(como(YO), "matches", "m1"), {rewarded: true}, {merge: true})
    );
  });

  await t.test("no puede crear una partida con premio inflado", async () => {
    await assertFails(
      setDoc(doc(como(YO), "matches", "m2"), partida({winReward: 500}))
    );
  });
});

test("contadores y contenido del servidor", async (t) => {
  // ai_usage es el medidor del gasto real en Anthropic. Poder resetearlo
  // sería poder gastar sin tope.
  await t.test("no puede leer ni resetear el medidor de gasto IA", async () => {
    await sembrar(["ai_usage", "2026-09-06"], {levels: 4999});

    await assertFails(getDoc(doc(como(YO), "ai_usage", "2026-09-06")));
    await assertFails(
      setDoc(doc(como(YO), "ai_usage", "2026-09-06"), {levels: 0})
    );
  });

  await t.test("el banco de preguntas es de solo lectura", async () => {
    await sembrar(
      ["fixed_pools", "ciencia", "difficulty_1", "pool", "questions", "q1"],
      {q: "¿?", options: ["a", "b", "c", "d"], answerIndex: 2}
    );

    await assertSucceeds(
      getDoc(
        doc(
          como(YO),
          "fixed_pools", "ciencia", "difficulty_1", "pool", "questions", "q1"
        )
      )
    );

    // Poder escribir aquí sería poder ponerse preguntas con respuesta
    // conocida, o corromper el banco de todos los jugadores.
    await assertFails(
      setDoc(
        doc(
          como(YO),
          "fixed_pools", "ciencia", "difficulty_1", "pool", "questions", "q1"
        ),
        {q: "¿?", options: ["a", "b", "c", "d"], answerIndex: 0}
      )
    );
  });

  await t.test("el tema semanal no lo escribe el cliente", async () => {
    // Lleva rewardCoins: escribirlo sería fijarse la recompensa.
    await sembrar(["weekly_topics", "current"], {
      categoryId: "arte",
      rewardCoins: 10,
    });

    await assertFails(
      setDoc(
        doc(como(YO), "weekly_topics", "current"),
        {rewardCoins: 9999},
        {merge: true}
      )
    );
  });

  await t.test("no puede borrar el tema semanal", async () => {
    await sembrar(["weekly_topics", "current"], {categoryId: "arte"});
    await assertFails(deleteDoc(doc(como(YO), "weekly_topics", "current")));
  });
});
