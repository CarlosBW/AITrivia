const {test} = require("node:test");
const assert = require("node:assert/strict");

const {groupReports, rowFor, HEADER} = require("./export_question_reports");

const question = {
  q: "¿Capital de Australia?",
  options: ["Sídney", "Canberra", "Melbourne", "Perth"],
  answerIndex: 1,
};

const report = (over) => ({
  categoryId: "geografia",
  difficulty: 2,
  docId: "q7",
  question,
  reason: "wrong_answer",
  details: "",
  ...over,
});

test("junta los reportes de una misma pregunta", () => {
  const groups = groupReports([
    report({}),
    report({reason: "confusing", details: "no se entiende"}),
    report({reason: "wrong_answer"}),
  ]);

  assert.equal(groups.length, 1);
  assert.equal(groups[0].count, 3);
  assert.deepEqual(groups[0].reasons, {wrong_answer: 2, confusing: 1});
  assert.deepEqual(groups[0].details, ["no se entiende"]);
});

test("la misma docId en otra dificultad es otra pregunta", () => {
  const groups = groupReports([report({}), report({difficulty: 3})]);
  assert.equal(groups.length, 2);
});

test("sin docId, agrupa por el texto", () => {
  const groups = groupReports([
    report({docId: null}),
    report({docId: null}),
    report({docId: null, question: {...question, q: "Otra"}}),
  ]);
  assert.deepEqual(groups.map((g) => g.count), [2, 1]);
});

test("las mas reportadas van primero", () => {
  const groups = groupReports([
    report({docId: "q1"}),
    report({docId: "q2"}),
    report({docId: "q2"}),
  ]);
  assert.deepEqual(groups.map((g) => g.docId), ["q2", "q1"]);
});

test("la fila tiene las columnas que apply_question_fixes necesita", () => {
  const [group] = groupReports([report({}), report({reason: "typo"})]);
  const row = rowFor(group, true);
  const cell = (name) => row[HEADER.indexOf(name)];

  assert.equal(row.length, HEADER.length);
  assert.equal(cell("categoria"), "geografia");
  assert.equal(cell("dificultad"), 2);
  assert.equal(cell("docId"), "q7");
  assert.equal(cell("pregunta"), "¿Capital de Australia?");
  assert.equal(cell("correcta_actual"), "2: Canberra");
  assert.equal(cell("en_fuente"), "si");
  assert.equal(cell("veredicto"), "");
  assert.equal(cell("reportes"), 2);
  assert.match(cell("motivos"), /respuesta mal marcada x1/);
  assert.match(cell("motivos"), /ortografia\/traduccion x1/);
});

test("avisa cuando no hay docId que aplicar", () => {
  const [group] = groupReports([report({docId: null})]);
  const row = rowFor(group, false);
  assert.equal(row[HEADER.indexOf("notas")], "sin docId: buscar por texto");
});
