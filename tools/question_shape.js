/**
 * Forma de una pregunta de pool, compartida por los scripts que las escriben.
 *
 * Vive aparte porque `seed_fill_pools.js` (que las inserta) y
 * `apply_question_fixes.js` (que las corrige) tienen que aceptar exactamente
 * lo mismo: si el segundo fuera mas permisivo, podria dejar en Firestore una
 * pregunta que el primero habria rechazado.
 */

/** Valida la forma de una pregunta. Devuelve una lista de problemas. */
function validateQuestion(q, where) {
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

/**
 * Serializa una pregunta con el formato exacto de una linea de
 * `fill_pools/<categoria>.js`, indentacion y coma final incluidas.
 *
 * `JSON.stringify` produce las mismas comillas y escapes que usan esos
 * archivos, que es lo que permite localizar una pregunta existente buscando
 * su texto serializado en lugar de tener que parsear el modulo.
 */
function sourceLine(q, indent = "    ") {
  const options = q.options.map((o) => JSON.stringify(o)).join(", ");
  return `${indent}{q: ${JSON.stringify(q.q)}, options: [${options}], ` +
    `answerIndex: ${q.answerIndex}},`;
}

/** Fragmento por el que se localiza una pregunta ya escrita en la fuente. */
function sourceNeedle(questionText) {
  return `{q: ${JSON.stringify(questionText)},`;
}

module.exports = {validateQuestion, sourceLine, sourceNeedle};
