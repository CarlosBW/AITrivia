const {test} = require("node:test");
const assert = require("node:assert/strict");

const {planCategory} = require("./apply_translations");

const es = [
  {d: 1, id: "q1", q: "¿Capital de Perú?", options: ["Lima", "Cusco"]},
  {d: 2, id: "q1", q: "¿2+2?", options: ["3", "4"]},
];
const en = [
  {d: 1, id: "q1", q: "Capital of Peru?", options: ["Lima", "Cusco"]},
  {d: 2, id: "q1", q: "2+2?", options: ["3", "4"]},
];
const liveOf = (entries) =>
  new Map(entries.map((e) => [`${e.d}/${e.id}`, {...e, answerIndex: 0}]));

test("escribe cada traduccion cuyo espanol no cambio", () => {
  const {updates, skipped} = planCategory(es, en, liveOf(es));
  assert.equal(updates.length, 2);
  assert.deepEqual(updates[0], {
    d: 1, id: "q1", q_en: "Capital of Peru?", options_en: ["Lima", "Cusco"],
  });
  assert.equal(skipped.length, 0);
});

test("salta una pregunta corregida despues de exportar", () => {
  const live = liveOf([{...es[0], q: "¿Cuál es la capital de Perú?"}, es[1]]);
  const {updates, skipped} = planCategory(es, en, live);
  assert.deepEqual(updates.map((u) => u.d), [2]);
  assert.deepEqual(skipped, [
    {key: "1/q1", reason: "el espanol cambio desde la exportacion"},
  ]);
});

test("salta una traduccion con otra cantidad de opciones", () => {
  const broken = [{...en[0], options: ["Lima"]}, en[1]];
  const {skipped} = planCategory(es, broken, liveOf(es));
  assert.equal(skipped[0].reason, "traduccion incompleta");
});

test("salta lo que ya no existe o ya esta escrito", () => {
  const live = liveOf([es[1]]);
  live.get("2/q1").q_en = "2+2?";
  live.get("2/q1").options_en = ["3", "4"];
  const {updates, skipped} = planCategory(es, en, live);
  assert.equal(updates.length, 0);
  assert.deepEqual(skipped.map((s) => s.reason), [
    "ya no existe en Firestore", "ya estaba igual",
  ]);
});

test("archivos desalineados no escriben nada", () => {
  const {updates, skipped} = planCategory(es, [en[0]], liveOf(es));
  assert.equal(updates.length, 0);
  assert.equal(skipped[0].key, "*");

  const swapped = planCategory(es, [en[1], en[0]], liveOf(es));
  assert.equal(swapped.updates.length, 0);
});
