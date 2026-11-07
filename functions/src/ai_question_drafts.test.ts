import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {acceptModelQuestions} from "./ai_question_drafts";

const draft = (q: string, correct = "Sí") => ({
  q,
  correctAnswer: correct,
  wrongAnswers: ["No", "Tal vez", "Nunca"],
  explanation: "",
});

describe("acceptModelQuestions", () => {
  test("takes only as many as are still needed", () => {
    const drafts = Array.from({length: 11}, (_, i) => draft(`Pregunta ${i}`));
    assert.equal(acceptModelQuestions(drafts, [], 10).length, 10);
  });

  // A topic used to fail outright when the model wrote 9 instead of 10.
  test("keeps a short batch, so only the rest has to be asked for", () => {
    const drafts = Array.from({length: 9}, (_, i) => draft(`Pregunta ${i}`));
    assert.equal(acceptModelQuestions(drafts, [], 10).length, 9);
  });

  test("drops a malformed question instead of the whole batch", () => {
    const bad = {...draft("Rota"), wrongAnswers: ["No", "No", "No"]};
    const got = acceptModelQuestions([draft("Buena"), bad], [], 10);
    assert.deepEqual(got.map((q) => q.q), ["Buena"]);
  });

  test("skips repeats of what is already kept, and within the batch", () => {
    const got = acceptModelQuestions(
      [draft("¿Qué es?"), draft("¿que es"), draft("Otra")],
      ["Otra"],
      10
    );
    assert.deepEqual(got.map((q) => q.q), ["¿Qué es?"]);
  });

  test("lays the answers out with the correct one where it says", () => {
    const [q] = acceptModelQuestions([draft("Pregunta", "Correcta")], [], 1);
    assert.equal(q.options[q.answerIndex], "Correcta");
  });
});
