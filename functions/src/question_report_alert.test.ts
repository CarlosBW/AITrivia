import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {questionReportEmail} from "./question_report_alert";

const louvre = {
  q: "¿Qué museo de París tiene una pirámide de vidrio en su entrada?",
  options: ["Orsay", "Pompidou", "El Louvre", "Rodin"],
  answerIndex: 2,
};

describe("questionReportEmail", () => {
  test("the subject names the reason and the category", () => {
    const email = questionReportEmail("fixed", "r1", {
      reason: "wrong_answer",
      categoryId: "arte",
      difficulty: 1,
      question: louvre,
    });
    assert.equal(
      email.subject,
      "[TriviaIA] Pregunta reportada (respuesta mal marcada): arte, " +
        "dificultad 1"
    );
  });

  test("lists every option, marking the right one and the player's", () => {
    const email = questionReportEmail("fixed", "r1", {
      reason: "wrong_answer",
      categoryId: "arte",
      difficulty: 1,
      question: louvre,
      selectedIndex: 0,
      details: "Creo que es otro",
    });
    assert.ok(email.text.includes(louvre.q));
    assert.ok(email.text.includes("C. El Louvre  ← correcta"));
    assert.ok(email.text.includes("A. Orsay  ← eligió el jugador"));
    assert.ok(email.text.includes("Comentario: Creo que es otro"));
    assert.ok(email.text.includes("dificultad 1"));
  });

  test("the player picking the right answer is marked once", () => {
    const email = questionReportEmail("fixed", "r1", {
      question: louvre,
      selectedIndex: 2,
    });
    assert.ok(email.text.includes(
      "C. El Louvre  ← correcta, eligió el jugador"
    ));
  });

  test("says when the player didn't answer, or the app didn't say", () => {
    const timedOut = questionReportEmail("fixed", "r1", {
      question: louvre,
      selectedIndex: null,
    });
    assert.ok(timedOut.text.includes("no respondió"));

    const oldApp = questionReportEmail("fixed", "r1", {question: louvre});
    assert.ok(oldApp.text.includes("no registrada"));
  });

  test("an AI topic report says so, with its level", () => {
    const email = questionReportEmail("ai", "r2", {
      reason: "typo",
      levelNumber: 4,
      questionText: "¿Capital de Peru?",
    });
    assert.ok(email.subject.includes("Tema IA, nivel 4"));
    assert.ok(email.text.includes("¿Capital de Peru?"));
  });

  test("links to the report in the console", () => {
    const fixed = questionReportEmail("fixed", "abc", {question: louvre});
    assert.ok(fixed.text.includes("~2Fquestion_reports~2Fabc"));
    const ai = questionReportEmail("ai", "def", {questionText: "x"});
    assert.ok(ai.text.includes("~2Fai_question_reports~2Fdef"));
  });

  test("an unknown reason or an empty report still reads", () => {
    const email = questionReportEmail("fixed", "r1", {reason: "???"});
    assert.ok(email.subject.includes("(otro)"));
    assert.ok(email.text.length > 0);
  });

  test("player text can't inject markup into the html", () => {
    const email = questionReportEmail("fixed", "r1", {
      details: "<script>alert(1)</script>",
      question: {...louvre, q: "<b>¿Qué?</b>"},
    });
    assert.ok(!email.html.includes("<script>"));
    assert.ok(!email.html.includes("<b>¿Qué?</b>"));
    assert.ok(email.html.includes("&lt;script&gt;"));
  });
});
