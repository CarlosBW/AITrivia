/**
 * Exporta las preguntas de los pools fijos a un CSV revisable.
 *
 * La revision factual no se puede hacer leyendo Firestore documento a
 * documento ni los `fill_pools/*.js` a ojo, asi que esto las saca todas a una
 * hoja con una columna para el veredicto y otras para la correccion. Lo que
 * se escriba ahi lo aplica despues `apply_question_fixes.js`, en Firestore y
 * en la fuente a la vez.
 *
 * Ordena por dificultad descendente: las d3 son donde un error factual es mas
 * probable y donde mas duele, asi que se revisan primero.
 *
 *   node export_questions.js                  # todas, a tools/review/
 *   node export_questions.js --nuevas         # solo las que estan en fill_pools/
 *   node export_questions.js --only=ciencia
 *   node export_questions.js --sep=;          # Excel en configuracion es-ES
 *   node export_questions.js --out=ruta.csv
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const csv = require("./csv");
const {sourceNeedle} = require("./question_shape");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};

const ONLY = argOf("only", null);
const SEP = argOf("sep", ",");
const NUEVAS = process.argv.includes("--nuevas");
const OUT = path.resolve(
  __dirname,
  argOf("out", path.join("review", "preguntas_revision.csv"))
);

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

const HEADER = [
  "categoria",
  "dificultad",
  "docId",
  "pregunta",
  "opcion1",
  "opcion2",
  "opcion3",
  "opcion4",
  "correcta_actual",
  "en_fuente",
  "veredicto",
  "nueva_pregunta",
  "nueva_opcion1",
  "nueva_opcion2",
  "nueva_opcion3",
  "nueva_opcion4",
  "nueva_correcta",
  "notas",
];

/** Texto de `fill_pools/<categoria>.js`, o null si esa categoria no tiene. */
function readSource(categoryId) {
  const file = path.join(__dirname, "fill_pools", `${categoryId}.js`);
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
}

async function run() {
  const categoryRefs = await db.collection("fixed_pools").listDocuments();
  const categories = categoryRefs
    .map((ref) => ref.id)
    .filter((id) => !ONLY || id === ONLY)
    .sort();

  if (!categories.length) {
    console.error(
      ONLY
        ? `No existe fixed_pools/${ONLY}.`
        : "fixed_pools no tiene ninguna categoria."
    );
    process.exit(1);
  }

  const sources = new Map(
    categories.map((id) => [id, readSource(id)])
  );

  const rows = [];
  let skippedNotNew = 0;

  // Dificultad descendente: lo mas dificil primero.
  for (const difficulty of [3, 2, 1]) {
    for (const categoryId of categories) {
      const snap = await db
        .collection("fixed_pools").doc(categoryId)
        .collection(`difficulty_${difficulty}`).doc("pool")
        .collection("questions")
        .get();

      const docs = snap.docs.slice().sort((a, b) => {
        const n = (id) => {
          const m = /^q(\d+)$/.exec(id);
          return m ? parseInt(m[1], 10) : Number.MAX_SAFE_INTEGER;
        };
        return n(a.id) - n(b.id) || a.id.localeCompare(b.id);
      });

      for (const doc of docs) {
        const data = doc.data();
        const question = String(data.q ?? "");
        const options = Array.isArray(data.options) ? data.options : [];
        const answerIndex = Number(data.answerIndex);

        const source = sources.get(categoryId);
        const inSource = Boolean(
          source && source.includes(sourceNeedle(question))
        );

        if (NUEVAS && !inSource) {
          skippedNotNew++;
          continue;
        }

        const answerText = options[answerIndex];
        const current = Number.isInteger(answerIndex) && answerText != null
          ? `${answerIndex + 1}: ${answerText}`
          : `?? (answerIndex=${data.answerIndex})`;

        rows.push([
          categoryId,
          difficulty,
          doc.id,
          question,
          options[0] ?? "",
          options[1] ?? "",
          options[2] ?? "",
          options[3] ?? "",
          current,
          inSource ? "si" : "no",
          "", "", "", "", "", "", "", "",
        ]);
      }
    }
  }

  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  fs.writeFileSync(OUT, csv.stringify([HEADER, ...rows], SEP), "utf8");

  const porDificultad = [3, 2, 1]
    .map((d) => `d${d}=${rows.filter((r) => r[1] === d).length}`)
    .join("  ");

  console.log(`Exportadas ${rows.length} preguntas  (${porDificultad})`);
  if (skippedNotNew) {
    console.log(`Omitidas ${skippedNotNew} que no estan en fill_pools/.`);
  }
  console.log(`Archivo: ${OUT}`);
  console.log(
    "\nComo revisar:\n" +
    "  veredicto = ok    -> se deja como esta (o dejalo en blanco)\n" +
    "  veredicto = fix   -> rellena solo las celdas que cambian\n" +
    "                       nueva_correcta admite 1-4 o el texto exacto\n" +
    "  veredicto = drop  -> borra la pregunta del pool y de la fuente\n" +
    "\nDespues:  node apply_question_fixes.js --in=" +
    path.relative(__dirname, OUT).replace(/\\/g, "/")
  );

  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
