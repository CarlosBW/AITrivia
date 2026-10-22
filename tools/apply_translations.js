/**
 * Escribe la traduccion al ingles del banco fijo (`translations/<cat>.en.json`)
 * como `q_en`/`options_en` en cada pregunta de `fixed_pools`, y el nombre en
 * ingles de cada categoria como `name_en` en `fixed_categories`.
 *
 * Las opciones en ingles van en el mismo orden que las espanolas, asi que
 * `answerIndex` (y lo que juzga el servidor) no cambia. La app muestra el
 * ingles solo si existe y tiene las mismas opciones; si no, el espanol.
 *
 * Solo escribe una pregunta si su espanol en Firestore sigue siendo el de
 * `translations/<cat>.es.json`: si alguien la corrigio despues de exportar,
 * la traduccion describe otra pregunta y se salta (hay que reexportar y
 * traducir esa).
 *
 * Como todo lo que escribe en produccion aqui, por defecto es dry-run.
 *
 *   node apply_translations.js
 *   node apply_translations.js --only=ciencia
 *   node apply_translations.js --commit
 */
const fs = require("fs");
const path = require("path");

const CATEGORY_NAMES_EN = {
  arte: "Art",
  ciencia: "Science",
  cine: "Movies",
  deportes: "Sports",
  geografia: "Geography",
  historia: "World History",
  libros: "Books",
  musica: "Music",
  videojuegos: "Video Games",
};

const sameList = (a, b) =>
  Array.isArray(a) && Array.isArray(b) &&
  a.length === b.length && a.every((x, i) => String(x) === String(b[i]));

/**
 * Decide que escribir. `es` y `en` son los JSON de una categoria; `live` es
 * un Map de `"<d>/<id>"` a los datos actuales en Firestore.
 */
function planCategory(es, en, live) {
  const updates = [];
  const skipped = [];

  if (!Array.isArray(es) || !Array.isArray(en) || es.length !== en.length) {
    return {updates, skipped: [{key: "*", reason: "es/en de distinto largo"}]};
  }

  es.forEach((source, i) => {
    const translated = en[i];
    const key = `${source.d}/${source.id}`;
    const skip = (reason) => skipped.push({key, reason});

    if (translated.d !== source.d || translated.id !== source.id) {
      return skip("posicion distinta en es/en");
    }
    const qEn = String(translated.q ?? "").trim();
    const optionsEn = (translated.options || []).map((o) => String(o).trim());
    if (!qEn || optionsEn.length !== source.options.length ||
        optionsEn.some((o) => !o)) {
      return skip("traduccion incompleta");
    }

    const current = live.get(key);
    if (!current) return skip("ya no existe en Firestore");
    if (String(current.q) !== source.q ||
        !sameList(current.options, source.options)) {
      return skip("el espanol cambio desde la exportacion");
    }
    if (current.q_en === qEn && sameList(current.options_en, optionsEn)) {
      return skip("ya estaba igual");
    }

    updates.push({d: source.d, id: source.id, q_en: qEn, options_en: optionsEn});
  });

  return {updates, skipped};
}

async function run() {
  const admin = require("firebase-admin");

  const argOf = (name, fallback) => {
    const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
    return arg ? arg.slice(name.length + 3) : fallback;
  };
  const ONLY = argOf("only", null);
  const COMMIT = process.argv.includes("--commit");

  admin.initializeApp({
    credential: admin.credential.cert(
      require(path.join(__dirname, "serviceAccountKey.json"))
    ),
  });
  const db = admin.firestore();
  const dir = path.join(__dirname, "translations");

  const categories = Object.keys(CATEGORY_NAMES_EN)
    .filter((id) => !ONLY || id === ONLY);

  let total = 0;
  for (const categoryId of categories) {
    const esFile = path.join(dir, `${categoryId}.es.json`);
    const enFile = path.join(dir, `${categoryId}.en.json`);
    if (!fs.existsSync(esFile) || !fs.existsSync(enFile)) {
      console.log(`${categoryId}: falta ${categoryId}.es.json o .en.json`);
      continue;
    }
    const es = JSON.parse(fs.readFileSync(esFile, "utf8"));
    const en = JSON.parse(fs.readFileSync(enFile, "utf8"));

    const pool = (d) => db.collection("fixed_pools").doc(categoryId)
      .collection(`difficulty_${d}`).doc("pool").collection("questions");

    const live = new Map();
    for (const d of [1, 2, 3]) {
      const snap = await pool(d).get();
      snap.forEach((doc) => live.set(`${d}/${doc.id}`, doc.data()));
    }

    const {updates, skipped} = planCategory(es, en, live);
    total += updates.length;
    console.log(
      `${categoryId}: ${updates.length} para escribir, ${skipped.length} saltadas`
    );
    for (const s of skipped.filter((s) => s.reason !== "ya estaba igual")) {
      console.log(`  - ${s.key}: ${s.reason}`);
    }

    if (COMMIT) {
      for (let i = 0; i < updates.length; i += 400) {
        const batch = db.batch();
        for (const u of updates.slice(i, i + 400)) {
          batch.update(pool(u.d).doc(u.id), {
            q_en: u.q_en,
            options_en: u.options_en,
          });
        }
        await batch.commit();
      }
      await db.collection("fixed_categories").doc(categoryId)
        .set({name_en: CATEGORY_NAMES_EN[categoryId]}, {merge: true});
    }
  }

  console.log(
    COMMIT ?
      `\nEscritas ${total} traducciones.` :
      `\nDry-run: ${total} traducciones por escribir. Agrega --commit.`
  );
  process.exit(0);
}

if (require.main === module) {
  run().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {planCategory, CATEGORY_NAMES_EN};
