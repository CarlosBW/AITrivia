/**
 * Aplica las correcciones de un CSV revisado (ver `export_questions.js`) a
 * Firestore y a `fill_pools/<categoria>.js` en la misma pasada.
 *
 * Existe porque corregir una pregunta eran dos ediciones manuales sin nada
 * que las atara: si solo se tocaba Firestore, el archivo fuente quedaba con
 * la version mala, y el seeder es append-only, asi que nunca la corregiria.
 *
 * Como todo lo que escribe en produccion aqui, por defecto es dry-run.
 *
 *   node apply_question_fixes.js --in=review/preguntas_revision.csv
 *   node apply_question_fixes.js --in=... --commit
 *   node apply_question_fixes.js --in=... --sep=;
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const csv = require("./csv");
const {validateQuestion, sourceLine, sourceNeedle} = require("./question_shape");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};

const COMMIT = process.argv.includes("--commit");
const SEP = argOf("sep", ",");
const IN = argOf("in", null);

const TARGET = {1: 30, 2: 40, 3: 30};
const BATCH_LIMIT = 400;
const READ_LIMIT = 300;

if (!IN) {
  console.error("Falta --in=<csv revisado>.");
  process.exit(1);
}
const inputPath = path.resolve(__dirname, IN);
if (!fs.existsSync(inputPath)) {
  console.error(`No existe ${inputPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

const problems = [];
const warnings = [];

function questionDoc(categoryId, difficulty, docId) {
  return db
    .collection("fixed_pools").doc(categoryId)
    .collection(`difficulty_${difficulty}`).doc("pool")
    .collection("questions").doc(docId);
}

const norm = (s) => String(s ?? "").trim().toLowerCase();

/** Lee las celdas de correccion de una fila y decide que hay que hacer. */
function readIntent(row) {
  const verdict = norm(row.veredicto);
  const edits = [
    row.nueva_pregunta,
    row.nueva_opcion1,
    row.nueva_opcion2,
    row.nueva_opcion3,
    row.nueva_opcion4,
    row.nueva_correcta,
  ].some((cell) => String(cell ?? "").trim() !== "");

  if (verdict === "drop") return "drop";
  if (verdict === "fix") return "fix";

  // Silenciar una fila con correcciones escritas seria la peor forma de
  // fallar: el revisor creeria que se aplicaron.
  if (edits) {
    problems.push(
      `fila ${row.__line} (${row.categoria}/${row.docId}): tiene ` +
      "correcciones pero el veredicto no dice 'fix' ni 'drop'"
    );
  }
  return "skip";
}

/** Resuelve `nueva_correcta` (1-4 o el texto exacto) contra las opciones. */
function resolveAnswerIndex(row, options, fallbackIndex) {
  const raw = String(row.nueva_correcta ?? "").trim();
  if (!raw) return fallbackIndex;

  if (/^[1-4]$/.test(raw)) return parseInt(raw, 10) - 1;

  const match = options.findIndex((o) => norm(o) === norm(raw));
  if (match === -1) {
    problems.push(
      `fila ${row.__line} (${row.categoria}/${row.docId}): ` +
      `nueva_correcta "${raw}" no es 1-4 ni coincide con ninguna opcion`
    );
    return fallbackIndex;
  }
  return match;
}

async function buildChanges(records) {
  const changes = [];
  const pending = [];

  for (const row of records) {
    const intent = readIntent(row);
    if (intent === "skip") continue;

    const categoryId = row.categoria;
    const difficulty = parseInt(row.dificultad, 10);
    const docId = row.docId;

    if (!categoryId || !docId || ![1, 2, 3].includes(difficulty)) {
      problems.push(
        `fila ${row.__line}: categoria/dificultad/docId incompletos`
      );
      continue;
    }

    pending.push({
      row, intent, categoryId, difficulty, docId,
      ref: questionDoc(categoryId, difficulty, docId),
    });
  }

  // De golpe y no uno a uno: una rebaraja completa son ~900 filas, y en
  // serie eso es una ida y vuelta por documento.
  const snapshots = new Map();
  for (let i = 0; i < pending.length; i += READ_LIMIT) {
    const slice = pending.slice(i, i + READ_LIMIT);
    const snaps = await db.getAll(...slice.map((p) => p.ref));
    snaps.forEach((snap, j) => snapshots.set(slice[j].ref.path, snap));
  }

  for (const {row, intent, categoryId, difficulty, docId, ref} of pending) {
    const snap = snapshots.get(ref.path);

    if (!snap.exists) {
      problems.push(
        `fila ${row.__line}: no existe ` +
        `fixed_pools/${categoryId}/difficulty_${difficulty}/pool/questions/${docId}`
      );
      continue;
    }

    const live = snap.data();
    const liveOptions = Array.isArray(live.options) ? live.options : [];

    // El CSV pudo exportarse hace dias. Si la pregunta ya no es la que se
    // reviso, la correccion se estaria aplicando a otra cosa.
    if (String(live.q ?? "") !== row.pregunta) {
      problems.push(
        `fila ${row.__line} (${categoryId}/${docId}): el enunciado en ` +
        "Firestore ya no coincide con el del CSV. Vuelve a exportar."
      );
      continue;
    }
    const csvOptions = [
      row.opcion1, row.opcion2, row.opcion3, row.opcion4,
    ];
    if (liveOptions.some((o, i) => String(o) !== csvOptions[i])) {
      problems.push(
        `fila ${row.__line} (${categoryId}/${docId}): las opciones en ` +
        "Firestore ya no coinciden con las del CSV. Vuelve a exportar."
      );
      continue;
    }

    if (intent === "drop") {
      changes.push({
        row, ref, categoryId, difficulty, docId,
        kind: "drop",
        original: {q: live.q, options: liveOptions},
      });
      continue;
    }

    const newQuestion = String(row.nueva_pregunta ?? "").trim() || live.q;
    const newOptions = liveOptions.map((option, i) => {
      const edited = String(row[`nueva_opcion${i + 1}`] ?? "").trim();
      return edited || String(option);
    });
    const optionsChanged = newOptions.some(
      (o, i) => o !== String(liveOptions[i])
    );

    const answerIndex = resolveAnswerIndex(
      row, newOptions, Number(live.answerIndex)
    );

    if (optionsChanged && !String(row.nueva_correcta ?? "").trim()) {
      warnings.push(
        `${categoryId}/${docId}: cambian las opciones y nueva_correcta ` +
        `esta vacia, se conserva la ${answerIndex + 1}`
      );
    }

    const updated = {q: newQuestion, options: newOptions, answerIndex};
    problems.push(
      ...validateQuestion(updated, `fila ${row.__line} (${categoryId}/${docId})`)
    );

    const same =
      updated.q === String(live.q) &&
      !optionsChanged &&
      updated.answerIndex === Number(live.answerIndex);

    if (same) {
      warnings.push(
        `${categoryId}/${docId}: veredicto 'fix' pero no cambia nada`
      );
      continue;
    }

    changes.push({
      row, ref, categoryId, difficulty, docId,
      kind: "fix",
      original: {q: String(live.q), options: liveOptions.map(String)},
      updated,
    });
  }

  return changes;
}

/**
 * Calcula el texto nuevo de cada `fill_pools/<categoria>.js`.
 *
 * Localiza cada pregunta por su texto serializado en vez de parsear el
 * modulo, que es lo unico que permite reescribir una linea sin reformatear
 * el archivo entero.
 */
function patchSources(changes) {
  const byCategory = new Map();
  for (const change of changes) {
    if (!byCategory.has(change.categoryId)) {
      byCategory.set(change.categoryId, []);
    }
    byCategory.get(change.categoryId).push(change);
  }

  const patches = [];

  for (const [categoryId, list] of byCategory) {
    const file = path.join(__dirname, "fill_pools", `${categoryId}.js`);
    if (!fs.existsSync(file)) {
      for (const change of list) {
        change.inSource = false;
      }
      continue;
    }

    const original = fs.readFileSync(file, "utf8");
    const edits = [];

    for (const change of list) {
      const needle = sourceNeedle(change.original.q);
      const count = original.split(needle).length - 1;

      if (count === 0) {
        // Normal en las preguntas anteriores a fill_pools: solo viven en
        // Firestore, y ahi si se corrigen.
        change.inSource = false;
        continue;
      }
      if (count > 1) {
        problems.push(
          `${categoryId}.js: "${change.original.q}" aparece ${count} veces, ` +
          "no se puede decidir cual corregir"
        );
        change.inSource = false;
        continue;
      }

      change.inSource = true;

      const at = original.indexOf(needle);
      const lineStart = original.lastIndexOf("\n", at) + 1;
      let lineEnd = original.indexOf("\n", at);
      if (lineEnd === -1) lineEnd = original.length;

      const indent = /^[ \t]*/.exec(original.slice(lineStart, lineEnd))[0];

      edits.push({
        start: lineStart,
        end: change.kind === "drop" ? lineEnd + 1 : lineEnd,
        text: change.kind === "drop"
          ? ""
          : sourceLine(change.updated, indent),
      });
    }

    if (!edits.length) continue;

    // De atras hacia adelante: asi los desplazamientos ya calculados sobre
    // el texto original siguen siendo validos.
    edits.sort((a, b) => b.start - a.start);
    let patched = original;
    for (const edit of edits) {
      patched = patched.slice(0, edit.start) + edit.text + patched.slice(edit.end);
    }

    patches.push({categoryId, file, original, patched, edits: edits.length});
  }

  return patches;
}

/**
 * Ejecuta el archivo parcheado y comprueba que quedo como se pretendia.
 *
 * El parche se hace sobre texto, linea a linea, asi que esto es lo unico
 * que separa una reescritura correcta de una que rompa el archivo o corrija
 * la pregunta equivocada. Corre siempre, tambien en dry-run.
 */
function verifyPatch(patch, changes) {
  const load = (text) => {
    const sandbox = {module: {exports: {}}, exports: {}};
    vm.runInNewContext(text, sandbox, {filename: patch.file});
    return sandbox.module.exports;
  };

  let before;
  let after;
  try {
    before = load(patch.original);
    after = load(patch.patched);
  } catch (e) {
    problems.push(
      `${patch.categoryId}.js: el archivo parcheado no parsea (${e.message})`
    );
    return;
  }

  const flatten = (mod) =>
    [1, 2, 3].flatMap((d) => mod[`d${d}`] || []);

  const applied = changes.filter((c) => c.inSource);
  const drops = applied.filter((c) => c.kind === "drop");
  const result = flatten(after);
  const matching = (text) => result.filter((q) => q.q === text);

  const delta = flatten(before).length - result.length;
  if (delta !== drops.length) {
    problems.push(
      `${patch.categoryId}.js: se esperaba que el total bajara en ` +
      `${drops.length} y bajo en ${delta}`
    );
  }

  for (const change of drops) {
    if (matching(change.original.q).length) {
      problems.push(
        `${patch.categoryId}.js: "${change.original.q}" seguiria en el archivo`
      );
    }
  }

  for (const change of applied.filter((c) => c.kind === "fix")) {
    const hits = matching(change.updated.q);
    if (hits.length !== 1) {
      problems.push(
        `${patch.categoryId}.js: tras el parche "${change.updated.q}" ` +
        `aparece ${hits.length} veces`
      );
      continue;
    }

    const got = hits[0];
    if (JSON.stringify(got.options) !== JSON.stringify(change.updated.options)) {
      problems.push(`${patch.categoryId}.js: ${change.docId} quedo con otras opciones`);
    }
    if (got.answerIndex !== change.updated.answerIndex) {
      problems.push(`${patch.categoryId}.js: ${change.docId} quedo con otra respuesta`);
    }
    if (
      change.updated.q !== change.original.q &&
      matching(change.original.q).length
    ) {
      problems.push(
        `${patch.categoryId}.js: la version vieja de ${change.docId} sigue ahi`
      );
    }
  }
}

function report(changes, patches) {
  const fixes = changes.filter((c) => c.kind === "fix");
  const drops = changes.filter((c) => c.kind === "drop");

  for (const change of fixes) {
    console.log(`\n[fix] ${change.categoryId}/d${change.difficulty}/${change.docId}` +
      (change.inSource ? "" : "  (solo Firestore, no esta en la fuente)"));
    if (change.updated.q !== change.original.q) {
      console.log(`  - ${change.original.q}`);
      console.log(`  + ${change.updated.q}`);
    }
    change.updated.options.forEach((option, i) => {
      if (option !== change.original.options[i]) {
        console.log(`  opcion${i + 1}:  ${change.original.options[i]}  ->  ${option}`);
      }
    });
    const originalRow = change.row;
    const before = parseInt(String(originalRow.correcta_actual).split(":")[0], 10);
    if (before - 1 !== change.updated.answerIndex) {
      console.log(
        `  correcta:  ${before}  ->  ${change.updated.answerIndex + 1} ` +
        `(${change.updated.options[change.updated.answerIndex]})`
      );
    }
  }

  for (const change of drops) {
    console.log(`\n[drop] ${change.categoryId}/d${change.difficulty}/${change.docId}` +
      (change.inSource ? "" : "  (solo Firestore)"));
    console.log(`  ${change.original.q}`);
  }

  console.log("\n" + "-".repeat(70));
  console.log(`Correcciones: ${fixes.length}   Bajas: ${drops.length}`);
  console.log(
    `Archivos fuente a reescribir: ${patches.length}` +
    (patches.length ? ` (${patches.map((p) => p.categoryId).join(", ")})` : "")
  );
}

/** Avisa si alguna baja deja el pool por debajo de 30/40/30. */
async function warnAboutPoolSizes(drops) {
  const buckets = new Map();
  for (const drop of drops) {
    const key = `${drop.categoryId}/${drop.difficulty}`;
    buckets.set(key, (buckets.get(key) || 0) + 1);
  }

  for (const [key, removed] of buckets) {
    const [categoryId, difficulty] = key.split("/");
    const snap = await db
      .collection("fixed_pools").doc(categoryId)
      .collection(`difficulty_${difficulty}`).doc("pool")
      .collection("questions").count().get();

    const left = (snap.data().count || 0) - removed;
    const target = TARGET[difficulty];
    if (left < target) {
      warnings.push(
        `${categoryId}/difficulty_${difficulty} quedaria con ${left} ` +
        `preguntas, por debajo de las ${target} que necesitan los niveles`
      );
    }
  }
}

async function run() {
  const {header, records} = csv.parseObjects(
    fs.readFileSync(inputPath, "utf8"), SEP
  );

  const required = ["categoria", "dificultad", "docId", "pregunta", "veredicto"];
  const missing = required.filter((name) => !header.includes(name));
  if (missing.length) {
    console.error(
      `El CSV no tiene las columnas: ${missing.join(", ")}.\n` +
      (SEP === "," ? "Si lo guardaste con Excel en es-ES, prueba --sep=;" : "")
    );
    process.exit(1);
  }

  console.log(`${records.length} filas leidas de ${inputPath}`);

  const changes = await buildChanges(records);
  const patches = patchSources(changes);

  for (const patch of patches) {
    verifyPatch(
      patch,
      changes.filter((c) => c.categoryId === patch.categoryId)
    );
  }

  await warnAboutPoolSizes(changes.filter((c) => c.kind === "drop"));

  if (problems.length) {
    console.error("\nSe aborta, hay problemas:\n" + problems.join("\n"));
    process.exit(1);
  }

  if (changes.length) report(changes, patches);

  // Antes de la salida temprana: si una fila se descarto por no cambiar
  // nada, el aviso es justo lo unico que el revisor necesita ver.
  if (warnings.length) {
    console.log("\nAvisos:\n  " + warnings.join("\n  "));
  }

  if (!changes.length) {
    console.log("\nNo hay nada que aplicar.");
    process.exit(0);
  }

  if (!COMMIT) {
    console.log("\nDRY-RUN. No se escribio nada. Usa --commit para aplicar.");
    process.exit(0);
  }

  // En lotes: un batch de Firestore admite 500 operaciones como maximo, y
  // una correccion masiva (rebarajar las opciones de todo el pool) pasa de
  // ahi de sobra.
  for (let i = 0; i < changes.length; i += BATCH_LIMIT) {
    const slice = changes.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();

    for (const change of slice) {
      if (change.kind === "drop") {
        batch.delete(change.ref);
      } else {
        batch.update(change.ref, {
          q: change.updated.q,
          options: change.updated.options,
          answerIndex: change.updated.answerIndex,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
    console.log(
      `OK Firestore: ${Math.min(i + slice.length, changes.length)}/` +
      `${changes.length} documentos.`
    );
  }

  for (const patch of patches) {
    fs.writeFileSync(patch.file, patch.patched, "utf8");
    console.log(`OK fill_pools/${patch.categoryId}.js: ${patch.edits} lineas.`);
  }

  // Igual que en el seeder: Solo y el Reto Diario leen el indice cacheado,
  // no los pools, asi que sin invalidarlo seguirian sirviendo la version
  // vieja hasta que expire.
  await db.collection("caches").doc("daily_question_index").delete();
  console.log("Cache daily_question_index invalidado.");

  console.log("\nListo.");
  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e);
  process.exit(1);
});
