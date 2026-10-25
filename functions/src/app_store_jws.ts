/**
 * Verifies a StoreKit 2 transaction locally, from its signed JWS.
 *
 * Kept out of index.ts so the checks that decide whether an iOS payment
 * turns into coins can be unit-tested without firebase-admin, the network
 * or an Apple account. Nothing here calls Apple: a StoreKit 2 transaction
 * carries its own certificate chain, and checking that chain against
 * Apple's pinned root is what Apple's own server library does.
 */

import {X509Certificate, verify as verifySignature} from "node:crypto";

/**
 * SHA-256 fingerprint of Apple Root CA - G3, which every App Store
 * transaction chains to (as listed on Apple's root certificate pages).
 */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:" +
  "7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

// Extensions Apple marks its certificates with, DER-encoded. Apple's root
// signs more than App Store receipts — Apple Pay merchant certificates,
// whose keys other companies hold, chain to it too — so a valid chain alone
// isn't enough: the intermediate must be Apple's WWDR one and the leaf the
// App Store's receipt-signing one.
/** 1.2.840.113635.100.6.2.1, Apple WWDR intermediate. */
const INTERMEDIATE_MARKER = Buffer.from("060a2a864886f76364060201", "hex");
/** 1.2.840.113635.100.6.11.1, App Store receipt signing. */
const LEAF_MARKER = Buffer.from("060a2a864886f76364060b01", "hex");

export type AppStoreVerdict =
  | {
      ok: true;
      /** Apple's id for this purchase: what the ledger is keyed on. */
      transactionId: string;
      purchaseTimeMillis: number | null;
      /** A sandbox purchase (TestFlight, App Review): no money moved. */
      test: boolean;
    }
  | {
      ok: false;
      reason: "invalid-signature" | "wrong-app" | "wrong-product" | "revoked";
    };

/**
 * Checks a StoreKit 2 signed transaction and reads what crediting needs.
 *
 * Anything that doesn't prove itself — a bad signature, a chain not ending
 * in [rootFingerprint256], an expired or unmarked certificate, a payload
 * that doesn't parse — is "invalid-signature": a payment check that
 * defaults to yes is not a payment check.
 * @param {string} jws `serverVerificationData` from the app.
 * @param {object} options The pinned root, the app, the pack and now.
 * @return {AppStoreVerdict} Whether to credit it, and the details kept.
 */
export function verifyAppStoreTransaction(
  jws: string,
  options: {
    rootFingerprint256: string;
    bundleId: string;
    productId: string;
    nowMs: number;
  }
): AppStoreVerdict {
  const invalid: AppStoreVerdict = {ok: false, reason: "invalid-signature"};

  const parts = jws.split(".");
  if (parts.length !== 3) return invalid;
  const [headerPart, payloadPart, signaturePart] = parts;

  let header: Record<string, unknown>;
  let payload: Record<string, unknown>;
  let leaf: X509Certificate;
  let intermediate: X509Certificate;
  let root: X509Certificate;
  try {
    header = JSON.parse(Buffer.from(headerPart, "base64url").toString());
    payload = JSON.parse(Buffer.from(payloadPart, "base64url").toString());
    if (header.alg !== "ES256") return invalid;
    const x5c = header.x5c;
    if (!Array.isArray(x5c) || x5c.length !== 3) return invalid;
    [leaf, intermediate, root] = x5c.map((der) =>
      new X509Certificate(Buffer.from(String(der), "base64"))
    );
  } catch (_) {
    return invalid;
  }

  if (root.fingerprint256 !== options.rootFingerprint256) return invalid;
  if (!intermediate.ca || leaf.ca) return invalid;
  if (!intermediate.raw.includes(INTERMEDIATE_MARKER)) return invalid;
  if (!leaf.raw.includes(LEAF_MARKER)) return invalid;
  for (const cert of [leaf, intermediate, root]) {
    const from = Date.parse(cert.validFrom);
    const to = Date.parse(cert.validTo);
    if (!(options.nowMs >= from && options.nowMs <= to)) return invalid;
  }
  if (!leaf.checkIssued(intermediate) || !leaf.verify(intermediate.publicKey)) {
    return invalid;
  }
  if (
    !intermediate.checkIssued(root) || !intermediate.verify(root.publicKey)
  ) {
    return invalid;
  }

  let signed = false;
  try {
    signed = verifySignature(
      "sha256",
      Buffer.from(`${headerPart}.${payloadPart}`),
      {key: leaf.publicKey, dsaEncoding: "ieee-p1363"},
      Buffer.from(signaturePart, "base64url")
    );
  } catch (_) {
    signed = false;
  }
  if (!signed) return invalid;

  const transactionId = typeof payload.transactionId === "string" ?
    payload.transactionId : "";
  if (!transactionId) return invalid;

  if (payload.bundleId !== options.bundleId) {
    return {ok: false, reason: "wrong-app"};
  }
  if (payload.productId !== options.productId) {
    return {ok: false, reason: "wrong-product"};
  }
  if (payload.revocationDate !== undefined && payload.revocationDate !== null) {
    return {ok: false, reason: "revoked"};
  }

  const purchaseDate = Number(payload.purchaseDate);
  return {
    ok: true,
    transactionId,
    purchaseTimeMillis: Number.isFinite(purchaseDate) &&
      payload.purchaseDate !== undefined ? purchaseDate : null,
    test: payload.environment === "Sandbox",
  };
}
