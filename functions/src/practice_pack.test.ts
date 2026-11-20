import {test} from "node:test";
import * as assert from "node:assert/strict";

import {
  PRACTICE_PACK_MIN_INTERVAL_MS,
  PRACTICE_PACK_SIZE,
  practicePackDue,
  practiceQuestion,
  selectPracticeEntries,
} from "./practice_pack";

const NOW = 1_800_000_000_000;

test("a player who never took a pack may take one", () => {
  assert.equal(practicePackDue(null, NOW), true);
  assert.equal(practicePackDue(NaN, NOW), true);
});

test("a second pack waits out the interval", () => {
  assert.equal(practicePackDue(NOW - 60_000, NOW), false);
  assert.equal(
    practicePackDue(NOW - PRACTICE_PACK_MIN_INTERVAL_MS + 1, NOW), false
  );
  assert.equal(
    practicePackDue(NOW - PRACTICE_PACK_MIN_INTERVAL_MS, NOW), true
  );
});

test("a stamp from the future does not lock the player out", () => {
  assert.equal(practicePackDue(NOW + 86_400_000, NOW), true);
});

const entries = Array.from({length: 500}, (_, i) => ({
  c: `cat${i % 5}`, d: 1 + (i % 3), q: `q${i}`,
}));

test("a pack holds its size, without repeats", () => {
  const picked = selectPracticeEntries(entries, 42);
  assert.equal(picked.length, PRACTICE_PACK_SIZE);
  assert.equal(new Set(picked.map((e) => e.q)).size, PRACTICE_PACK_SIZE);
});

test("the same seed draws the same pack, another seed a different one", () => {
  const a = selectPracticeEntries(entries, 7).map((e) => e.q);
  const b = selectPracticeEntries(entries, 7).map((e) => e.q);
  const c = selectPracticeEntries(entries, 8).map((e) => e.q);
  assert.deepEqual(a, b);
  assert.notDeepEqual(a, c);
});

test("a pack draws from every category", () => {
  const picked = selectPracticeEntries(entries, 3);
  assert.equal(new Set(picked.map((e) => e.c)).size, 5);
});

test("a bank smaller than a pack gives all it has", () => {
  assert.equal(selectPracticeEntries(entries.slice(0, 12), 1).length, 12);
  assert.deepEqual(selectPracticeEntries([], 1), []);
});

const stored = {
  q: "¿Capital de Perú?",
  options: ["Lima", "Cusco", "Arequipa", "Trujillo"],
  answerIndex: 0,
  q_en: "Capital of Peru?",
  options_en: ["Lima", "Cusco", "Arequipa", "Trujillo"],
  explanation: "Lima es la capital.",
  createdAt: 123,
};

test("a question carries what a round needs and nothing else", () => {
  assert.deepEqual(practiceQuestion(stored, "geo"), {
    categoryId: "geo",
    q: "¿Capital de Perú?",
    options: ["Lima", "Cusco", "Arequipa", "Trujillo"],
    answerIndex: 0,
    q_en: "Capital of Peru?",
    options_en: ["Lima", "Cusco", "Arequipa", "Trujillo"],
  });
});

test("English that doesn't line up with the Spanish is left out", () => {
  const question = practiceQuestion(
    {...stored, options_en: ["Lima", "Cusco"]}, "geo"
  );
  assert.equal(question?.q_en, undefined);
  assert.equal(question?.options_en, undefined);
  assert.equal(question?.q, "¿Capital de Perú?");
});

test("a question that can't be played is dropped", () => {
  assert.equal(practiceQuestion(null, "geo"), null);
  assert.equal(practiceQuestion({...stored, q: "  "}, "geo"), null);
  assert.equal(practiceQuestion({...stored, options: ["Lima"]}, "geo"), null);
  assert.equal(
    practiceQuestion({...stored, options: ["Lima", ""]}, "geo"), null
  );
  assert.equal(practiceQuestion({...stored, answerIndex: 4}, "geo"), null);
  assert.equal(practiceQuestion({...stored, answerIndex: -1}, "geo"), null);
  assert.equal(practiceQuestion({...stored, answerIndex: "0"}, "geo"), null);
});
