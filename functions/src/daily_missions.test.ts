import {strict as assert} from "node:assert";
import {describe, test} from "node:test";

import {
  DAILY_MISSIONS_CHEST,
  MISSION_SLOTS,
  MISSION_STATS,
  allMissionsComplete,
  missionProgress,
  missionStats,
  missionsForDate,
  soloLevelMissionStats,
} from "./daily_missions";

describe("missionsForDate", () => {
  test("a day has one mission from each slot", () => {
    const missions = missionsForDate("2026-11-14");

    assert.equal(missions.length, MISSION_SLOTS.length);
    missions.forEach((mission, slot) => {
      assert.ok(MISSION_SLOTS[slot].includes(mission));
    });
  });

  test("the same day always has the same missions", () => {
    assert.deepEqual(
      missionsForDate("2026-11-14"), missionsForDate("2026-11-14")
    );
  });

  test("the next day's are different", () => {
    const today = missionsForDate("2026-11-14").map((m) => m.id);
    const tomorrow = missionsForDate("2026-11-15").map((m) => m.id);

    assert.notDeepEqual(today, tomorrow);
  });

  // The app works out the same missions on its own; these pin both
  // sides to one answer (see daily_missions_sync_test.dart).
  test("known days", () => {
    assert.deepEqual(
      missionsForDate("2026-11-14").map((m) => m.id),
      ["correct_20", "solo_levels_3", "great_level"]
    );
    assert.deepEqual(
      missionsForDate("2026-11-15").map((m) => m.id),
      ["correct_15", "play_daily", "streak_level"]
    );
    assert.deepEqual(
      missionsForDate("2026-11-16").map((m) => m.id),
      ["correct_25", "solo_levels_2", "great_level"]
    );
  });

  test("over a stretch of days every mission comes up", () => {
    const seen = new Set<string>();
    for (let day = 1; day <= 28; day++) {
      const dateId = `2026-02-${String(day).padStart(2, "0")}`;
      missionsForDate(dateId).forEach((m) => seen.add(m.id));
    }

    for (const mission of MISSION_SLOTS.flat()) {
      assert.ok(seen.has(mission.id), mission.id);
    }
  });

  test("a date that isn't one has no missions", () => {
    assert.deepEqual(missionsForDate("hoy"), []);
    assert.deepEqual(missionsForDate(""), []);
  });
});

describe("the mission table", () => {
  test("ids are unique and every stat exists", () => {
    const ids = MISSION_SLOTS.flat().map((m) => m.id);

    assert.equal(new Set(ids).size, ids.length);
    for (const mission of MISSION_SLOTS.flat()) {
      assert.ok(MISSION_STATS.includes(mission.stat));
      assert.ok(mission.target > 0);
    }
  });

  test("the chest pays something", () => {
    assert.ok(DAILY_MISSIONS_CHEST.coins > 0);
    assert.ok(DAILY_MISSIONS_CHEST.xp > 0);
  });
});

describe("missionStats", () => {
  test("a day with nothing recorded is all zeros", () => {
    const stats = missionStats(undefined);

    for (const stat of MISSION_STATS) assert.equal(stats[stat], 0);
  });

  test("anything that isn't a count is zero", () => {
    const stats = missionStats({correct: "x", soloLevels: -2, dailyPlayed: 1});

    assert.equal(stats.correct, 0);
    assert.equal(stats.soloLevels, 0);
    assert.equal(stats.dailyPlayed, 1);
  });
});

describe("progress and the chest", () => {
  const dateId = "2026-11-15"; // correct_15, play_daily, streak_level

  test("progress never passes the target", () => {
    const [correct15] = missionsForDate(dateId);

    assert.equal(
      missionProgress(correct15, missionStats({correct: 7})), 7
    );
    assert.equal(
      missionProgress(correct15, missionStats({correct: 40})), 15
    );
  });

  test("the chest is due only with all three done", () => {
    assert.equal(
      allMissionsComplete(dateId, missionStats({
        correct: 15, dailyPlayed: 1, streakLevels: 1,
      })),
      true
    );
    assert.equal(
      allMissionsComplete(dateId, missionStats({
        correct: 14, dailyPlayed: 1, streakLevels: 1,
      })),
      false
    );
    assert.equal(allMissionsComplete(dateId, missionStats({})), false);
  });

  // Doing another day's missions doesn't open today's chest.
  test("counts that belong to other missions don't count", () => {
    assert.equal(
      allMissionsComplete(dateId, missionStats({
        correct: 15, soloLevels: 4, weeklyRounds: 5, greatLevels: 3,
      })),
      false
    );
  });

  test("a date that isn't one never has a chest", () => {
    assert.equal(
      allMissionsComplete("hoy", missionStats({correct: 99})), false
    );
  });
});

describe("soloLevelMissionStats", () => {
  test("a level counts as played, with its right answers", () => {
    assert.deepEqual(
      soloLevelMissionStats(6, 10, 2), {soloLevels: 1, correct: 6}
    );
  });

  test("nine of ten is a great level", () => {
    assert.equal(soloLevelMissionStats(9, 10, 4).greatLevels, 1);
    assert.equal(soloLevelMissionStats(8, 10, 4).greatLevels, undefined);
  });

  test("five in a row counts for the streak mission", () => {
    assert.equal(soloLevelMissionStats(7, 10, 5).streakLevels, 1);
    assert.equal(soloLevelMissionStats(7, 10, 4).streakLevels, undefined);
  });

  test("a level with nothing right still counts as played", () => {
    assert.deepEqual(soloLevelMissionStats(0, 10, 0), {soloLevels: 1});
  });
});
