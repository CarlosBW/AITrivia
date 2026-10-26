import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  asyncMatchScrub,
  deletedPlayerName,
  leaderboardEntryPaths,
  liveMatchScrub,
} from "./account_deletion";

describe("deletedPlayerName", () => {
  test("speaks the reader's language", () => {
    assert.equal(deletedPlayerName("en"), "Deleted player");
    assert.equal(deletedPlayerName("es"), "Jugador eliminado");
  });

  test("falls back to Spanish, like the rest of the app", () => {
    assert.equal(deletedPlayerName(undefined), "Jugador eliminado");
    assert.equal(deletedPlayerName("fr"), "Jugador eliminado");
  });
});

describe("liveMatchScrub", () => {
  const finished = {
    hostUid: "gone",
    guestUid: "opp",
    status: "finished",
    rewarded: true,
    players: {
      gone: {displayName: "carlos", avatarId: "avatar_7",
        equippedFrame: "gold", bestLeagueId: "gold", score: 4},
      opp: {displayName: "ana", avatarId: "avatar_2", score: 6},
    },
  };

  test("renames the deleted seat and leaves the scores alone", () => {
    const scrub = liveMatchScrub(finished, "gone", "Deleted player");
    assert.deepEqual(scrub, {
      opponentUid: "opp",
      closed: false,
      patch: {
        "players.gone.displayName": "Deleted player",
        "players.gone.avatarId": "avatar_1",
        "players.gone.equippedFrame": "",
        "players.gone.bestLeagueId": "",
      },
    });
  });

  test("works from the guest seat too", () => {
    const scrub = liveMatchScrub(
      {...finished, hostUid: "opp", guestUid: "gone"}, "gone", "x"
    );
    assert.equal(scrub?.opponentUid, "opp");
    assert.equal(scrub?.patch["players.gone.displayName"], "x");
  });

  test("closes an unsettled match so it can't pay the deleted player", () => {
    const scrub = liveMatchScrub(
      {...finished, status: "playing", rewarded: false}, "gone", "x"
    );
    assert.equal(scrub?.closed, true);
    assert.equal(scrub?.patch.status, "cancelled");
    assert.equal(scrub?.patch.rewarded, true);
  });

  test("closes an open room nobody joined, with no opponent", () => {
    const scrub = liveMatchScrub({
      hostUid: "gone", guestUid: null, status: "waiting", rewarded: false,
      players: {gone: {displayName: "carlos"}},
    }, "gone", "x");
    assert.equal(scrub?.opponentUid, null);
    assert.equal(scrub?.closed, true);
  });

  test("leaves an already cancelled match closed as it was", () => {
    const scrub = liveMatchScrub(
      {...finished, status: "cancelled", rewarded: false}, "gone", "x"
    );
    assert.equal(scrub?.closed, false);
    assert.equal(scrub?.patch.status, undefined);
  });

  test("ignores a match the player isn't in", () => {
    assert.equal(liveMatchScrub(finished, "someone", "x"), null);
    assert.equal(liveMatchScrub(undefined, "gone", "x"), null);
  });
});

describe("asyncMatchScrub", () => {
  const settled = {
    challengerUid: "gone",
    challengedUid: "opp",
    challengerDisplayName: "carlos",
    challengedDisplayName: "ana",
    status: "finished",
    rewarded: true,
  };

  test("renames the deleted side of a settled match", () => {
    assert.deepEqual(asyncMatchScrub(settled, "gone", "Deleted player"), {
      opponentUid: "opp",
      closed: false,
      patch: {challengerDisplayName: "Deleted player"},
    });
    assert.deepEqual(
      asyncMatchScrub(
        {...settled, challengerUid: "opp", challengedUid: "gone"},
        "gone", "x"
      )?.patch,
      {challengedDisplayName: "x"}
    );
  });

  test("declines one still in play, as the deleted player", () => {
    const scrub = asyncMatchScrub(
      {...settled, status: "waiting_challenged", rewarded: false},
      "gone", "x"
    );
    assert.equal(scrub?.closed, true);
    assert.deepEqual(scrub?.patch, {
      challengerDisplayName: "x",
      status: "declined",
      declinedByUid: "gone",
      rewarded: true,
    });
  });

  test("leaves one that was already declined as it was", () => {
    const scrub = asyncMatchScrub(
      {...settled, status: "declined", declinedByUid: "opp", rewarded: false},
      "gone", "x"
    );
    assert.equal(scrub?.closed, false);
    assert.deepEqual(scrub?.patch, {challengerDisplayName: "x"});
  });

  test("ignores a match the player isn't in", () => {
    assert.equal(asyncMatchScrub(settled, "someone", "x"), null);
    assert.equal(asyncMatchScrub(null, "gone", "x"), null);
  });
});

describe("leaderboardEntryPaths", () => {
  const leagues = ["bronze", "silver"];

  test("one daily row per day and one weekly row per week and league", () => {
    // 2026-10-19 is a Monday; the 20th falls in the same week.
    assert.deepEqual(
      leaderboardEntryPaths("gone", ["2026-10-19", "2026-10-20"], leagues),
      [
        "daily_leaderboards/2026-10-19/players/gone",
        "daily_leaderboards/2026-10-20/players/gone",
        "weekly_leagues/2026-10-19/bronze/gone",
        "weekly_leagues/2026-10-19/silver/gone",
      ]
    );
  });

  test("skips ids that aren't dates instead of building odd paths", () => {
    assert.deepEqual(
      leaderboardEntryPaths(
        "gone", ["", "x/y", "2026-13-99", "2026-02-30"], leagues
      ),
      []
    );
  });

  test("nothing played, nothing to delete", () => {
    assert.deepEqual(leaderboardEntryPaths("gone", [], leagues), []);
  });
});
