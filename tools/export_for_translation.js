/**
 * Saca el banco fijo a `translations/<categoria>.es.json`, una entrada por
 * pregunta con su dificultad y docId, para traducirlo. La traduccion va en
 * `translations/<categoria>.en.json` con las mismas entradas en el mismo
 * orden, y `apply_translations.js` la escribe como `q_en`/`options_en`.
 *
 * Solo lee Firestore.
 *
 *   node export_for_translation.js
 *   node export_for_translation.js --only=ciencia
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};
const ONLY = argOf("only", null);

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

const OUT_DIR = path.join(__dirname, "translations");

async function run() {
  const categoryRefs = await db.collection("fixed_pools").listDocuments();
  const categories = categoryRefs
    .map((ref) => ref.id)
    .filter((id) => !ONLY || id === ONLY)
    .sort();

  fs.mkdirSync(OUT_DIR, {recursive: true});

  for (const categoryId of categories) {
    const entries = [];
    for (const difficulty of [1, 2, 3]) {
      const snap = await db
        .collection("fixed_pools").doc(categoryId)
        .collection(`difficulty_${difficulty}`).doc("pool")
        .collection("questions")
        .get();
      const docs = snap.docs.slice().sort((a, b) => a.id.localeCompare(
        b.id, undefined, {numeric: true}
      ));
      for (const doc of docs) {
        const data = doc.data();
        entries.push({
          d: difficulty,
          id: doc.id,
          q: String(data.q ?? ""),
          options: (data.options || []).map(String),
          answerIndex: Number(data.answerIndex),
        });
      }
    }
    const file = path.join(OUT_DIR, `${categoryId}.es.json`);
    fs.writeFileSync(file, JSON.stringify(entries, null, 2) + "\n", "utf8");
    console.log(`${categoryId}: ${entries.length} -> ${path.relative(__dirname, file)}`);
  }
  process.exit(0);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
