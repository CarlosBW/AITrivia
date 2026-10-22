import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  QUESTION_REPORT_REASONS,
  cleanReportDetails,
  fixedReportDocId,
  questionAt,
  reportQuotaAfter,
} from "./question_reports";

describe("QUESTION_REPORT_REASONS", () => {
  test("covers the reasons the review screen offers", () => {
    for (const reason of [
      "wrong_answer", "confusing", "typo", "inappropriate", "other",
    ]) {
      assert.ok(QUESTION_REPORT_REASONS.has(reason), reason);
    }
  });

  test("refuses anything else", () => {
    assert.equal(QUESTION_REPORT_REASONS.has("spam"), false);
    assert.equal(QUESTION_REPORT_REASONS.has(""), false);
  });
});

describe("questionAt", () => {
  const questions = [
    {q: "¿Capital de Perú?", options: ["Lima", "Cusco", "Puno", "Ica"],
      answerIndex: 0, sourceQuestionId: "q12"},
    {q: "¿2+2?", options: ["3", "4"], answerIndex: 1},
  ];

  test("returns the question at that position, with its extra fields", () => {
    const found = questionAt(questions, 0);
    assert.equal(found?.q, "¿Capital de Perú?");
    assert.deepEqual(found?.options, ["Lima", "Cusco", "Puno", "Ica"]);
    assert.equal(found?.answerIndex, 0);
    assert.equal(found?.raw.sourceQuestionId, "q12");
  });

  test("an index outside the list finds nothing", () => {
    assert.equal(questionAt(questions, 2), null);
    assert.equal(questionAt(questions, -1), null);
    assert.equal(questionAt(questions, 0.5), null);
  });

  test("something that isn't a question finds nothing", () => {
    assert.equal(questionAt("nope", 0), null);
    assert.equal(questionAt([{q: "", options: ["a"], answerIndex: 0}], 0),
      null, "no text");
    assert.equal(questionAt([{q: "x", options: [], answerIndex: 0}], 0),
      null, "no options");
    assert.equal(questionAt([{q: "x", options: ["a"], answerIndex: 3}], 0),
      null, "answer outside the options");
  });
});

describe("cleanReportDetails", () => {
  test("trims and caps the comment", () => {
    assert.equal(cleanReportDetails("  hola  "), "hola");
    assert.equal(cleanReportDetails("x".repeat(900)).length, 500);
  });

  test("anything that isn't text is an empty comment", () => {
    assert.equal(cleanReportDetails(undefined), "");
    assert.equal(cleanReportDetails({a: 1}), "");
  });
});

describe("fixedReportDocId", () => {
  test("one report per player and bank question", () => {
    assert.equal(
      fixedReportDocId("u1", "ciencia", 2, "q7"),
      fixedReportDocId("u1", "ciencia", 2, "q7")
    );
    assert.notEqual(
      fixedReportDocId("u1", "ciencia", 2, "q7"),
      fixedReportDocId("u2", "ciencia", 2, "q7")
    );
    assert.notEqual(
      fixedReportDocId("u1", "ciencia", 2, "q7"),
      fixedReportDocId("u1", "ciencia", 3, "q7"),
      "the same id in another difficulty is another question"
    );
  });
});

describe("reportQuotaAfter", () => {
  const MAX = 3;

  test("the first report of the day starts the count", () => {
    assert.deepEqual(reportQuotaAfter(undefined, "2026-10-22", MAX), {
      allowed: true, next: {dayId: "2026-10-22", count: 1},
    });
  });

  test("counts up within the same day", () => {
    assert.deepEqual(
      reportQuotaAfter({dayId: "2026-10-22", count: 2}, "2026-10-22", MAX),
      {allowed: true, next: {dayId: "2026-10-22", count: 3}}
    );
  });

  test("refuses past the daily maximum", () => {
    const after = reportQuotaAfter(
      {dayId: "2026-10-22", count: 3}, "2026-10-22", MAX
    );
    assert.equal(after.allowed, false);
  });

  test("a new day starts over", () => {
    assert.deepEqual(
      reportQuotaAfter({dayId: "2026-10-21", count: 3}, "2026-10-22", MAX),
      {allowed: true, next: {dayId: "2026-10-22", count: 1}}
    );
  });
});
