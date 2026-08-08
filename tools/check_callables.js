// Verifica que toda función `onCall` sea invocable desde el cliente.
//
// Por qué existe: una callable desplegada sin el binding
// `allUsers -> roles/run.invoker` es rechazada por Cloud Run *antes* de
// ejecutar su código. El cliente no distingue eso de cualquier otro fallo
// de red, y varios servicios tragan la excepción a propósito
// (`ensureAiTopicBuffer` es "best-effort"), así que la función queda muerta
// en silencio. `ensureAiTopicLevelsGenerated` y `submitWeeklyTopicRound`
// estuvieron así tres días sin que nada lo notara.
//
// Cómo distingue: una llamada sin autenticar a una callable sana llega al
// código de la función, que responde su propio HttpsError en JSON
// (401 `{"error":{"status":"UNAUTHENTICATED"}}`). Si en cambio Cloud Run la
// bloquea, la respuesta es una página HTML de Google. El discriminante es el
// cuerpo, no el código HTTP: un HttpsError `permission-denied` también es
// 403, pero viene en JSON.
//
// Uso: node tools/check_callables.js
// Sale con código 1 si alguna función no es invocable.

const fs = require("fs");
const path = require("path");

const repoRoot = path.join(__dirname, "..");
const REGION = process.env.FUNCTIONS_REGION || "us-central1";
const CONCURRENCY = 6;

// Justo después de un rollout el binding puede tardar unos segundos en
// propagarse. Sin reintento, correr esto al final de un deploy daría rojos
// falsos — y un chequeo que miente en su primer uso es un chequeo que se
// acaba ignorando. Solo se reintenta el caso "Cloud Run bloqueó"; un fallo
// de red o una respuesta rara se reportan de una.
const RETRIES = 2;
const RETRY_DELAY_MS = 5000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function projectId() {
  const rc = JSON.parse(
    fs.readFileSync(path.join(repoRoot, ".firebaserc"), "utf8")
  );
  const id = rc.projects && rc.projects.default;
  if (!id) throw new Error("No se pudo leer projects.default de .firebaserc");
  return id;
}

// Se leen del fuente en vez de mantener una lista aparte: así una callable
// nueva queda cubierta sin que nadie se acuerde de actualizar este script.
function callableNames() {
  const src = fs.readFileSync(
    path.join(repoRoot, "functions/src/index.ts"),
    "utf8"
  );
  const names = [...src.matchAll(/^export const (\w+) = onCall/gm)]
    .map((m) => m[1]);
  if (names.length === 0) {
    throw new Error("No se encontró ninguna callable en functions/src/index.ts");
  }
  return names;
}

async function probeOnce(project, name) {
  const url =
    `https://${REGION}-${project}.cloudfunctions.net/${name}`;

  let res;
  let body;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({data: {}}),
      signal: AbortSignal.timeout(30000),
    });
    body = await res.text();
  } catch (e) {
    return {name, ok: false, detail: `sin respuesta: ${e.message}`};
  }

  let parsed = null;
  try {
    parsed = JSON.parse(body);
  } catch (_) {
    // Cuerpo no-JSON: casi siempre la página de error de Cloud Run.
  }

  // El código de la función corrió si contestó su propio error estructurado
  // (o cualquier JSON válido: hay callables que no exigen auth de entrada).
  if (parsed !== null) {
    const status = parsed.error && parsed.error.status;
    return {name, ok: true, detail: `${res.status} ${status || "JSON"}`};
  }

  if (res.status === 403) {
    return {
      name,
      ok: false,
      blocked: true,
      detail: "403 de Cloud Run — falta allUsers -> roles/run.invoker",
    };
  }

  return {name, ok: false, detail: `${res.status} respuesta no-JSON`};
}

async function probe(project, name) {
  let result = await probeOnce(project, name);

  for (let attempt = 0; attempt < RETRIES && result.blocked; attempt++) {
    await sleep(RETRY_DELAY_MS);
    result = await probeOnce(project, name);
  }

  return result;
}

async function main() {
  const project = projectId();
  const names = callableNames();

  console.log(`proyecto: ${project} (${REGION})`);
  console.log(`callables encontradas: ${names.length}\n`);

  const results = [];
  for (let i = 0; i < names.length; i += CONCURRENCY) {
    const chunk = names.slice(i, i + CONCURRENCY);
    results.push(...await Promise.all(chunk.map((n) => probe(project, n))));
  }

  const broken = results.filter((r) => !r.ok);

  for (const r of results.filter((r) => r.ok)) {
    console.log(`  ok    ${r.name} (${r.detail})`);
  }

  if (broken.length === 0) {
    console.log(`\nTodas las ${results.length} callables son invocables.`);
    return 0;
  }

  console.log("");
  for (const r of broken) {
    console.log(`  ROTA  ${r.name} — ${r.detail}`);
  }
  console.log(
    `\n${broken.length} de ${results.length} no son invocables. Para cada una:\n` +
    "  gcloud run services add-iam-policy-binding <nombre-en-minusculas> \\\n" +
    `    --region=${REGION} --member=allUsers --role=roles/run.invoker \\\n` +
    `    --project=${project}\n` +
    "o en Cloud Run > el servicio > Permissions > Add principal."
  );
  return 1;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error("ERROR:", e.message);
    process.exit(1);
  }
);
