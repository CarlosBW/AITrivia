import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  DailyPoolEntry,
  orderByAscendingDifficulty,
  selectDailyEntries,
} from "./daily_question_set";

/**
 * `n` entries of one difficulty, ids prefixed so they stay identifiable.
 * @param {number} difficulty Tier to stamp on every entry.
 * @param {number} n How many entries to build.
 * @param {string} prefix Id prefix.
 * @return {DailyPoolEntry[]} Generated entries.
 */
function entries(
  difficulty: number, n: number, prefix = "q"
): DailyPoolEntry[] {
  return Array.from({length: n}, (_, i) => ({
    c: "cine",
    d: difficulty,
    q: `${prefix}${difficulty}_${i}`,
  }));
}

describe("selectDailyEntries", () => {
  test("takes the requested number from the shuffled order", () => {
    const selected = selectDailyEntries(entries(1, 10), new Set(), 4);

    assert.equal(selected.length, 4);
    assert.deepEqual(selected.map((e) => e.q), [
      "q1_0", "q1_1", "q1_2", "q1_3",
    ]);
  });

  test("prefers questions not served on recent days", () => {
    const pool = entries(1, 4);
    const selected = selectDailyEntries(
      pool, new Set(["q1_0", "q1_1"]), 2
    );

    assert.deepEqual(selected.map((e) => e.q), ["q1_2", "q1_3"]);
  });

  // A short day is worse than a repeated question, so exclusions are a
  // preference and not a filter.
  test("falls back to recent rather than serving a short day", () => {
    const pool = entries(1, 3);
    const selected = selectDailyEntries(
      pool, new Set(["q1_0", "q1_1"]), 3
    );

    assert.equal(selected.length, 3);
    assert.deepEqual(selected.map((e) => e.q).sort(), [
      "q1_0", "q1_1", "q1_2",
    ]);
  });

  test("never returns more than the pool holds", () => {
    assert.equal(selectDailyEntries(entries(1, 3), new Set(), 60).length, 3);
  });

  test("handles an empty pool and a zero limit", () => {
    assert.deepEqual(selectDailyEntries([], new Set(), 10), []);
    assert.deepEqual(selectDailyEntries(entries(1, 5), new Set(), 0), []);
  });
});

describe("orderByAscendingDifficulty", () => {
  test("puts the easy tier first and the hard tier last", () => {
    const mixed = [
      ...entries(3, 2),
      ...entries(1, 2),
      ...entries(2, 2),
    ];

    const ordered = orderByAscendingDifficulty(mixed);

    assert.deepEqual(ordered.map((e) => e.d), [1, 1, 2, 2, 3, 3]);
  });

  // Stability is what keeps the day-to-day mix varying: the incoming order
  // is already shuffled, and only the tiers are rearranged.
  test("keeps the incoming order within a tier", () => {
    const sameTier = [
      {c: "cine", d: 2, q: "b"},
      {c: "cine", d: 2, q: "a"},
      {c: "cine", d: 2, q: "c"},
    ];

    assert.deepEqual(
      orderByAscendingDifficulty(sameTier).map((e) => e.q),
      ["b", "a", "c"]
    );
  });

  test("does not mutate its argument", () => {
    const original = [...entries(3, 1), ...entries(1, 1)];
    const before = original.map((e) => e.q);

    orderByAscendingDifficulty(original);

    assert.deepEqual(original.map((e) => e.q), before);
  });

  test("handles an empty day", () => {
    assert.deepEqual(orderByAscendingDifficulty([]), []);
  });
});
