import {strict as assert} from "node:assert";
import {
  createSign,
  generateKeyPairSync,
  KeyObject,
} from "node:crypto";
import {describe, test} from "node:test";

import {
  AD_REWARDS,
  adRewardCounts,
  adRewardKind,
  adUnitIsOurs,
  callbackSignedByAdMob,
  countAdReward,
  parseRewardCallback,
  parseVerifierKeys,
} from "./ad_rewards";

const admob = generateKeyPairSync("ec", {namedCurve: "prime256v1"});
const stranger = generateKeyPairSync("ec", {namedCurve: "prime256v1"});
const KEY_ID = "3335741209";

const keys = parseVerifierKeys({
  keys: [{
    keyId: Number(KEY_ID),
    pem: admob.publicKey.export({type: "spki", format: "pem"}),
    base64: "unused",
  }],
});

const CONTENT =
  "ad_network=5450213213286189855&ad_unit=2747237135" +
  "&custom_data=lives&reward_amount=1&reward_item=Reward" +
  "&timestamp=1794700000000" +
  "&transaction_id=18fa792de1bca816048293fc71035638&user_id=uid_1";

/**
 * A callback's query string as AdMob would send it.
 * @param {string} content The part that is signed.
 * @param {{privateKey: KeyObject}} pair Whose key signs it.
 * @param {string} keyId The key id it claims.
 * @return {string} The full query string.
 */
function signedQuery(
  content: string, pair: {privateKey: KeyObject} = admob, keyId = KEY_ID
): string {
  const signature = createSign("SHA256").update(content)
    .sign(pair.privateKey).toString("base64url");
  return `${content}&signature=${signature}&key_id=${keyId}`;
}

describe("parseRewardCallback", () => {
  test("reads who watched, what for, and which reward it is", () => {
    const callback = parseRewardCallback(signedQuery(CONTENT));

    assert.ok(callback);
    assert.equal(callback.userId, "uid_1");
    assert.equal(callback.customData, "lives");
    assert.equal(callback.adUnit, "2747237135");
    assert.equal(
      callback.transactionId, "18fa792de1bca816048293fc71035638"
    );
    assert.equal(callback.signedContent, CONTENT);
  });

  test("a request without a signature is not a callback", () => {
    assert.equal(parseRewardCallback(CONTENT), null);
    assert.equal(parseRewardCallback(""), null);
    assert.equal(parseRewardCallback(`${CONTENT}&signature=abc`), null);
  });

  test("a callback naming no player or no transaction is refused", () => {
    const noUser = CONTENT.replace("&user_id=uid_1", "");
    const noTransaction = CONTENT.replace(
      "&transaction_id=18fa792de1bca816048293fc71035638", ""
    );

    assert.equal(parseRewardCallback(signedQuery(noUser)), null);
    assert.equal(parseRewardCallback(signedQuery(noTransaction)), null);
  });
});

describe("callbackSignedByAdMob", () => {
  test("accepts what AdMob signed", () => {
    const callback = parseRewardCallback(signedQuery(CONTENT));

    assert.ok(callback);
    assert.equal(callbackSignedByAdMob(callback, keys), true);
  });

  // The point of the signature: a player can't name themselves, or
  // another reward, on a callback they captured.
  test("refuses a callback whose contents were changed", () => {
    const query = signedQuery(CONTENT).replace("uid_1", "uid_2");
    const callback = parseRewardCallback(query);

    assert.ok(callback);
    assert.equal(callbackSignedByAdMob(callback, keys), false);
  });

  test("refuses a signature made with someone else's key", () => {
    const callback = parseRewardCallback(signedQuery(CONTENT, stranger));

    assert.ok(callback);
    assert.equal(callbackSignedByAdMob(callback, keys), false);
  });

  test("refuses a key id AdMob doesn't publish", () => {
    const callback = parseRewardCallback(
      signedQuery(CONTENT, admob, "999")
    );

    assert.ok(callback);
    assert.equal(callbackSignedByAdMob(callback, keys), false);
  });

  test("a signature that isn't one is refused, not thrown", () => {
    const callback = parseRewardCallback(
      `${CONTENT}&signature=not-a-signature&key_id=${KEY_ID}`
    );

    assert.ok(callback);
    assert.equal(callbackSignedByAdMob(callback, keys), false);
  });
});

describe("parseVerifierKeys", () => {
  test("anything but AdMob's key list yields no keys", () => {
    assert.deepEqual(parseVerifierKeys(null), {});
    assert.deepEqual(parseVerifierKeys({keys: "nope"}), {});
    assert.deepEqual(parseVerifierKeys({keys: [{keyId: 1}]}), {});
  });
});

describe("adUnitIsOurs", () => {
  test("accepts a listed unit, as the number or as the full id", () => {
    assert.equal(adUnitIsOurs("2747237135", "2747237135"), true);
    assert.equal(
      adUnitIsOurs(
        "2747237135",
        "ca-app-pub-123/1111111111, ca-app-pub-123/2747237135"
      ),
      true
    );
  });

  // Anyone can have AdMob sign a callback for their own ad unit.
  test("refuses someone else's ad unit", () => {
    assert.equal(adUnitIsOurs("9999999999", "2747237135"), false);
  });

  test("pays nothing while no ad unit is configured", () => {
    assert.equal(adUnitIsOurs("2747237135", ""), false);
    assert.equal(adUnitIsOurs("", ""), false);
    assert.equal(adUnitIsOurs("", "2747237135"), false);
  });
});

describe("adRewardKind", () => {
  test("only the rewards that exist", () => {
    assert.equal(adRewardKind("lives"), "lives");
    assert.equal(adRewardKind("coins"), "coins");
    assert.equal(adRewardKind("xp"), null);
    assert.equal(adRewardKind(""), null);
    assert.equal(adRewardKind(undefined), null);
  });
});

describe("the daily allowance", () => {
  const today = "2026-11-14";

  test("a player who has watched none today starts at zero", () => {
    assert.deepEqual(
      adRewardCounts({}, today), {date: today, lives: 0, coins: 0}
    );
  });

  test("yesterday's counts don't carry over", () => {
    const user = {
      adRewardsDate: "2026-11-13", adLivesToday: 5, adCoinsToday: 5,
    };

    assert.deepEqual(
      adRewardCounts(user, today), {date: today, lives: 0, coins: 0}
    );
  });

  test("each reward counts on its own", () => {
    const counts = adRewardCounts(
      {adRewardsDate: today, adLivesToday: 2, adCoinsToday: 1}, today
    );

    assert.deepEqual(
      countAdReward(counts, "coins"), {date: today, lives: 2, coins: 2}
    );
  });

  test("the cap is the last one paid, the next is refused", () => {
    const cap = AD_REWARDS.lives.dailyCap;
    const oneLeft = adRewardCounts(
      {adRewardsDate: today, adLivesToday: cap - 1}, today
    );
    const spent = countAdReward(oneLeft, "lives");

    assert.ok(spent);
    assert.equal(spent.lives, cap);
    assert.equal(countAdReward(spent, "lives"), null);
    // The other reward's allowance is untouched.
    assert.ok(countAdReward(spent, "coins"));
  });

  test("a count that isn't a number is no count", () => {
    const counts = adRewardCounts(
      {adRewardsDate: today, adLivesToday: "x", adCoinsToday: -3}, today
    );

    assert.deepEqual(counts, {date: today, lives: 0, coins: 0});
  });
});
