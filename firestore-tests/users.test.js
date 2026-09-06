/**
 * `firestore.rules` sobre el documento de usuario.
 *
 * Es la regla más cara del repo: decide qué puede escribir el cliente sobre
 * su propia cuenta, y ya rompió el registro en producción dos veces —una
 * porque las vidas iniciales cambiaron de 5 a 10 y la regla seguía fijando
 * los valores viejos, otra por un `pvpRatingDelta: 0` que la regla exige
 * ausente. Las dos se encontraron a mano, con usuarios reales delante.
 *
 * Cada `it` describe una decisión de la regla, no su implementación, para
 * que reescribirla no obligue a reescribir esto.
 */
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

const UID = "jugador";
const OTRO = "otro_jugador";

let env;

/** Lo que `user_bootstrap.dart` escribe al crear una cuenta. */
function nuevoUsuario(extra = {}) {
  return {
    uid: UID,
    username: "Jugador",
    usernameLower: "jugador",
    coins: 0,
    xp: 0,
    pvpRating: 1000,
    pvpLeagueId: "silver",
    bestLeagueId: "silver",
    unlockedAvatars: [
      "avatar_1", "avatar_2", "avatar_3", "avatar_4",
      "avatar_5", "avatar_6", "avatar_7", "avatar_8",
    ],
    lifeUnits: 20,
    maxLifeUnits: 20,
    lifeRegenSeconds: 90,
    loginStreak: 1,
    gamesPlayed: 0,
    correctAnswers: 0,
    wrongAnswers: 0,
    dailyStreak: 0,
    maxDailyStreak: 0,
    bestDailyScore: 0,
    wins1v1: 0,
    losses1v1: 0,
    draws1v1: 0,
    matches1v1: 0,
    currentWinStreak1v1: 0,
    bestWinStreak1v1: 0,
    pvpAbandonCount: 0,
    ...extra,
  };
}

/** Siembra un documento saltándose las reglas, como haría el servidor. */
async function sembrar(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", UID), data);
  });
}

const comoJugador = () => env.authenticatedContext(UID).firestore();

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

test.beforeEach(async () => env.clearFirestore());
test.after(async () => env && env.cleanup());

test("creación de la cuenta", async (t) => {
  await t.test("el alta que hace la app es válida", async () => {
    // Si esto falla, nadie puede registrarse. Es exactamente el fallo que
    // llegó a producción dos veces.
    await assertSucceeds(
      setDoc(doc(comoJugador(), "users", UID), nuevoUsuario())
    );
  });

  await t.test("no puede empezar con monedas", async () => {
    await assertFails(
      setDoc(doc(comoJugador(), "users", UID), nuevoUsuario({coins: 5000}))
    );
  });

  await t.test("no puede fabricarse un rating alto", async () => {
    await assertFails(
      setDoc(doc(comoJugador(), "users", UID), nuevoUsuario({pvpRating: 2400}))
    );
  });

  await t.test("no puede llegar con victorias hechas", async () => {
    await assertFails(
      setDoc(doc(comoJugador(), "users", UID), nuevoUsuario({wins1v1: 999}))
    );
  });

  await t.test("no puede crear el documento de otro", async () => {
    await assertFails(
      setDoc(doc(comoJugador(), "users", OTRO), nuevoUsuario({uid: OTRO}))
    );
  });

  await t.test("no puede desbloquear temas al crearse", async () => {
    await assertFails(
      setDoc(
        doc(comoJugador(), "users", UID),
        nuevoUsuario({ownedThemes: ["playful"]})
      )
    );
  });
});

test("la economía es solo del servidor", async (t) => {
  test.beforeEach(async () => sembrar(nuevoUsuario()));

  // Valores distintos de los sembrados a propósito: la regla mira las
  // claves que *cambian*, así que reescribir el mismo valor es un no-op
  // legítimo y no probaría nada.
  const noPuedeEscribir = {
    coins: 9999,
    xp: 9999,
    pvpRating: 2400,
    lifeUnits: 40,
    unlockedAvatars: ["avatar_pirata"],
    ownedThemes: ["playful"],
    dailyStreak: 50,
    leagueScore: 9999,
  };

  for (const [campo, valor] of Object.entries(noPuedeEscribir)) {
    await t.test(`no puede escribir ${campo}`, async () => {
      await sembrar(nuevoUsuario());
      await assertFails(
        setDoc(
          doc(comoJugador(), "users", UID),
          {[campo]: valor},
          {merge: true}
        )
      );
    });
  }

  await t.test("sí puede cambiar su nombre", async () => {
    await sembrar(nuevoUsuario());
    await assertSucceeds(
      setDoc(
        doc(comoJugador(), "users", UID),
        {username: "Nuevo", usernameLower: "nuevo"},
        {merge: true}
      )
    );
  });

  await t.test("no puede tocar el documento de otro jugador", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", OTRO), {uid: OTRO, coins: 0});
    });

    await assertFails(
      setDoc(
        doc(comoJugador(), "users", OTRO),
        {username: "hackeado"},
        {merge: true}
      )
    );
  });

  // El documento es legible por cualquiera a propósito: amigos, rankings y
  // perfiles lo leen. Lo privado vive en la subcolección /private.
  await t.test("otro jugador sí puede leerlo", async () => {
    await sembrar(nuevoUsuario());
    await assertSucceeds(
      getDoc(doc(env.authenticatedContext(OTRO).firestore(), "users", UID))
    );
  });

  await t.test("sin sesión no se lee nada", async () => {
    await sembrar(nuevoUsuario());
    await assertFails(
      getDoc(doc(env.unauthenticatedContext().firestore(), "users", UID))
    );
  });
});

test("equipar cosméticos", async (t) => {
  await t.test("puede equipar un avatar desbloqueado", async () => {
    await sembrar(nuevoUsuario());
    await assertSucceeds(
      setDoc(
        doc(comoJugador(), "users", UID),
        {avatarId: "avatar_3"},
        {merge: true}
      )
    );
  });

  await t.test("no puede equipar un avatar que no tiene", async () => {
    await sembrar(nuevoUsuario());
    await assertFails(
      setDoc(
        doc(comoJugador(), "users", UID),
        {avatarId: "avatar_legendario"},
        {merge: true}
      )
    );
  });

  await t.test("puede equipar un marco de su liga", async () => {
    await sembrar(nuevoUsuario());
    await assertSucceeds(
      setDoc(
        doc(comoJugador(), "users", UID),
        {equippedFrame: "bronze"},
        {merge: true}
      )
    );
  });

  await t.test("no puede equipar un marco de liga superior", async () => {
    await sembrar(nuevoUsuario());
    await assertFails(
      setDoc(
        doc(comoJugador(), "users", UID),
        {equippedFrame: "master"},
        {merge: true}
      )
    );
  });
});

// Lo más reciente y lo menos rodado: el tema comprable. Que un jugador
// pueda equipar lo que no compró convierte la tienda en decorado.
test("temas comprables", async (t) => {
  await t.test("puede volver al tema gratuito siempre", async () => {
    await sembrar(nuevoUsuario());
    await assertSucceeds(
      setDoc(
        doc(comoJugador(), "users", UID),
        {equippedTheme: "default"},
        {merge: true}
      )
    );
  });

  await t.test("no puede equipar un tema que no compró", async () => {
    await sembrar(nuevoUsuario());
    await assertFails(
      setDoc(
        doc(comoJugador(), "users", UID),
        {equippedTheme: "playful"},
        {merge: true}
      )
    );
  });

  await t.test("sí puede equipar el que el servidor le concedió", async () => {
    await sembrar(nuevoUsuario({ownedThemes: ["playful"]}));
    await assertSucceeds(
      setDoc(
        doc(comoJugador(), "users", UID),
        {equippedTheme: "playful"},
        {merge: true}
      )
    );
  });

  // El intento obvio: concederse el tema y equiparlo en la misma escritura.
  // La regla mira `resource.data`, el documento *antes* del cambio.
  await t.test("no puede concedérselo y equiparlo a la vez", async () => {
    await sembrar(nuevoUsuario());
    await assertFails(
      setDoc(
        doc(comoJugador(), "users", UID),
        {ownedThemes: ["playful"], equippedTheme: "playful"},
        {merge: true}
      )
    );
  });
});

test("la subcolección privada", async (t) => {
  await t.test("el dueño escribe su token de push", async () => {
    await assertSucceeds(
      setDoc(doc(comoJugador(), "users", UID, "private", "push"), {
        fcmToken: "abc",
      })
    );
  });

  // El token vivía en el documento de usuario, que es público, así que
  // cualquiera podía cosechar el de los demás. Por eso existe /private.
  await t.test("otro jugador no puede leerlo", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", UID, "private", "push"), {
        fcmToken: "abc",
      });
    });

    await assertFails(
      getDoc(
        doc(
          env.authenticatedContext(OTRO).firestore(),
          "users", UID, "private", "push"
        )
      )
    );
  });
});
