/**
 * Comprueba contra Firestore donde cae la respuesta correcta.
 *
 * Complementa a `answer_balance.test.js`, que solo ve lo que entra por
 * `fill_pools/`. El sesgo que llego a produccion —507 de 900 preguntas con
 * la correcta en la primera opcion— estaba justo en las que no pasan por
 * ahi, asi que un test estatico no lo habria visto nunca.
 *
 * Sale con codigo 1 si alguna posicion se pasa del umbral, para poder
 * colgarlo de un cron igual que check_callables.js.
 *
 *   node check_answer_balance.js
 *   node check_answer_balance.js --limit=0.35
 */
const admin = require("firebase-admin");
const path = require("path");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};

// Con reparto uniforme cada posicion ronda el 25%. Holgado a proposito:
// con ~900 preguntas la desviacion tipica es de poco mas del 1%.
const LIMIT = parseFloat(argOf("limit", "0.4"));

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

async function run() {
  const categoryRefs = await db.collection("fixed_pools").listDocuments();
  const counts = [0, 0, 0, 0];
  const perCategory = new Map();
  let malformed = 0;

  for (const ref of categoryRefs) {
    const own = [0, 0, 0, 0];

    for (const difficulty of [1, 2, 3]) {
      const snap = await ref
        .collection(`difficulty_${difficulty}`).doc("pool")
        .collection("questions").get();

      for (const doc of snap.docs) {
        const index = Number(doc.data().answerIndex);
        if (!Number.isInteger(index) || index < 0 || index > 3) {
          malformed++;
          continue;
        }
        counts[index]++;
        own[index]++;
      }
    }

    perCategory.set(ref.id, own);
  }

  const total = counts.reduce((a, b) => a + b, 0);
  if (!total) {
    console.error("fixed_pools no tiene preguntas.");
    process.exit(1);
  }

  console.log(`${total} preguntas en fixed_pools\n`);
  console.log("categoria".padEnd(16), "pos1  pos2  pos3  pos4");
  console.log("-".repeat(44));
  for (const id of [...perCategory.keys()].sort()) {
    console.log(
      id.padEnd(16),
      perCategory.get(id).map((c) => String(c).padStart(4)).join("  ")
    );
  }
  console.log("-".repeat(44));
  console.log(
    "TOTAL".padEnd(16),
    counts.map((c) => String(c).padStart(4)).join("  ")
  );
  console.log(
    "".padEnd(16),
    counts
      .map((c) => `${((c / total) * 100).toFixed(0)}%`.padStart(4))
      .join("  ")
  );

  if (malformed) {
    console.error(`\n${malformed} preguntas con answerIndex invalido.`);
  }

  const over = counts
    .map((c, i) => ({position: i + 1, share: c / total}))
    .filter((x) => x.share > LIMIT);

  if (over.length || malformed) {
    console.error(
      "\nFALLA: " +
      over
        .map(
          (x) =>
            `la posicion ${x.position} concentra el ` +
            `${(x.share * 100).toFixed(0)}% (maximo ${LIMIT * 100}%)`
        )
        .join("; ")
    );
    console.error(
      "Pasa los pools por shuffle_question_options.js para repartirlas."
    );
    process.exit(1);
  }

  console.log(
    `\nOK: ninguna posicion pasa del ${LIMIT * 100}%.`
  );
  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
