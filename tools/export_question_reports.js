/**
 * Exporta los reportes de preguntas del banco fijo (los que los jugadores
 * mandan desde "Revisar preguntas" al final de un nivel) a un CSV con el
 * mismo formato que `export_questions.js`, para corregirlas con
 * `apply_question_fixes.js`.
 *
 * Agrupa por pregunta: una fila por pregunta reportada, con cuantos la
 * reportaron, por que y lo que escribieron. Las mas reportadas van primero.
 * Los reportes no esconden nada por su cuenta (un solo jugador podria
 * enterrar cualquier pregunta), asi que lo que no pase por aqui no cambia.
 *
 *   node export_question_reports.js                  # abiertos, a tools/review/
 *   node export_question_reports.js --sep=;          # Excel en configuracion es-ES
 *   node export_question_reports.js --out=ruta.csv
 *
 * Despues de aplicar las correcciones, marcar esos reportes como revisados
 * para que no vuelvan a salir (por defecto es dry-run):
 *
 *   node export_question_reports.js --cerrar --commit
 */
const fs = require("fs");
const path = require("path");

const csv = require("./csv");
const {sourceNeedle} = require("./question_shape");

const REASON_LABELS = {
  wrong_answer: "respuesta mal marcada",
  confusing: "confusa",
  typo: "ortografia/traduccion",
  inappropriate: "inapropiada",
  other: "otro",
};

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
  "reportes",
  "motivos",
  "comentarios",
];

/**
 * Agrupa reportes por pregunta. Cada reporte es
 * `{categoryId, difficulty, docId, question: {q, options, answerIndex},
 * reason, details}`; devuelve una entrada por pregunta, ordenadas de mas a
 * menos reportada.
 */
function groupReports(reports) {
  const groups = new Map();

  for (const report of reports) {
    const q = String(report.question?.q ?? "");
    const key = [
      report.categoryId,
      report.difficulty,
      report.docId || `texto:${q}`,
    ].join("|");

    if (!groups.has(key)) {
      groups.set(key, {
        categoryId: report.categoryId,
        difficulty: report.difficulty,
        docId: report.docId || "",
        question: report.question,
        count: 0,
        reasons: {},
        details: [],
      });
    }

    const group = groups.get(key);
    group.count++;
    group.reasons[report.reason] = (group.reasons[report.reason] || 0) + 1;
    const detail = String(report.details ?? "").trim();
    if (detail) group.details.push(detail);
  }

  return [...groups.values()].sort((a, b) =>
    b.count - a.count ||
    String(a.categoryId).localeCompare(String(b.categoryId)) ||
    Number(b.difficulty) - Number(a.difficulty)
  );
}

/** La fila del CSV para una pregunta agrupada. */
function rowFor(group, inSource) {
  const options = Array.isArray(group.question?.options) ?
    group.question.options : [];
  const answerIndex = Number(group.question?.answerIndex);
  const answerText = options[answerIndex];

  const reasons = Object.entries(group.reasons)
    .sort((a, b) => b[1] - a[1])
    .map(([reason, n]) => `${REASON_LABELS[reason] || reason} x${n}`)
    .join("; ");

  return [
    group.categoryId,
    group.difficulty,
    group.docId,
    group.question?.q ?? "",
    options[0] ?? "",
    options[1] ?? "",
    options[2] ?? "",
    options[3] ?? "",
    answerText != null ? `${answerIndex + 1}: ${answerText}` : "",
    inSource ? "si" : "no",
    "", "", "", "", "", "", "",
    // Sin docId la pregunta cambio desde que se jugo y apply no la
    // encuentra: hay que buscarla a mano por el texto.
    group.docId ? "" : "sin docId: buscar por texto",
    group.count,
    reasons,
    group.details.join(" | "),
  ];
}

async function run() {
  const admin = require("firebase-admin");

  const argOf = (name, fallback) => {
    const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
    return arg ? arg.slice(name.length + 3) : fallback;
  };
  const SEP = argOf("sep", ",");
  const OUT = path.resolve(
    __dirname,
    argOf("out", path.join("review", "reportes_preguntas.csv"))
  );
  const CLOSE = process.argv.includes("--cerrar");
  const COMMIT = process.argv.includes("--commit");

  admin.initializeApp({
    credential: admin.credential.cert(
      require(path.join(__dirname, "serviceAccountKey.json"))
    ),
  });
  const db = admin.firestore();

  const snap = await db.collection("question_reports")
    .where("status", "==", "open").get();

  if (CLOSE) {
    console.log(
      `${snap.size} reportes abiertos` +
      (COMMIT ? " -> marcando como revisados." : " (dry-run; agrega --commit).")
    );
    if (COMMIT) {
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of snap.docs.slice(i, i + 400)) {
          batch.update(doc.ref, {
            status: "reviewed",
            reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    }
    process.exit(0);
  }

  const groups = groupReports(snap.docs.map((doc) => doc.data()));

  const sources = new Map();
  const sourceOf = (categoryId) => {
    if (!sources.has(categoryId)) {
      const file = path.join(__dirname, "fill_pools", `${categoryId}.js`);
      sources.set(
        categoryId,
        fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null
      );
    }
    return sources.get(categoryId);
  };

  const rows = groups.map((group) => {
    const source = sourceOf(group.categoryId);
    const inSource = Boolean(
      source && source.includes(sourceNeedle(String(group.question?.q ?? "")))
    );
    return rowFor(group, inSource);
  });

  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  fs.writeFileSync(OUT, csv.stringify([HEADER, ...rows], SEP), "utf8");

  console.log(
    `${snap.size} reportes abiertos en ${rows.length} preguntas.\n` +
    `Archivo: ${OUT}\n` +
    "\nRevisalo igual que preguntas_revision.csv (veredicto ok/fix/drop) y:\n" +
    "  node apply_question_fixes.js --in=" +
    path.relative(__dirname, OUT).replace(/\\/g, "/") + "\n" +
    "  node export_question_reports.js --cerrar --commit"
  );
  process.exit(0);
}

if (require.main === module) {
  run().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {groupReports, rowFor, HEADER};
