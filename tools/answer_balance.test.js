/**
 * Vigila donde cae la respuesta correcta en los pools de `fill_pools/`.
 *
 * Existe porque llego a produccion un lote en el que 507 de 900 preguntas
 * tenian la correcta en la primera opcion: responder siempre "la primera"
 * acertaba el 56%. Barajar el orden de las preguntas —lo unico que hacia el
 * juego— no lo tapa, porque mueve las preguntas, no la respuesta dentro de
 * cada una. Y las opciones no se barajan en ningun punto, asi que el
 * `answerIndex` guardado es literalmente la posicion en pantalla.
 *
 * Solo cubre lo que entra por el repo. Las preguntas que ya viven en
 * Firestore y no estan aqui no las ve nadie desde un test estatico.
 *
 *   node --test answer_balance.test.js
 */
const test = require("node:test");
const assert = require("node:assert");

const DATA = require("./fill_pools_data");

const CATEGORIES = Object.keys(DATA).sort();
const DIFFICULTIES = [1, 2, 3];

/** Todas las preguntas, con su procedencia para poder senalarla. */
function everyQuestion() {
  const out = [];
  for (const categoryId of CATEGORIES) {
    for (const difficulty of DIFFICULTIES) {
      const list = DATA[categoryId][`d${difficulty}`] || [];
      list.forEach((q, i) => {
        out.push({categoryId, difficulty, index: i, question: q});
      });
    }
  }
  return out;
}

test("la respuesta correcta no se concentra en una posicion", () => {
  const counts = [0, 0, 0, 0];
  for (const {question} of everyQuestion()) counts[question.answerIndex]++;

  const total = counts.reduce((a, b) => a + b, 0);
  assert.ok(total > 0, "fill_pools no tiene preguntas");

  // Con reparto uniforme cada posicion ronda el 25%. El umbral es holgado
  // a proposito: con ~540 preguntas la desviacion tipica es de un 2%, asi
  // que un 40% no salta por azar, pero el 56% que hubo si lo habria hecho.
  const LIMIT = 0.4;

  counts.forEach((count, position) => {
    const share = count / total;
    assert.ok(
      share <= LIMIT,
      `la posicion ${position + 1} concentra el ${(share * 100).toFixed(0)}% ` +
      `de las respuestas (${count} de ${total}). El maximo tolerado es el ` +
      `${LIMIT * 100}%. Reparte las opciones al escribir el lote, o pasalo ` +
      "por shuffle_question_options.js."
    );
  });
});

test("la respuesta correcta no avanza en ciclo dentro de un bloque", () => {
  for (const categoryId of CATEGORIES) {
    for (const difficulty of DIFFICULTIES) {
      const list = DATA[categoryId][`d${difficulty}`] || [];
      if (list.length < 8) continue;

      const seq = list.map((q) => q.answerIndex);
      let steps = 0;
      for (let i = 1; i < seq.length; i++) {
        if (seq[i] === (seq[i - 1] + 1) % 4) steps++;
      }
      const ratio = steps / (seq.length - 1);

      // 1,2,3,4,1,2,3,4... es el patron que sale de asignar la posicion
      // mecanicamente en vez de elegirla. Un tramo suelto es normal; que
      // lo sea casi todo el bloque, no.
      assert.ok(
        ratio <= 0.9,
        `${categoryId}/d${difficulty}: la respuesta avanza +1 en el ` +
        `${(ratio * 100).toFixed(0)}% de los pasos (${seq.join("")}). ` +
        "Parece asignada en ciclo, no elegida."
      );
    }
  }
});

test("cada pregunta declara una posicion valida", () => {
  for (const {categoryId, difficulty, index, question} of everyQuestion()) {
    const where = `${categoryId}/d${difficulty}[${index}]`;

    assert.ok(
      Array.isArray(question.options) && question.options.length === 4,
      `${where}: se esperaban 4 opciones`
    );
    assert.ok(
      Number.isInteger(question.answerIndex) &&
        question.answerIndex >= 0 &&
        question.answerIndex <= 3,
      `${where}: answerIndex fuera de rango`
    );
    assert.ok(
      typeof question.options[question.answerIndex] === "string" &&
        question.options[question.answerIndex].trim() !== "",
      `${where}: answerIndex apunta a una opcion vacia`
    );
  }
});
