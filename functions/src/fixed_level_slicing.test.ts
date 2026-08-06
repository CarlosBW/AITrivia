import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  FIXED_LEVEL_BANDS,
  FIXED_LEVEL_QUESTION_COUNT,
  difficultyForLevel,
  levelIndexInBand,
  sliceForLevel,
} from "./fixed_level_slicing";

/**
 * A pool of positions in shuffled-but-known order.
 * @param {number} size How many questions the pool holds.
 * @return {number[]} Positions 0..size-1.
 */
function pool(size: number): number[] {
  return [...Array(size).keys()];
}

/**
 * The levels that read a given difficulty tier.
 * @param {number} difficulty Fixed-pool tier (1-3).
 * @return {number[]} Level numbers in that band, ascending.
 */
function levelsOf(difficulty: number): number[] {
  const band = FIXED_LEVEL_BANDS.find((b) => b.difficulty === difficulty);
  assert.ok(band, `no band for difficulty ${difficulty}`);
  const out: number[] = [];
  for (let l = band.firstLevel; l <= band.lastLevel; l++) out.push(l);
  return out;
}

describe("FIXED_LEVEL_BANDS", () => {
  test("covers levels 1-10 with no gaps and no overlap", () => {
    assert.equal(FIXED_LEVEL_BANDS[0].firstLevel, 1);
    assert.equal(
      FIXED_LEVEL_BANDS[FIXED_LEVEL_BANDS.length - 1].lastLevel,
      10
    );
    for (let i = 1; i < FIXED_LEVEL_BANDS.length; i++) {
      assert.equal(
        FIXED_LEVEL_BANDS[i].firstLevel,
        FIXED_LEVEL_BANDS[i - 1].lastLevel + 1,
        "bands must be contiguous"
      );
    }
  });

  test("the seeded pool targets are band size x questions per level", () => {
    // 30/40/30 is what tools/seed_fill_pools.js fills each category to;
    // if a band changes, that target has to change with it.
    const targets = FIXED_LEVEL_BANDS.map(
      (b) => (b.lastLevel - b.firstLevel + 1) * FIXED_LEVEL_QUESTION_COUNT
    );
    assert.deepEqual(targets, [30, 40, 30]);
  });
});

describe("difficultyForLevel", () => {
  test("maps each level to its documented tier", () => {
    assert.deepEqual(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(difficultyForLevel),
      [1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
    );
  });

  test("keeps levels past the last band on the hardest tier", () => {
    // Preserves the original `else return 3` shape rather than returning
    // undefined for a level the bands don't name.
    assert.equal(difficultyForLevel(11), 3);
    assert.equal(difficultyForLevel(99), 3);
  });
});

describe("levelIndexInBand", () => {
  test("numbers each band's levels from zero", () => {
    assert.deepEqual(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(levelIndexInBand),
      [0, 1, 2, 0, 1, 2, 3, 0, 1, 2]
    );
  });

  test("gives every level in a band a distinct index", () => {
    // This is the invariant sliceForLevel depends on: two levels sharing a
    // pool must start at different offsets, or their slates collide.
    for (const band of FIXED_LEVEL_BANDS) {
      const indices = levelsOf(band.difficulty).map(levelIndexInBand);
      assert.equal(
        new Set(indices).size,
        indices.length,
        `difficulty ${band.difficulty} has repeated indices`
      );
    }
  });
});

describe("sliceForLevel", () => {
  test("gives every level in a band a disjoint slate at target size", () => {
    for (const band of FIXED_LEVEL_BANDS) {
      const levels = levelsOf(band.difficulty);
      const size = levels.length * FIXED_LEVEL_QUESTION_COUNT;
      const seen = new Set<number>();

      for (const level of levels) {
        const slice = sliceForLevel(pool(size), level);
        assert.equal(slice.length, FIXED_LEVEL_QUESTION_COUNT);
        for (const q of slice) {
          assert.ok(
            !seen.has(q),
            `level ${level} repeats question ${q} from a sibling level`
          );
          seen.add(q);
        }
      }

      assert.equal(seen.size, size, "the band should consume its whole pool");
    }
  });

  test("never repeats a question inside one level on a short pool", () => {
    // Pools below the band's needs wrap around; the window is capped at the
    // pool size so a single level still can't see the same question twice.
    for (const size of [1, 5, 9, 13, 14]) {
      for (let level = 1; level <= 10; level++) {
        const slice = sliceForLevel(pool(size), level);
        assert.equal(
          new Set(slice).size,
          slice.length,
          `level ${level} on a pool of ${size} repeats a question`
        );
      }
    }
  });

  test("serves the whole pool when it is smaller than a slate", () => {
    const slice = sliceForLevel(pool(4), 1);
    assert.equal(slice.length, 4);
    assert.deepEqual([...slice].sort((a, b) => a - b), [0, 1, 2, 3]);
  });

  test("reads a consecutive window of the shuffled order", () => {
    // The shuffle decides which questions; this only decides where the
    // window starts, so the order handed in must come back untouched.
    const order = [7, 3, 9, 1, 5, 8, 0, 2, 6, 4, 11, 10];
    assert.deepEqual(sliceForLevel(order, 1), order.slice(0, 10));
  });

  test("levels of different bands may share an offset safely", () => {
    // Level 1 and level 4 both start at offset 0, which is fine: they are
    // slicing difficulty_1 and difficulty_2, never the same list.
    assert.equal(levelIndexInBand(1), levelIndexInBand(4));
    assert.notEqual(difficultyForLevel(1), difficultyForLevel(4));
  });
});
