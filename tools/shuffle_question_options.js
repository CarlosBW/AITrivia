/**
 * Rebaraja las opciones de las preguntas de los pools fijos.
 *
 * Hacia falta porque la posicion de la respuesta correcta no estaba
 * repartida: 507 de 900 preguntas la tenian en la primera opcion, asi que
 * responder siempre "la primera" acertaba el 56% de las veces. Barajar el
 * orden de las preguntas —que es lo unico que hacia el juego— no arregla
 * eso: mueve las preguntas, no la respuesta dentro de cada una.
 *
 * No decide nada por si mismo: escribe un CSV de correcciones que aplica
 * `apply_question_fixes.js`, para que las escrituras pasen por el mismo
 * camino ya probado (validacion de forma, parcheo de la fuente y
 * verificacion del resultado) en vez de por un segundo escritor.
 *
 * La baraja se siembra con el enunciado, no con el reloj: la misma pregunta
 * da siempre la misma permutacion, de modo que el CSV es reproducible y lo
 * que muestra el dry-run es exactamente lo que se escribe.
 *
 *   node shuffle_question_options.js
 *   node shuffle_question_options.js --only=cine
 *   node shuffle_question_options.js --out=review/rebaraja.csv
 *   node apply_question_fixes.js --in=review/rebaraja.csv        # dry-run
 *   node apply_question_fixes.js --in=review/rebaraja.csv --commit
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const csv = require("./csv");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};

const ONLY = argOf("only", null);
const SEP = argOf("sep", ",");
const OUT = path.resolve(
  __dirname,
  argOf("out", path.join("review", "rebaraja_opciones.csv"))
);

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

const HEADER = [
  "categoria", "dificultad", "docId", "pregunta",
  "opcion1", "opcion2", "opcion3", "opcion4",
  "correcta_actual", "en_fuente", "veredicto",
  "nueva_pregunta", "nueva_opcion1", "nueva_opcion2", "nueva_opcion3",
  "nueva_opcion4", "nueva_correcta", "notas",
];

/** FNV-1a de 32 bits, el mismo hash que usa `index.ts` para sembrar. */
function fnv1a32(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** PRNG determinista (mulberry32) a partir de una semilla de 32 bits. */
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Fisher-Yates sembrado. Devuelve una permutacion nueva. */
function shuffled(items, rand) {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

async function run() {
  const categoryRefs = await db.collection("fixed_pools").listDocuments();
  const categories = categoryRefs
    .map((ref) => ref.id)
    .filter((id) => !ONLY || id === ONLY)
    .sort();

  const sources = new Map(
    categories.map((id) => {
      const file = path.join(__dirname, "fill_pools", `${id}.js`);
      return [id, fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null];
    })
  );

  const rows = [];
  const problems = [];
  const before = [0, 0, 0, 0];
  const after = [0, 0, 0, 0];
  let unchanged = 0;

  for (const categoryId of categories) {
    for (const difficulty of [1, 2, 3]) {
      const snap = await db
        .collection("fixed_pools").doc(categoryId)
        .collection(`difficulty_${difficulty}`).doc("pool")
        .collection("questions")
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const question = String(data.q ?? "");
        const options = (Array.isArray(data.options) ? data.options : [])
          .map(String);
        const answerIndex = Number(data.answerIndex);

        const where = `${categoryId}/d${difficulty}/${doc.id}`;

        if (options.length !== 4) {
          problems.push(`${where}: tiene ${options.length} opciones, no 4`);
          continue;
        }
        if (!Number.isInteger(answerIndex) ||
            answerIndex < 0 || answerIndex > 3) {
          problems.push(`${where}: answerIndex fuera de rango`);
          continue;
        }

        const answerText = options[answerIndex];

        // `nueva_correcta` acepta "1".."4" como posicion, asi que una
        // respuesta cuyo texto sea uno de esos digitos (las preguntas de
        // "¿cuantos...?" con opciones numericas) se leeria como posicion.
        // Esas van por posicion explicita; el resto por texto, que ademas
        // sirve de contraste entre las opciones nuevas y la respuesta.
        const ambiguous = /^[1-4]$/.test(answerText.trim());

        before[answerIndex]++;

        const rand = mulberry32(fnv1a32(question));
        const newOptions = shuffled(options, rand);
        const newIndex = newOptions.indexOf(answerText);

        // La respuesta tiene que ser la misma; solo cambia de sitio.
        if (newIndex === -1) {
          problems.push(`${where}: la respuesta se perdio al barajar`);
          continue;
        }
        if (new Set(newOptions).size !== 4) {
          problems.push(`${where}: opciones duplicadas tras barajar`);
          continue;
        }

        after[newIndex]++;
        if (newIndex === answerIndex &&
            newOptions.every((o, i) => o === options[i])) {
          unchanged++;
          continue;
        }

        const source = sources.get(categoryId);
        const inSource = Boolean(
          source && source.includes(`{q: ${JSON.stringify(question)},`)
        );

        rows.push([
          categoryId, difficulty, doc.id, question,
          options[0], options[1], options[2], options[3],
          `${answerIndex + 1}: ${answerText}`,
          inSource ? "si" : "no",
          "fix",
          "",
          newOptions[0], newOptions[1], newOptions[2], newOptions[3],
          ambiguous ? String(newIndex + 1) : answerText,
          ambiguous
            ? `la respuesta es el texto "${answerText}", se indica por ` +
              "posicion para no confundirla con la forma 1-4"
            : "",
        ]);
      }
    }
  }

  if (problems.length) {
    console.error("Se aborta, hay problemas:\n" + problems.join("\n"));
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  fs.writeFileSync(OUT, csv.stringify([HEADER, ...rows], SEP), "utf8");

  const pct = (counts) => {
    const total = counts.reduce((a, b) => a + b, 0) || 1;
    return counts
      .map((c, i) => `pos${i + 1}=${c} (${((c / total) * 100).toFixed(0)}%)`)
      .join("  ");
  };

  console.log("Reparto de la respuesta correcta");
  console.log("  antes: ", pct(before));
  console.log("  despues:", pct(after));
  console.log(
    `\n${rows.length} preguntas a rebarajar` +
    (unchanged ? `, ${unchanged} que la permutacion dejo igual` : "")
  );
  console.log(`Archivo: ${OUT}`);
  console.log(
    "\nRevisa y aplica:\n" +
    `  node apply_question_fixes.js --in=${
      path.relative(__dirname, OUT).replace(/\\/g, "/")}\n` +
    "  ...y con --commit cuando el dry-run cuadre."
  );

  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
