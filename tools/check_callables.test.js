/**
 * Comprueba que `check_callables.js` clasifique bien cada respuesta.
 *
 * Existe porque el chequeo se equivocó justo en esto: durante días reportó
 * "no invocable" ante un 500 y mandó a tocar permisos de IAM por funciones
 * que estaban levantadas, y ante un 429 —que era el propio chequeo siendo
 * limitado— hacía lo mismo. Distinguir los cuatro desenlaces es toda su
 * utilidad, así que es lo que hay que fijar.
 *
 * No toca la red: sustituye `fetch` y pone los tiempos a cero, de modo que
 * corre en un segundo en vez de los ~8 minutos de una pasada real.
 *
 *   node --test check_callables.test.js
 */
const test = require("node:test");
const assert = require("node:assert");
const {execFileSync} = require("node:child_process");
const path = require("node:path");

const script = path.join(__dirname, "check_callables.js");

/** Corre el chequeo con cada llamada respondiendo lo mismo. */
function runWith({status, body, contentType}) {
  const stub = [
    "globalThis.fetch = async () => ({",
    `  status: ${status},`,
    `  headers: {get: () => ${JSON.stringify(contentType)}},`,
    `  text: async () => ${JSON.stringify(body)},`,
    "});",
    `require(${JSON.stringify(script)});`,
  ].join("\n");

  const env = {
    ...process.env,
    PROBE_DELAY_MS: "0",
    PROBE_RETRY_DELAY_MS: "0",
    PROBE_RETRIES: "1",
  };

  try {
    return {
      code: 0,
      out: execFileSync(process.execPath, ["-e", stub], {
        encoding: "utf8",
        env,
        cwd: __dirname,
      }),
    };
  } catch (e) {
    return {code: e.status, out: (e.stdout || "") + (e.stderr || "")};
  }
}

test("una callable sana pasa", () => {
  const {code, out} = runWith({
    status: 401,
    body: '{"error":{"status":"UNAUTHENTICATED"}}',
    contentType: "application/json",
  });

  assert.strictEqual(code, 0);
  assert.match(out, /son invocables/);
});

test("un 403 de Cloud Run manda a arreglar IAM", () => {
  const {code, out} = runWith({
    status: 403,
    body: "<html>403</html>",
    contentType: "text/html",
  });

  assert.strictEqual(code, 1);
  assert.match(out, /add-iam-policy-binding/);
});

// El fallo que motivó todo esto: un 500 significa que la llamada atravesó el
// control de acceso, así que mandar a tocar IAM es el consejo equivocado.
test("un 500 manda a los logs, no a IAM", () => {
  const {code, out} = runWith({
    status: 500,
    body: "<html>500</html>",
    contentType: "text/html",
  });

  assert.strictEqual(code, 1);
  assert.match(out, /functions:log/);
  assert.doesNotMatch(out, /add-iam-policy-binding/);
});

// Un 429 es el chequeo siendo limitado. No dice nada de la función, así que
// no puede pintarla de roja ni tumbar el cron.
test("un 429 queda como no comprobado y no falla", () => {
  const {code, out} = runWith({
    status: 429,
    body: "<html>429</html>",
    contentType: "text/html",
  });

  assert.strictEqual(code, 0);
  assert.match(out, /quedaron sin comprobar/);
  assert.doesNotMatch(out, /add-iam-policy-binding/);
});

// Un HttpsError `permission-denied` tambien es 403, pero viene en JSON: la
// funcion corrio. Confundirlo con el bloqueo de Cloud Run seria un rojo
// falso permanente.
test("un 403 en JSON es una funcion sana, no un bloqueo", () => {
  const {code, out} = runWith({
    status: 403,
    body: '{"error":{"status":"PERMISSION_DENIED"}}',
    contentType: "application/json",
  });

  assert.strictEqual(code, 0);
  assert.match(out, /son invocables/);
});
