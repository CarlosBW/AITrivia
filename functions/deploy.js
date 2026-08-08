// Envoltorio de `firebase deploy --only functions`.
//
// Por qué existe: `index.ts` tarda más de los 10s que el CLI espera por
// defecto para cargar el código y descubrir qué funciones exporta, así que
// el deploy muere con "Cannot determine backend specification. Timeout after
// 10000". Un deploy que aborta en esa fase puede dejar funciones creadas sin
// completar el paso de IAM, que es como `ensureAiTopicLevelsGenerated` y
// `submitWeeklyTopicRound` acabaron sin su binding de invoker y muertas en
// silencio. Fijar el timeout aquí evita que dependa de que alguien se
// acuerde de exportar la variable a mano.
//
// Uso:
//   npm run deploy                                  (todas las funciones)
//   npm run deploy -- --only functions:nombreDeUna  (una sola)

// eslint-disable-next-line @typescript-eslint/no-var-requires
const {spawnSync} = require("child_process");

const extra = process.argv.slice(2);
const args = extra.length > 0 ?
  ["deploy", ...extra] :
  ["deploy", "--only", "functions"];

// `shell: true` es obligatorio en Windows: `firebase` es un .cmd y Node lo
// rechaza con EINVAL si se lanza sin shell. Se pasa el comando como una sola
// cadena en vez de shell + array de argumentos, que es la combinación que
// Node marca como deprecada.
const command = ["firebase", ...args].join(" ");

const result = spawnSync(command, {
  stdio: "inherit",
  shell: true,
  env: {
    ...process.env,
    FUNCTIONS_DISCOVERY_TIMEOUT:
      process.env.FUNCTIONS_DISCOVERY_TIMEOUT || "120",
  },
});

process.exit(result.status === null ? 1 : result.status);
