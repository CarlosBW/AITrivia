import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  MAX_PLAYER_REPORTS_PER_DAY,
  PLAYER_REPORT_REASONS,
  playerReportDocId,
  usernameViolation,
} from "./player_safety";

describe("usernameViolation", () => {
  test("lets ordinary names through", () => {
    for (const name of [
      "carlos", "Ana_2026", "TriviaFan", "ElProfe99", "maria_jose",
      "computadora", "diputado", "Vergara", "MariCarmen", "grape_juice",
      "Dickens", "scunthorpe", "Player1a2b3c4d",
    ]) {
      assert.equal(usernameViolation(name), null, name);
    }
  });

  test("blocks insults, in Spanish and English", () => {
    for (const name of [
      "pendejo", "ElPendejo99", "hijodeputa", "maricon", "cabron_",
      "fuck_you", "bitch", "shithead",
    ]) {
      assert.equal(usernameViolation(name), "offensive", name);
    }
  });

  // Short words that are also parts of ordinary words only count as a
  // whole word: "puta" is blocked, "computadora" isn't.
  test("blocks short insults only as a whole word", () => {
    for (const name of ["puta", "Puta123", "la_puta", "LaPuta", "culo"]) {
      assert.equal(usernameViolation(name), "offensive", name);
    }
  });

  test("sees through repeated letters and digits for letters", () => {
    for (const name of ["peeendejo", "p3nd3j0", "Pu7a", "fuuuck"]) {
      assert.equal(usernameViolation(name), "offensive", name);
    }
  });

  test("blocks hate and sexual terms", () => {
    for (const name of ["hitler_88", "nazi", "porno", "xxx"]) {
      assert.equal(usernameViolation(name), "offensive", name);
    }
  });

  // Nobody should be able to pass for the game's own staff.
  test("reserves names that look official", () => {
    for (const name of [
      "admin", "TriviaIA", "triviaia_oficial", "Soporte", "moderador",
      "staff_team", "MassiveDynamics",
    ]) {
      assert.equal(usernameViolation(name), "reserved", name);
    }
  });
});

describe("player reports", () => {
  test("offers a fixed set of reasons", () => {
    assert.deepEqual([...PLAYER_REPORT_REASONS].sort(), [
      "cheating", "offensive_name", "other", "spam_or_harassment",
    ]);
  });

  test("one report per reporter and player", () => {
    assert.equal(playerReportDocId("me", "them"), "me__them");
  });

  test("caps reports per day", () => {
    assert.ok(MAX_PLAYER_REPORTS_PER_DAY > 0);
    assert.ok(MAX_PLAYER_REPORTS_PER_DAY <= 30);
  });
});
