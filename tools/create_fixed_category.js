/**
 * Da de alta una categoria fija nueva en `fixed_categories`.
 *
 * Solo crea el documento de la categoria. Las preguntas van antes, por
 * `seed_fill_pools.js` (desde `fill_pools/<id>.js`), y su ingles despues,
 * por `apply_translations.js`. Va en ese orden porque `isActive: true` es lo
 * que la muestra en Solo y la mete en el Reto diario y el PvP: activarla
 * con los pools vacios serviria niveles sin preguntas.
 *
 * Se niega a pisar una categoria que ya existe. Por defecto es dry-run.
 *
 *   node create_fixed_category.js --id=astronomia --name=Astronomía \
 *     --name-en=Astronomy --order=10
 *   node create_fixed_category.js ... --commit
 */
const admin = require("firebase-admin");
const path = require("path");

const argOf = (name) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : null;
};

const COMMIT = process.argv.includes("--commit");
const id = argOf("id");
const name = argOf("name");
const nameEn = argOf("name-en");
const order = parseInt(argOf("order") || "", 10);

// Lo que piden Solo (10 niveles x 10 preguntas) y los pools 30/40/30.
const LEVEL_COUNT = 10;
const POOL_TARGET = {1: 30, 2: 40, 3: 30};

if (!id || !/^[a-z0-9_]+$/.test(id) || !name || !nameEn ||
    !Number.isInteger(order)) {
  console.error(
    "Uso: node create_fixed_category.js --id=<id> --name=<nombre> " +
    "--name-en=<name> --order=<n> [--commit]"
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

async function run() {
  const ref = db.collection("fixed_categories").doc(id);
  const existing = await ref.get();
  // apply_translations.js puede haber dejado solo `name_en`; eso no cuenta
  // como una categoria dada de alta.
  if (existing.exists && existing.data().isActive !== undefined) {
    console.error(`fixed_categories/${id} ya existe. No se toca.`);
    process.exit(1);
  }

  // Los pools tienen que estar llenos antes de activarla.
  const problems = [];
  for (const [d, target] of Object.entries(POOL_TARGET)) {
    const snap = await db.collection("fixed_pools").doc(id)
      .collection(`difficulty_${d}`).doc("pool")
      .collection("questions").count().get();
    const size = snap.data().count;
    console.log(`fixed_pools/${id}/difficulty_${d}: ${size}/${target}`);
    if (size < target) problems.push(`difficulty_${d} tiene ${size}`);
  }
  if (problems.length) {
    console.error(
      "Faltan preguntas (" + problems.join(", ") + "). " +
      `Corre antes: node seed_fill_pools.js --only=${id} --commit`
    );
    process.exit(1);
  }

  const data = {name, name_en: nameEn, order, levelCount: LEVEL_COUNT,
    isActive: true};
  console.log(`\nfixed_categories/${id}:`, data);

  if (!COMMIT) {
    console.log("\nDRY-RUN. No se escribio nada. Usa --commit para aplicar.");
    process.exit(0);
  }

  await ref.set({
    ...data,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  // El Reto diario arma su lista de categorias desde un indice cacheado
  // (ver seed_fill_pools.js); sin borrarlo, la nueva no entra hasta que
  // expire.
  await db.collection("caches").doc("daily_question_index").delete();
  console.log("Categoria creada. Cache daily_question_index invalidado.");
  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
