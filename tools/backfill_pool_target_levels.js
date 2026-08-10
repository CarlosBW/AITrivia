/**
 * Corrige `targetLevels` en los docs de `ai_topic_pool` creados antes del
 * arreglo en functions/src/index.ts.
 *
 * Que arregla: `getOrCreatePoolEntry` sembraba el campo con
 * AI_INITIAL_GENERATED_LEVELS (2), que es cuantos niveles se generan de
 * entrada, no la profundidad objetivo del tema. Como ademas nada volvia a
 * subirlo salvo la generacion misma, cada pool quedaba declarando un
 * objetivo de 2 mientras cada tema que lo adoptaba apuntaba a 10 (o mas si
 * el jugador pago una ampliacion). Es el caso del pool de "Harry Potter".
 *
 * Nada de esto cambia lo que se genera: el buffering se acota contra el
 * `targetLevels` del tema del usuario, no contra el del pool (ver
 * ensureAiTopicLevelsGenerated). Este campo es informativo, asi que el
 * backfill solo lo pone en un piso correcto.
 *
 * El piso es max(actual, AI_LEVELS_PER_TOPIC, generatedLevels): todo tema
 * que adopta un pool apunta al menos a AI_LEVELS_PER_TOPIC, y un pool nunca
 * puede tener generados mas niveles de los que dice querer. No intenta
 * reconstruir el objetivo real de quien amplio su tema por encima de eso
 * (habria que barrer users/{uid}/ai_topics con un collectionGroup y su
 * indice); si alguien vuelve a ampliar, expandAiTopic ya sube el pool solo.
 *
 * APPEND-ONLY en la practica: solo sube el valor, nunca lo baja, y salta los
 * docs que ya estan bien. Por defecto corre en dry-run; hay que pasar
 * --commit para escribir de verdad.
 *
 *   node backfill_pool_target_levels.js            # dry-run, no escribe
 *   node backfill_pool_target_levels.js --commit   # escribe en Firestore
 */
const admin = require("firebase-admin");
const path = require("path");

const COMMIT = process.argv.includes("--commit");

// Espeja AI_LEVELS_PER_TOPIC en functions/src/index.ts. Si cambia alla,
// cambia aca.
const AI_LEVELS_PER_TOPIC = 10;

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

function safeInt(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

async function main() {
  const snap = await db.collection("ai_topic_pool").get();

  if (snap.empty) {
    console.log("No hay pools de temas IA.");
    return;
  }

  const pending = [];

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const current = safeInt(data.targetLevels, 0);
    const generated = safeInt(data.generatedLevels, 0);
    const desired = Math.max(current, AI_LEVELS_PER_TOPIC, generated);

    if (desired === current) continue;

    pending.push({
      id: doc.id,
      title: String(data.title || "(sin titulo)"),
      current,
      generated,
      desired,
    });
  }

  console.log(`Pools revisados: ${snap.size}`);
  console.log(`Pools a corregir: ${pending.length}`);

  for (const p of pending) {
    console.log(
      `  ${p.title} [${p.id}] targetLevels ${p.current} -> ${p.desired} ` +
      `(generatedLevels ${p.generated})`
    );
  }

  if (pending.length === 0) return;

  if (!COMMIT) {
    console.log("\nDry-run: no se escribio nada. Repite con --commit.");
    return;
  }

  // En lotes por si el pool crece; 500 es el limite de un batch de Firestore.
  const BATCH_SIZE = 400;

  for (let i = 0; i < pending.length; i += BATCH_SIZE) {
    const batch = db.batch();

    for (const p of pending.slice(i, i + BATCH_SIZE)) {
      batch.set(
        db.collection("ai_topic_pool").doc(p.id),
        {
          targetLevels: p.desired,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }

    await batch.commit();
  }

  console.log(`\nListo: ${pending.length} pool(s) corregidos.`);
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  }
);
