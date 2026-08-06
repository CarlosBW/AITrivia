/**
 * Rellena los pools de las categorias fijas hasta 30/40/30 (100 por categoria).
 *
 * El objetivo por dificultad sale de difficultyForLevel() en functions/src/index.ts:
 *   niveles 1-3  -> difficulty_1  (3 niveles x 10 preguntas = 30)
 *   niveles 4-7  -> difficulty_2  (4 niveles x 10 preguntas = 40)
 *   niveles 8-10 -> difficulty_3  (3 niveles x 10 preguntas = 30)
 *
 * APPEND-ONLY: nunca sobrescribe una pregunta existente. Calcula el primer id
 * libre leyendo el pool y aborta si detectara una colision. Por defecto corre
 * en dry-run; hay que pasar --commit para escribir de verdad.
 *
 *   node seed_fill_pools.js            # dry-run, no escribe nada
 *   node seed_fill_pools.js --commit   # escribe en Firestore
 *   node seed_fill_pools.js --commit --only=cine
 */
const admin = require("firebase-admin");
const path = require("path");

const DATA = require("./fill_pools_data");

const COMMIT = process.argv.includes("--commit");
const onlyArg = process.argv.find((a) => a.startsWith("--only="));
const ONLY = onlyArg ? onlyArg.split("=")[1] : null;

const TARGET = {1: 30, 2: 40, 3: 30};

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

function questionsCol(categoryId, difficulty) {
  return db
    .collection("fixed_pools").doc(categoryId)
    .collection(`difficulty_${difficulty}`).doc("pool")
    .collection("questions");
}

/** Valida la forma de una pregunta antes de subirla. */
function validate(q, where) {
  const errs = [];
  if (typeof q.q !== "string" || q.q.trim().length < 8) {
    errs.push("enunciado vacio o muy corto");
  }
  if (!Array.isArray(q.options) || q.options.length !== 4) {
    errs.push("options debe tener exactamente 4 entradas");
  } else {
    if (q.options.some((o) => typeof o !== "string" || !o.trim())) {
      errs.push("alguna opcion vacia");
    }
    const uniq = new Set(q.options.map((o) => o.trim().toLowerCase()));
    if (uniq.size !== 4) errs.push("opciones duplicadas");
  }
  if (!Number.isInteger(q.answerIndex) || q.answerIndex < 0 || q.answerIndex > 3) {
    errs.push("answerIndex fuera de rango 0-3");
  }
  return errs.map((e) => `${where}: ${e}`);
}

async function run() {
  const cats = Object.keys(DATA).sort();
  const plan = [];
  let problems = [];

  // --- Validacion local, antes de tocar Firestore ---
  const seenTexts = new Map();
  for (const cat of cats) {
    for (const d of [1, 2, 3]) {
      const list = DATA[cat][`d${d}`] || [];
      list.forEach((q, i) => {
        problems.push(...validate(q, `${cat}/d${d}[${i}]`));
        const key = q.q.trim().toLowerCase();
        if (seenTexts.has(key)) {
          problems.push(`${cat}/d${d}[${i}]: duplicada de ${seenTexts.get(key)}`);
        }
        seenTexts.set(key, `${cat}/d${d}[${i}]`);
      });
    }
  }
  if (problems.length) {
    console.error("Validacion fallida:\n" + problems.join("\n"));
    process.exit(1);
  }

  // --- Contraste contra lo que ya existe ---
  for (const cat of cats) {
    if (ONLY && cat !== ONLY) continue;

    for (const d of [1, 2, 3]) {
      const col = questionsCol(cat, d);
      const snap = await col.get();

      const existingIds = new Set(snap.docs.map((s) => s.id));
      const existingTexts = new Set(
        snap.docs.map((s) => String(s.data().q || "").trim().toLowerCase())
      );

      const maxN = snap.docs.reduce((m, s) => {
        const n = /^q(\d+)$/.exec(s.id);
        return n ? Math.max(m, parseInt(n[1], 10)) : m;
      }, 0);

      const incoming = DATA[cat][`d${d}`] || [];
      const need = Math.max(0, TARGET[d] - snap.size);

      // Choca con una pregunta ya publicada?
      for (const q of incoming) {
        if (existingTexts.has(q.q.trim().toLowerCase())) {
          problems.push(`${cat}/d${d}: "${q.q}" ya existe en el pool`);
        }
      }

      if (incoming.length !== need) {
        problems.push(
          `${cat}/d${d}: hay ${snap.size}, faltan ${need}, ` +
          `pero el archivo trae ${incoming.length}`
        );
      }

      const assigned = incoming.map((q, i) => {
        const id = `q${maxN + 1 + i}`;
        if (existingIds.has(id)) {
          problems.push(`${cat}/d${d}: el id ${id} ya existe (colision)`);
        }
        return {id, q};
      });

      plan.push({cat, d, existing: snap.size, adding: assigned.length, assigned});
    }
  }

  if (problems.length) {
    console.error("Se aborta, hay problemas:\n" + problems.join("\n"));
    process.exit(1);
  }

  console.log("cat/dif".padEnd(20), "tiene", "agrega", "queda", "ids");
  console.log("-".repeat(78));
  for (const p of plan) {
    const ids = p.assigned.length
      ? `${p.assigned[0].id}..${p.assigned[p.assigned.length - 1].id}`
      : "-";
    console.log(
      `${p.cat}/d${p.d}`.padEnd(20),
      String(p.existing).padStart(5),
      String(p.adding).padStart(6),
      String(p.existing + p.adding).padStart(6),
      " " + ids
    );
  }
  const total = plan.reduce((a, p) => a + p.adding, 0);
  console.log("-".repeat(78));
  console.log(`Total a insertar: ${total}`);

  if (!COMMIT) {
    console.log("\nDRY-RUN. No se escribio nada. Usa --commit para aplicar.");
    process.exit(0);
  }

  for (const p of plan) {
    if (!p.assigned.length) continue;
    const col = questionsCol(p.cat, p.d);
    const batch = db.batch();
    for (const {id, q} of p.assigned) {
      // create() en vez de set(): falla si el documento ya existe, de modo que
      // una segunda corrida no puede sobrescribir nada.
      batch.create(col.doc(id), {
        q: q.q,
        options: q.options,
        answerIndex: q.answerIndex,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(`OK ${p.cat}/difficulty_${p.d}: +${p.assigned.length}`);
  }

  // Solo y el Reto Diario no leen los pools directamente: van contra el
  // indice cacheado en caches/daily_question_index, que se reconstruye solo
  // cada 24h (DAILY_POOL_INDEX_TTL_MS). Sin borrarlo, las preguntas recien
  // subidas no se sirven hasta que expire.
  await db.collection("caches").doc("daily_question_index").delete();
  console.log("Cache daily_question_index invalidado.");

  console.log("\nListo.");
  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
