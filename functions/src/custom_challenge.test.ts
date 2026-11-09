import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  CUSTOM_CHALLENGE_TIMEOUT_SECONDS,
  customChallengeBudgetUnits,
  customChallengeLanguages,
  customChallengeLevel,
  withEnglishVersion,
} from "./custom_challenge";

describe("customChallengeBudgetUnits", () => {
  // One unit of the daily limit is one level: ten generated questions.
  test("up to ten questions cost one level", () => {
    assert.equal(customChallengeBudgetUnits(5), 1);
    assert.equal(customChallengeBudgetUnits(10), 1);
  });

  test("fifteen questions cost two levels", () => {
    assert.equal(customChallengeBudgetUnits(15), 2);
  });

  test("a nonsense count still costs one level", () => {
    assert.equal(customChallengeBudgetUnits(0), 1);
    assert.equal(customChallengeBudgetUnits(-3), 1);
  });
});

describe("customChallengeLevel", () => {
  // Generation scales difficulty by level number: 1-3 easy, 4-7 medium,
  // 8-10 hard.
  test("each challenge difficulty lands in its level band", () => {
    assert.equal(customChallengeLevel(1), 2);
    assert.equal(customChallengeLevel(2), 5);
    assert.equal(customChallengeLevel(3), 9);
  });

  test("an out-of-range difficulty falls back to medium", () => {
    assert.equal(customChallengeLevel(0), 5);
    assert.equal(customChallengeLevel(7), 5);
  });
});

describe("customChallengeLanguages", () => {
  // The bank's convention: Spanish in q/options, English in q_en/options_en.
  test("two Spanish players: Spanish only", () => {
    assert.deepEqual(customChallengeLanguages("es", "es"),
      {generateIn: "es", addEnglish: false});
  });

  test("two English players: English only, which both read as is", () => {
    assert.deepEqual(customChallengeLanguages("en", "en"),
      {generateIn: "en", addEnglish: false});
  });

  test("one of each: Spanish, with the English version alongside", () => {
    assert.deepEqual(customChallengeLanguages("en", "es"),
      {generateIn: "es", addEnglish: true});
    assert.deepEqual(customChallengeLanguages("es", "en"),
      {generateIn: "es", addEnglish: true});
  });

  test("an unset language counts as Spanish, like everywhere else", () => {
    assert.deepEqual(customChallengeLanguages(undefined, "es"),
      {generateIn: "es", addEnglish: false});
  });
});

describe("withEnglishVersion", () => {
  const question = {
    q: "¿Capital de Perú?",
    options: ["Lima", "Cusco", "Arequipa", "Trujillo"],
    answerIndex: 0,
  };

  test("adds the translation in the same option order", () => {
    assert.deepEqual(withEnglishVersion(question, {
      q: "Capital of Peru?",
      options: ["Lima", "Cusco", "Arequipa", "Trujillo"],
    }), {
      ...question,
      q_en: "Capital of Peru?",
      options_en: ["Lima", "Cusco", "Arequipa", "Trujillo"],
    });
  });

  test("a translation that lost an option is left out", () => {
    // A shorter list could put the right answer under the wrong text.
    assert.deepEqual(withEnglishVersion(question, {
      q: "Capital of Peru?",
      options: ["Lima", "Cusco", "Arequipa"],
    }), question);
  });

  test("an empty or missing translation is left out", () => {
    assert.deepEqual(withEnglishVersion(question, {q: " ", options: []}),
      question);
    assert.deepEqual(withEnglishVersion(question, undefined), question);
  });
});

describe("CUSTOM_CHALLENGE_TIMEOUT_SECONDS", () => {
  test("leaves room to generate and translate", () => {
    assert.ok(CUSTOM_CHALLENGE_TIMEOUT_SECONDS >= 240);
  });
});
