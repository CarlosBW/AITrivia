/**
 * Valida sin tocar Firestore las preguntas nuevas de `expand_pools/<cat>.js`,
 * las que llevan los pools de 30/40/30 a 60/80/60.
 *
 * Revisa la forma (la misma que acepta seed_fill_pools.js), que traigan su
 * ingles con las mismas opciones, que no repitan una pregunta del banco
 * actual (`translations/<cat>.es.json`) ni entre ellas, cuantas hay por
 * dificultad y que la respuesta correcta no se cargue a una posicion.
 *
 *   node check_expand_pools.js arte
 *   node check_expand_pools.js            # todas las que existan
 */
const fs = require("fs");
const path = require("path");
const {validateQuestion} = require("./question_shape");

/** Preguntas nuevas por dificultad: 60/80/60 menos las 30/40/30 de hoy. */
const NEW_PER_DIFFICULTY = {1: 30, 2: 40, 3: 30};

/** Ninguna posicion de la respuesta puede pasar de esta fraccion. */
const BALANCE_LIMIT = 0.4;

const normalize = (text) => String(text)
  .toLowerCase()
  .normalize("NFD").replace(/[̀-ͯ]/g, "")
  .replace(/[^a-z0-9ñ ]/g, " ")
  .replace(/\s+/g, " ")
  .trim();

function check(cat) {
  const file = path.join(__dirname, "expand_pools", `${cat}.js`);
  delete require.cache[require.resolve(file)];
  const data = require(file);
  const existing = JSON.parse(fs.readFileSync(
    path.join(__dirname, "translations", `${cat}.es.json`), "utf8"
  ));

  const problems = [];
  const seen = new Map(existing.map((e) => [normalize(e.q), `banco ${e.id}`]));

  for (const d of [1, 2, 3]) {
    const list = data[`d${d}`] || [];
    if (list.length !== NEW_PER_DIFFICULTY[d]) {
      problems.push(`d${d}: trae ${list.length}, deben ser ${NEW_PER_DIFFICULTY[d]}`);
    }

    const positions = [0, 0, 0, 0];
    list.forEach((q, i) => {
      const where = `d${d}[${i}]`;
      problems.push(...validateQuestion(q, where));
      if (Number.isInteger(q.answerIndex)) positions[q.answerIndex]++;

      const en = q.en || {};
      if (typeof en.q !== "string" || en.q.trim().length < 8) {
        problems.push(`${where}: falta el ingles (en.q)`);
      }
      if (!Array.isArray(en.options) || en.options.length !== 4 ||
          en.options.some((o) => typeof o !== "string" || !o.trim())) {
        problems.push(`${where}: en.options debe tener 4 opciones`);
      } else if (new Set(en.options.map(normalize)).size !== 4) {
        problems.push(`${where}: en.options repetidas`);
      }

      const key = normalize(q.q);
      if (seen.has(key)) {
        problems.push(`${where}: repite ${seen.get(key)}: "${q.q}"`);
      }
      seen.set(key, where);

      if (typeof q.q === "string" && Array.isArray(q.options) &&
          Number.isInteger(q.answerIndex)) {
        const answer = normalize(q.options[q.answerIndex] || "");
        if (answer.length > 3 && normalize(q.q).includes(answer)) {
          problems.push(`${where}: la respuesta aparece en el enunciado`);
        }
      }
    });

    positions.forEach((n, pos) => {
      if (list.length && n / list.length > BALANCE_LIMIT) {
        problems.push(`d${d}: ${n} de ${list.length} con la respuesta en la opcion ${pos}`);
      }
    });
  }
  return problems;
}

const dir = path.join(__dirname, "expand_pools");
const cats = process.argv[2] ? [process.argv[2]] :
  fs.readdirSync(dir).filter((f) => f.endsWith(".js")).map((f) => f.slice(0, -3));

let failed = false;
for (const cat of cats) {
  const problems = check(cat);
  if (problems.length) {
    failed = true;
    console.log(`${cat}: ${problems.length} problema(s)`);
    problems.forEach((p) => console.log(`  ${p}`));
  } else {
    console.log(`${cat}: OK`);
  }
}
process.exit(failed ? 1 : 0);
