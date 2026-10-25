import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {createPrivateKey, sign, X509Certificate} from "node:crypto";

import {verifyAppStoreTransaction} from "./app_store_jws";

// A throwaway chain built like Apple's: a root, an intermediate carrying
// Apple's intermediate marker (1.2.840.113635.100.6.2.1) and a leaf
// carrying the App Store receipt-signing marker (1.2.840.113635.100.6.11.1).
// "plain" is the same key under a leaf without the marker — what any other
// certificate under Apple's root looks like.
const ROOT =
  "MIIBTzCB9aADAgECAhQlDEfOmX8IRDP0VVirhvPmXplLtDAKBggqhkjOPQQDAjAU" +
  "MRIwEAYDVQQDDAlUZXN0IFJvb3QwIBcNMjYxMDI1MTgzMzAxWhgPMjEyNjEwMDEx" +
  "ODMzMDFaMBQxEjAQBgNVBAMMCVRlc3QgUm9vdDBZMBMGByqGSM49AgEGCCqGSM49" +
  "AwEHA0IABFcPXF0k/oZw+9HDxYafszovV9quQiqYP77w2X/eTPB85YchY2jNtOo1" +
  "si3RKonlBLPBblb7Ur2xr7UnW0isalKjIzAhMA8GA1UdEwEB/wQFMAMBAf8wDgYD" +
  "VR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0kAMEYCIQDGtaqTj5GUBxWMWfFrG1uw" +
  "BJNMbudc3ayhb5/ew5QMcgIhANFPciN4WeQkhhXJeM62zigtjBhtSiiU4n8KZz1F" +
  "8Ry2";
const INTERMEDIATE =
  "MIIBbTCCARKgAwIBAgIUdAjaZud7ErIMUYjcwkDrKn1QnLAwCgYIKoZIzj0EAwIw" +
  "FDESMBAGA1UEAwwJVGVzdCBSb290MCAXDTI2MTAyNTE4MzMwMVoYDzIxMjYxMDAx" +
  "MTgzMzAxWjAcMRowGAYDVQQDDBFUZXN0IEludGVybWVkaWF0ZTBZMBMGByqGSM49" +
  "AgEGCCqGSM49AwEHA0IABDLtd7sHlupvYYMpSjytJUDDmHQWXYxdohAHxVkImouJ" +
  "2Wp4+XxHz2vxViX+fMHpRYAb+cLhDu7ieNqx3eBAfayjODA2MBIGA1UdEwEB/wQI" +
  "MAYBAf8CAQAwDgYDVR0PAQH/BAQDAgEGMBAGCiqGSIb3Y2QGAgEEAgUAMAoGCCqG" +
  "SM49BAMCA0kAMEYCIQCDiM4I6K3WXLfkrarxMnTmPAfxhI7og8S9mMMI0YLiSQIh" +
  "AOcuw6vGe8zhnO6HxrrKOJHUzGfsdO/V4BB536NnyvaC";
const LEAF =
  "MIIBZjCCAQygAwIBAgIUS7fnNNE8v3m9s7+VGh8j1h/d/fAwCgYIKoZIzj0EAwIw" +
  "HDEaMBgGA1UEAwwRVGVzdCBJbnRlcm1lZGlhdGUwIBcNMjYxMDI1MTgzMzAxWhgP" +
  "MjEyNjEwMDExODMzMDFaMBQxEjAQBgNVBAMMCVRlc3QgTGVhZjBZMBMGByqGSM49" +
  "AgEGCCqGSM49AwEHA0IABB49ev/2/+Aa4MKXym7EYzC+yKAEULhr23YY0Il2rW4+" +
  "1U/7l9qiG/6tqdzxbtkjWKYNdLmPUQeRVcbTFjJf6B6jMjAwMAwGA1UdEwEB/wQC" +
  "MAAwDgYDVR0PAQH/BAQDAgeAMBAGCiqGSIb3Y2QGCwEEAgUAMAoGCCqGSM49BAMC" +
  "A0gAMEUCICo+38wfCeCiFj0yyp0jaZGB4XxYDXBJzklBPwiIS8roAiEA5RHRqldI" +
  "ZRd9NHYOo74ACaSODkDy1v3nZNE2FvA3kto=";
const PLAIN_LEAF =
  "MIIBVDCB+6ADAgECAhRLt+c00Ty/eb2zv5UaHyPWH9398TAKBggqhkjOPQQDAjAc" +
  "MRowGAYDVQQDDBFUZXN0IEludGVybWVkaWF0ZTAgFw0yNjEwMjUxODMzMDFaGA8y" +
  "MTI2MTAwMTE4MzMwMVowFTETMBEGA1UEAwwKUGxhaW4gTGVhZjBZMBMGByqGSM49" +
  "AgEGCCqGSM49AwEHA0IABB49ev/2/+Aa4MKXym7EYzC+yKAEULhr23YY0Il2rW4+" +
  "1U/7l9qiG/6tqdzxbtkjWKYNdLmPUQeRVcbTFjJf6B6jIDAeMAwGA1UdEwEB/wQC" +
  "MAAwDgYDVR0PAQH/BAQDAgeAMAoGCCqGSM49BAMCA0gAMEUCICAIWzgMqB6jTKse" +
  "sG1J9crG71Xo3tG3au60XoYRHX5dAiEAyzyiPVu03tJZQM3SRvoiLwQn8k4S6gpn" +
  "gMWXooaBT8s=";
const LEAF_KEY = createPrivateKey(`-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgyyr7ESemBVI2xL6S
UY0pBcA0xrQQWpmWz8rxzLY1yyahRANCAAQePXr/9v/gGuDCl8puxGMwvsigBFC4
a9t2GNCJdq1uPtVP+5faohv+ranc8W7ZI1imDXS5j1EHkVXG0xYyX+ge
-----END PRIVATE KEY-----`);

const ROOT_FINGERPRINT =
  new X509Certificate(Buffer.from(ROOT, "base64")).fingerprint256;

const NOW = Date.parse("2027-01-01T00:00:00Z");
const BUNDLE = "pe.massivedynamics.triviaia";
const PRODUCT = "coins_pack_small";

/**
 * A transaction payload as StoreKit 2 signs it.
 * @param {object} overrides Fields to change.
 * @return {object} The payload.
 */
function payload(overrides: Record<string, unknown> = {}) {
  return {
    transactionId: "2000000123456789",
    originalTransactionId: "2000000123456789",
    bundleId: BUNDLE,
    productId: PRODUCT,
    purchaseDate: Date.parse("2026-12-31T23:59:00Z"),
    type: "Consumable",
    environment: "Production",
    ...overrides,
  };
}

/**
 * Signs a payload into a JWS with the test leaf.
 * @param {object} body The payload.
 * @param {object} options Header changes.
 * @return {string} The compact JWS.
 */
function jws(
  body: Record<string, unknown>,
  options: {x5c?: string[]; alg?: string} = {}
): string {
  const header = {
    alg: options.alg ?? "ES256",
    x5c: options.x5c ?? [LEAF, INTERMEDIATE, ROOT],
  };
  const encode = (value: unknown) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const signingInput = `${encode(header)}.${encode(body)}`;
  const signature = sign(
    "sha256", Buffer.from(signingInput),
    {key: LEAF_KEY, dsaEncoding: "ieee-p1363"}
  );
  return `${signingInput}.${signature.toString("base64url")}`;
}

/**
 * Verifies with the test root pinned and the test app's details.
 * @param {string} token The JWS.
 * @param {object} overrides Option changes.
 * @return {object} The verdict.
 */
function check(
  token: string,
  overrides: Partial<Parameters<typeof verifyAppStoreTransaction>[1]> = {}
) {
  return verifyAppStoreTransaction(token, {
    rootFingerprint256: ROOT_FINGERPRINT,
    bundleId: BUNDLE,
    productId: PRODUCT,
    nowMs: NOW,
    ...overrides,
  });
}

describe("verifyAppStoreTransaction", () => {
  test("accepts a transaction signed through the pinned root", () => {
    const verdict = check(jws(payload()));
    assert.deepEqual(verdict, {
      ok: true,
      transactionId: "2000000123456789",
      purchaseTimeMillis: Date.parse("2026-12-31T23:59:00Z"),
      test: false,
    });
  });

  // App Review buys in the sandbox, so it has to work; it's flagged as no
  // money moved, like a Play license tester.
  test("accepts a sandbox purchase, marked as a test", () => {
    const verdict = check(jws(payload({environment: "Sandbox"})));
    assert.equal(verdict.ok, true);
    assert.equal(verdict.ok && verdict.test, true);
  });

  test("refuses a payload changed after signing", () => {
    const [header, , signature] = jws(payload()).split(".");
    const forged = Buffer.from(JSON.stringify(payload({
      productId: "coins_pack_large",
    }))).toString("base64url");
    assert.deepEqual(
      check(
        `${header}.${forged}.${signature}`, {productId: "coins_pack_large"}
      ),
      {ok: false, reason: "invalid-signature"}
    );
  });

  // The whole point of pinning: a chain that is internally valid but ends
  // in someone else's root proves nothing.
  test("refuses a chain that doesn't end in the pinned root", () => {
    const other = "00:".repeat(31) + "00";
    assert.deepEqual(
      check(jws(payload()), {rootFingerprint256: other}),
      {ok: false, reason: "invalid-signature"}
    );
  });

  // Apple's root also signs certificates other parties hold the keys to
  // (Apple Pay merchants, for one): only the App Store's leaf may sign.
  test("refuses a leaf without the App Store marker", () => {
    assert.deepEqual(
      check(jws(payload(), {x5c: [PLAIN_LEAF, INTERMEDIATE, ROOT]})),
      {ok: false, reason: "invalid-signature"}
    );
  });

  test("refuses a chain in the wrong order or incomplete", () => {
    assert.deepEqual(
      check(jws(payload(), {x5c: [INTERMEDIATE, LEAF, ROOT]})),
      {ok: false, reason: "invalid-signature"}
    );
    assert.deepEqual(
      check(jws(payload(), {x5c: [LEAF, ROOT]})),
      {ok: false, reason: "invalid-signature"}
    );
  });

  test("refuses another signing algorithm", () => {
    assert.deepEqual(
      check(jws(payload(), {alg: "none"})),
      {ok: false, reason: "invalid-signature"}
    );
  });

  test("refuses once the certificates have expired", () => {
    assert.deepEqual(
      check(jws(payload()), {nowMs: Date.parse("2130-01-01T00:00:00Z")}),
      {ok: false, reason: "invalid-signature"}
    );
  });

  test("refuses another app's purchase", () => {
    assert.deepEqual(
      check(jws(payload({bundleId: "com.example.other"}))),
      {ok: false, reason: "wrong-app"}
    );
  });

  test("refuses a purchase of a different pack than claimed", () => {
    assert.deepEqual(
      check(jws(payload()), {productId: "coins_pack_large"}),
      {ok: false, reason: "wrong-product"}
    );
  });

  test("refuses a refunded purchase", () => {
    assert.deepEqual(
      check(jws(payload({revocationDate: NOW - 1000}))),
      {ok: false, reason: "revoked"}
    );
  });

  test("refuses anything that isn't a JWS", () => {
    assert.deepEqual(
      check("MIIT...a StoreKit 1 receipt"),
      {ok: false, reason: "invalid-signature"}
    );
    assert.deepEqual(check(""), {ok: false, reason: "invalid-signature"});
  });

  test("refuses a transaction without an id", () => {
    assert.deepEqual(
      check(jws(payload({transactionId: ""}))),
      {ok: false, reason: "invalid-signature"}
    );
  });
});
