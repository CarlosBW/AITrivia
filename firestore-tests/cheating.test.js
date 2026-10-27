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
const {
  doc, getDoc, setDoc, deleteDoc, updateDoc, serverTimestamp,
} = require("firebase/firestore");

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

  await t.test("sí puede poner en el ranking lo que lleva su perfil",
    async () => {
      await sembrar(["users", YO], {
        username: "Nuevo", displayName: "Nuevo",
        avatarId: "avatar_2", equippedFrame: "silver",
      });
      await sembrar(["weekly_leagues", "2026-09-01", "bronze", YO], {
        weeklyScore: 10,
        username: "Yo",
      });

      await assertSucceeds(
        setDoc(
          doc(como(YO), "weekly_leagues", "2026-09-01", "bronze", YO),
          {
            username: "Nuevo", displayName: "Nuevo",
            avatarId: "avatar_2", equippedFrame: "silver",
          },
          {merge: true}
        )
      );
    });

  // Antes aceptaba cualquier cosa: un marco o avatar no desbloqueado se
  // lucía en el ranking.
  await t.test("no puede lucir en el ranking lo que su perfil no lleva",
    async () => {
      await sembrar(["users", YO], {
        username: "Yo", displayName: "Yo",
        avatarId: "avatar_2", equippedFrame: "silver",
      });
      await sembrar(["weekly_leagues", "2026-09-01", "bronze", YO], {
        weeklyScore: 10, username: "Yo",
      });
      const fila = doc(como(YO), "weekly_leagues", "2026-09-01", "bronze", YO);

      await assertFails(setDoc(fila, {equippedFrame: "master"}, {merge: true}));
      await assertFails(
        setDoc(fila, {avatarId: "avatar_pvp_master"}, {merge: true})
      );
      await assertFails(setDoc(fila, {username: "Otro"}, {merge: true}));
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

  // Responder pasa por submitLiveMatchAnswer, que juzga contra el reloj y
  // la clave del servidor. Escribir las propias respuestas directamente era
  // poder ponerse las correctas.
  await t.test("no puede escribir sus propias respuestas", async () => {
    await sembrar(["matches", "m1"], partida());
    const p = partida().players;

    await assertFails(
      setDoc(
        doc(como(YO), "matches", "m1"),
        {players: {...p, [YO]: {...p[YO], answers: [1], score: 1}}},
        {merge: true}
      )
    );
  });

  await t.test("no puede marcarse listo ni empezar la partida", async () => {
    await sembrar(["matches", "m1"], partida({status: "waiting"}));
    await assertFails(
      setDoc(doc(como(YO), "matches", "m1"), {status: "playing"}, {merge: true})
    );
  });

  await t.test("no puede volver ranked una partida casual", async () => {
    await sembrar(["matches", "m1"], partida({ranked: false}));
    await assertFails(
      setDoc(doc(como(YO), "matches", "m1"),
        {ranked: true, affectsPvpRating: true}, {merge: true})
    );
  });

  // La clave de respuestas vive aparte para que ningún jugador la lea antes
  // de que la partida termine.
  await t.test("nadie lee la clave de respuestas", async () => {
    await sembrar(["matches", "m1"], partida());
    await sembrar(["matches", "m1", "secret", "answers"], {answerIndices: [1]});
    await assertFails(
      getDoc(doc(como(YO), "matches", "m1", "secret", "answers"))
    );
    await sembrar(["async_matches", "a1"], {
      challengerUid: YO, challengedUid: RIVAL,
    });
    await sembrar(["async_matches", "a1", "secret", "answers"],
      {answerIndices: [1]});
    await assertFails(
      getDoc(doc(como(YO), "async_matches", "a1", "secret", "answers"))
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

  // Ni siquiera una normal: con el rival que quisiera y sus propias
  // preguntas, era un modo de bajarle el rating a cualquiera.
  await t.test("no puede crear ninguna partida", async () => {
    await assertFails(setDoc(doc(como(YO), "matches", "m3"), partida()));
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

  await t.test("el banco de preguntas no se lee ni se escribe", async () => {
    await sembrar(
      ["fixed_pools", "ciencia", "difficulty_1", "pool", "questions", "q1"],
      {q: "¿?", options: ["a", "b", "c", "d"], answerIndex: 2}
    );

    // Cada pregunta lleva su answerIndex: leer el banco era descargar
    // todas las respuestas. Las partidas reciben solo sus preguntas desde
    // el servidor.
    await assertFails(
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

  await t.test("las preguntas de los temas IA no se leen", async () => {
    await sembrar(["ai_topic_pool", "pool1"], {status: "ready", usageCount: 9});
    await sembrar(
      ["ai_topic_pool", "pool1", "levels", "level_1", "questions", "q1"],
      {q: "¿?", options: ["a", "b", "c", "d"], answerIndex: 1}
    );

    // El tema en sí sí: la lista de temas populares lo muestra.
    await assertSucceeds(getDoc(doc(como(YO), "ai_topic_pool", "pool1")));
    await assertFails(
      getDoc(
        doc(
          como(YO),
          "ai_topic_pool", "pool1", "levels", "level_1", "questions", "q1"
        )
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

test("invitaciones en vivo", async (t) => {
  const invitacion = (extra = {}) => ({
    fromUid: YO, toUid: RIVAL, fromName: "Yo", toName: "Rival",
    status: "pending", ...extra,
  });

  await t.test("las dos partes la leen", async () => {
    await sembrar(["realtime_invites", "i1"], invitacion());
    await assertSucceeds(getDoc(doc(como(YO), "realtime_invites", "i1")));
    await assertSucceeds(getDoc(doc(como(RIVAL), "realtime_invites", "i1")));
    await assertFails(getDoc(doc(como(AJENO), "realtime_invites", "i1")));
  });

  // Antes cualquiera mandaba invitaciones sin límite, con el nombre que
  // quisiera, y cualquiera de las dos partes reescribía cualquier campo.
  await t.test("el cliente no crea ni reescribe invitaciones", async () => {
    await assertFails(setDoc(doc(como(YO), "realtime_invites", "i2"),
      invitacion({fromName: "Soporte oficial"})));
    await sembrar(["realtime_invites", "i1"], invitacion());
    await assertFails(setDoc(doc(como(RIVAL), "realtime_invites", "i1"),
      {status: "accepted", toUid: AJENO}, {merge: true}));
  });
});

test("rechazar un reto por turnos", async (t) => {
  /** Un reto que YO lancé a RIVAL y que RIVAL todavía no empezó. */
  function reto(extra = {}) {
    return {
      challengerUid: YO,
      challengedUid: RIVAL,
      status: "waiting_challenged",
      challengerStatus: "finished",
      challengedStatus: "pending",
      challenger: {score: 3, answers: {"0": 1}},
      challenged: {score: 0},
      ...extra,
    };
  }
  const rechazo = (uid) => ({
    status: "declined",
    declinedByUid: uid,
    declinedAt: serverTimestamp(),
    lastUpdatedAt: serverTimestamp(),
  });

  await t.test("el retado puede rechazarlo antes de jugar", async () => {
    await sembrar(["async_matches", "r1"], reto());
    await assertSucceeds(
      updateDoc(doc(como(RIVAL), "async_matches", "r1"), rechazo(RIVAL))
    );
  });

  // Rechazar a mitad de partida era una forma de esquivar una derrota.
  await t.test("no una vez que empezó a jugar", async () => {
    await sembrar(["async_matches", "r1"], reto({
      challenged: {score: 0, deadlines: {"0": 123}},
    }));
    await assertFails(
      updateDoc(doc(como(RIVAL), "async_matches", "r1"), rechazo(RIVAL))
    );
  });

  // El que lanzó el reto ya jugó: anularlo sería borrar su derrota.
  await t.test("quien lanzó el reto no puede anularlo", async () => {
    await sembrar(["async_matches", "r1"], reto());
    await assertFails(
      updateDoc(doc(como(YO), "async_matches", "r1"), rechazo(YO))
    );
  });

  await t.test("no uno que ya terminó", async () => {
    await sembrar(["async_matches", "r1"], reto({
      status: "completed", challengedStatus: "finished",
    }));
    await assertFails(
      updateDoc(doc(como(RIVAL), "async_matches", "r1"), rechazo(RIVAL))
    );
  });
});

test("solicitudes de amistad", async (t) => {
  // El cliente escribía la solicitud directo en la bandeja del otro: con
  // cualquier nombre, y podía devolver una rechazada a "pending" para
  // volver a notificarle. Ahora solo lo hace sendFriendRequest.
  await t.test("no se escribe en la bandeja de otro jugador", async () => {
    await assertFails(
      setDoc(doc(como(YO), "users", RIVAL, "friend_requests", YO), {
        requesterUid: YO, requesterDisplayName: "Cualquier cosa",
        status: "pending",
      })
    );
  });

  await t.test("no se reabre una solicitud rechazada", async () => {
    await sembrar(["users", RIVAL, "friend_requests", YO],
      {requesterUid: YO, status: "rejected"});
    await assertFails(
      updateDoc(doc(como(YO), "users", RIVAL, "friend_requests", YO),
        {status: "pending"})
    );
  });

  await t.test("tampoco la lista propia de enviadas", async () => {
    await assertFails(
      setDoc(doc(como(YO), "users", YO, "sent_friend_requests", RIVAL),
        {targetUid: RIVAL, status: "pending"})
    );
  });

  await t.test("ambos pueden leer la solicitud", async () => {
    await sembrar(["users", RIVAL, "friend_requests", YO],
      {requesterUid: YO, status: "pending"});
    await assertSucceeds(
      getDoc(doc(como(YO), "users", RIVAL, "friend_requests", YO))
    );
    await assertSucceeds(
      getDoc(doc(como(RIVAL), "users", RIVAL, "friend_requests", YO))
    );
  });
});

test("las respuestas de los modos individuales", async (t) => {
  // Las preguntas de Solo, Reto diario y Tema de la semana llegan sin la
  // respuesta; la clave vive aparte y solo la lee el servidor, que juzga
  // cada respuesta.
  const claves = [
    ["users", YO, "sessions_fixed", "cine_1", "secret", "answers"],
    ["users", YO, "sessions_ai", "t1_1", "secret", "answers"],
    ["users", YO, "daily_challenges", "2026-10-22", "secret", "answers"],
    ["users", YO, "weekly_rounds", "current", "secret", "answers"],
    ["users", YO, "weekly_rounds", "current"],
  ];
  for (const ruta of claves) {
    await t.test(`no se lee ${ruta.slice(2).join("/")}`, async () => {
      await sembrar(ruta, {answerIndices: [1, 2, 0]});
      await assertFails(getDoc(doc(como(YO), ...ruta)));
    });
  }

  await t.test("la sesión propia sí se lee", async () => {
    await sembrar(["users", YO, "sessions_fixed", "cine_1"],
      {questions: [{q: "¿?", options: ["a", "b"]}]});
    await assertSucceeds(
      getDoc(doc(como(YO), "users", YO, "sessions_fixed", "cine_1"))
    );
  });
});

test("bloqueos y reportes de jugadores", async (t) => {
  // Bloquear y reportar pasan por Cloud Functions (blockPlayer,
  // reportPlayer): un bloqueo escrito desde la app podría apuntar a
  // cualquiera, y un reporte, inventar su contenido.
  await t.test("cada uno lee su propia lista de bloqueados", async () => {
    await sembrar(["users", YO, "blocked", RIVAL], {uid: RIVAL});
    await assertSucceeds(getDoc(doc(como(YO), "users", YO, "blocked", RIVAL)));
  });

  await t.test("nadie lee la lista de otro", async () => {
    await sembrar(["users", YO, "blocked", RIVAL], {uid: RIVAL});
    await assertFails(getDoc(doc(como(RIVAL), "users", YO, "blocked", RIVAL)));
  });

  await t.test("ni siquiera el dueño la escribe", async () => {
    await assertFails(
      setDoc(doc(como(YO), "users", YO, "blocked", RIVAL), {uid: RIVAL})
    );
  });

  await t.test("los reportes no se leen ni se escriben", async () => {
    const ruta = ["player_reports", `${YO}__${RIVAL}`];
    await assertFails(setDoc(doc(como(YO), ...ruta), {reason: "other"}));
    await sembrar(ruta, {reporterUid: YO, targetUid: RIVAL});
    await assertFails(getDoc(doc(como(YO), ...ruta)));
    await assertFails(getDoc(doc(como(RIVAL), ...ruta)));
  });
});
