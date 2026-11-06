import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {parseNotifyUids, questionReportAlert} from "./question_report_alert";

describe("parseNotifyUids", () => {
  test("splits on commas and spaces, trimming and dropping repeats", () => {
    assert.deepEqual(
      parseNotifyUids(" abc123 , def456,abc123  ghi789 "),
      ["abc123", "def456", "ghi789"]
    );
  });

  test("an empty setting notifies nobody", () => {
    assert.deepEqual(parseNotifyUids(""), []);
    assert.deepEqual(parseNotifyUids("  ,  "), []);
  });

  test("ignores anything that can't be a uid", () => {
    assert.deepEqual(parseNotifyUids("ok_uid, ../x, a/b"), ["ok_uid"]);
  });
});

describe("questionReportAlert", () => {
  test("names the category, the reason and the question", () => {
    const alert = questionReportAlert("fixed", {
      categoryId: "cine",
      reason: "wrong_answer",
      details: "Fue Spielberg",
      question: {q: "¿Quién dirigió Tiburón?"},
    });
    assert.equal(alert.title, "Pregunta reportada: respuesta mal marcada");
    assert.ok(alert.body.includes("cine"));
    assert.ok(alert.body.includes("¿Quién dirigió Tiburón?"));
    assert.ok(alert.body.includes("Fue Spielberg"));
  });

  test("an AI topic report says it is one, with its level", () => {
    const alert = questionReportAlert("ai", {
      levelNumber: 4,
      reason: "typo",
      questionText: "¿Capital de Peru?",
    });
    assert.ok(alert.body.includes("Tema IA"));
    assert.ok(alert.body.includes("nivel 4"));
    assert.ok(alert.body.includes("¿Capital de Peru?"));
  });

  test("an unknown reason or a missing question still reads", () => {
    const alert = questionReportAlert("fixed", {reason: "???"});
    assert.equal(alert.title, "Pregunta reportada: otro");
    assert.ok(alert.body.length > 0);
  });

  test("keeps the body short enough for a push", () => {
    const alert = questionReportAlert("fixed", {
      reason: "other",
      details: "x".repeat(1000),
      question: {q: "y".repeat(1000)},
    });
    assert.ok(alert.body.length <= 240, `${alert.body.length}`);
  });
});
