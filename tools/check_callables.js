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
// (401 `{"error":{"status":"UNAUTHENTICATED"}}`). Cualquier JSON significa
// que la función corrió — un HttpsError `permission-denied` también es 403,
// pero viene en JSON, así que el cuerpo manda sobre el código.
//
// Sin JSON, el código HTTP separa tres desenlaces que no comparten arreglo:
//   403  Cloud Run lo bloqueó       -> falta el binding de IAM
//   5xx  la llamada sí entró        -> el contenedor falló, mira los logs
//   429  nos limitaron a nosotros   -> no se pudo comprobar, no dice nada
//
// Mezclarlos costó caro: durante días esto reportó hasta 27 de 40 "no
// invocables" que respondían perfectamente al probarlas de una en una, y
// mandaba a tocar permisos por funciones que estaban levantadas.
// `check_callables.test.js` fija los cuatro casos.
//
// Uso: node tools/check_callables.js
// Sale con código 1 si alguna función no es invocable o devuelve 5xx.

const fs = require("fs");
const path = require("path");

const num = (value, fallback) =>
  value === undefined || value === "" ? fallback : Number(value);

const repoRoot = path.join(__dirname, "..");
const REGION = process.env.FUNCTIONS_REGION || "us-central1";

// Una a una y con pausa, no en paralelo.
//
// En paralelo esto se autolimitaba: los fallos se acumulaban hacia el final
// de la corrida —las últimas 15 de 40 daban 500— y esas mismas funciones
// respondían 401 JSON al probarlas sueltas. No era arranque en frío ni IAM,
// era el ritmo del propio chequeo. Un cron diario puede permitirse el
// minuto que cuesta hacerlo bien.
// Configurables por entorno para poder ejercitar la clasificación sin
// esperar los minutos que tarda una corrida real (ver
// `check_callables.test.js`), y para poder aflojar el ritmo desde CI sin
// tocar el código si Google aprieta más.
const PROBE_DELAY_MS = num(process.env.PROBE_DELAY_MS, 1500);

// Justo después de un rollout el binding puede tardar unos segundos en
// propagarse. Sin reintento, correr esto al final de un deploy daría rojos
// falsos — y un chequeo que miente es un chequeo que se acaba ignorando.
//
// Se reintenta *cualquier* fallo, no solo el bloqueo de Cloud Run: el 500
// por arranque en frío es intermitente, y antes se reportaba a la primera
// porque el reintento solo miraba `blocked`.
const RETRIES = num(process.env.PROBE_RETRIES, 3);
const RETRY_DELAY_MS = num(process.env.PROBE_RETRY_DELAY_MS, 5000);

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

  // 429: nos está limitando Google, no falla la función. No dice nada sobre
  // su salud, así que no puede contar ni como rota ni como sana.
  if (res.status === 429) {
    return {
      name,
      ok: false,
      throttled: true,
      detail: "429 — el chequeo fue limitado, no se pudo comprobar",
    };
  }

  // Un 5xx no es lo que este chequeo busca: la petición pasó el control de
  // acceso y llegó a Cloud Run, que es justo lo que se quiere confirmar. Lo
  // que falló fue el contenedor. Se distingue del 403 porque el arreglo es
  // otro — mirar los logs de la función, no tocar IAM.
  if (res.status >= 500) {
    return {
      name,
      ok: false,
      serverError: true,
      detail: `${res.status} de Cloud Run — la función no llegó a responder`,
    };
  }

  return {name, ok: false, detail: `${res.status} respuesta no-JSON`};
}

async function probe(project, name) {
  let result = await probeOnce(project, name);
  let attempts = 1;

  for (let attempt = 0; attempt < RETRIES && !result.ok; attempt++) {
    // Retroceso exponencial cuando nos limitan: insistir al mismo ritmo
    // contra un 429 solo alarga la limitación.
    const wait = result.throttled
      ? RETRY_DELAY_MS * Math.pow(3, attempt + 1)
      : RETRY_DELAY_MS;

    await sleep(wait);
    result = await probeOnce(project, name);
    attempts++;
  }

  // Se lleva la cuenta para poder decirlo: un verde que solo se consigue al
  // tercer intento no es lo mismo que uno limpio, y sin esto el reintento
  // taparía una degradación real en vez de sortear un fallo pasajero.
  return {...result, attempts};
}

async function main() {
  const project = projectId();
  const names = callableNames();

  console.log(`proyecto: ${project} (${REGION})`);
  console.log(`callables encontradas: ${names.length}\n`);

  const results = [];
  for (const [i, name] of names.entries()) {
    if (i > 0) await sleep(PROBE_DELAY_MS);
    results.push(await probe(project, name));
  }

  // Tres desenlaces distintos con tres arreglos distintos. Mezclarlos
  // mandaba a tocar permisos de IAM por una función que estaba levantada.
  const throttled = results.filter((r) => r.throttled);
  const failing = results.filter((r) => !r.ok && !r.throttled);
  const unreachable = failing.filter((r) => !r.serverError);
  const erroring = failing.filter((r) => r.serverError);

  for (const r of results.filter((r) => r.ok)) {
    const retried = r.attempts > 1 ? `, al intento ${r.attempts}` : "";
    console.log(`  ok    ${r.name} (${r.detail}${retried})`);
  }

  const retried = results.filter((r) => r.ok && r.attempts > 1);

  // Se dice siempre, pase o falle: un chequeo que no pudo comprobar parte de
  // lo suyo tiene que decirlo, o su verde promete más de lo que sabe.
  if (throttled.length) {
    console.log("");
    for (const r of throttled) {
      console.log(`  ?     ${r.name} — ${r.detail}`);
    }
    console.log(
      `\n${throttled.length} de ${results.length} quedaron sin comprobar: ` +
      "Google limitó el propio chequeo, lo que no dice nada sobre esas " +
      "funciones. Si se repite a diario, sube PROBE_DELAY_MS."
    );
  }

  if (failing.length === 0) {
    console.log(
      `\n${results.length - throttled.length} de ${results.length} ` +
      "callables comprobadas son invocables."
    );
    if (retried.length) {
      console.log(
        `${retried.length} necesitaron reintento: ` +
        `${retried.map((r) => r.name).join(", ")}.\n` +
        "Invocables, pero Cloud Run falló al primer intento. Si la cifra " +
        "crece con los días, mira los logs antes de que se vuelva rojo."
      );
    }
    return 0;
  }

  console.log("");

  if (erroring.length) {
    for (const r of erroring) {
      console.log(`  ERROR ${r.name} — ${r.detail}`);
    }
    console.log(
      `\n${erroring.length} de ${results.length} respondieron 5xx tras ` +
      `${RETRIES + 1} intentos. Son invocables — el acceso no es el ` +
      "problema —, pero su contenedor falló. Mira sus logs:\n" +
      "  firebase functions:log --only <nombre>"
    );
  }

  if (unreachable.length) {
    if (erroring.length) console.log("");
    for (const r of unreachable) {
      console.log(`  ROTA  ${r.name} — ${r.detail}`);
    }
    console.log(
      `\n${unreachable.length} de ${results.length} no son invocables. ` +
      "Para cada una:\n" +
      "  gcloud run services add-iam-policy-binding <nombre-en-minusculas> \\\n" +
      `    --region=${REGION} --member=allUsers --role=roles/run.invoker \\\n` +
      `    --project=${project}\n` +
      "o en Cloud Run > el servicio > Permissions > Add principal."
    );
  }
  return 1;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error("ERROR:", e.message);
    process.exit(1);
  }
);
