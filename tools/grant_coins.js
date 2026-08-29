/**
 * Acredita monedas a una cuenta, para poder probar una compra sin jugar
 * hasta juntarlas.
 *
 * `coins` esta en economyProtectedFields, asi que el cliente no puede
 * tocarlo ni con un cliente modificado — este script escribe con el Admin
 * SDK, que salta las reglas. Es una herramienta de prueba: no la conviertas
 * en un camino que la app pueda invocar.
 *
 * Por defecto corre en dry-run, como todo lo que escribe en produccion.
 *
 *   node grant_coins.js --username=Carlos            # ver cuanto tiene
 *   node grant_coins.js --username=Carlos --add=400 --commit
 *   node grant_coins.js --uid=abc123 --set=1000 --commit
 *   node grant_coins.js --list                       # ultimas cuentas
 */
const admin = require("firebase-admin");
const path = require("path");

const argOf = (name, fallback) => {
  const arg = process.argv.find((a) => a.startsWith(`--${name}=`));
  return arg ? arg.slice(name.length + 3) : fallback;
};

const COMMIT = process.argv.includes("--commit");
const LIST = process.argv.includes("--list");
const USERNAME = argOf("username", null);
const UID = argOf("uid", null);
const ADD = argOf("add", null);
const SET = argOf("set", null);

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.join(__dirname, "serviceAccountKey.json"))
  ),
});
const db = admin.firestore();

async function listRecent() {
  const snap = await db.collection("users")
    .orderBy("createdAt", "desc")
    .limit(15)
    .get();

  if (snap.empty) {
    console.log("No hay cuentas.");
    return;
  }

  console.log("uid".padEnd(30), "usuario".padEnd(20), "monedas", " temas");
  console.log("-".repeat(78));

  for (const doc of snap.docs) {
    const d = doc.data();
    console.log(
      doc.id.padEnd(30),
      String(d.username || "-").padEnd(20),
      String(d.coins ?? 0).padStart(7),
      "  " + (Array.isArray(d.ownedThemes) ? d.ownedThemes.join(",") : "-")
    );
  }
}

async function findUser() {
  if (UID) {
    const snap = await db.collection("users").doc(UID).get();
    if (!snap.exists) throw new Error(`No existe el usuario ${UID}`);
    return snap;
  }

  const snap = await db.collection("users")
    .where("usernameLower", "==", USERNAME.toLowerCase())
    .limit(2)
    .get();

  if (snap.empty) throw new Error(`No hay ninguna cuenta "${USERNAME}"`);
  if (snap.size > 1) throw new Error(`Hay varias cuentas "${USERNAME}"`);

  return snap.docs[0];
}

async function run() {
  if (LIST) {
    await listRecent();
    process.exit(0);
  }

  if (!USERNAME && !UID) {
    console.error(
      "Falta --username=<nombre> o --uid=<id>.\n" +
      "Usa --list para ver las cuentas."
    );
    process.exit(1);
  }

  const doc = await findUser();
  const data = doc.data();
  const coins = Number(data.coins ?? 0);

  console.log(`Cuenta:  ${data.username || "(sin nombre)"}  [${doc.id}]`);
  console.log(`Monedas: ${coins}`);
  console.log(
    "Temas:   " +
    (Array.isArray(data.ownedThemes) && data.ownedThemes.length ?
      data.ownedThemes.join(", ") :
      "solo el gratuito") +
    `   (equipado: ${data.equippedTheme || "default"})`
  );

  if (ADD === null && SET === null) {
    console.log("\nNada que cambiar. Pasa --add=N o --set=N.");
    process.exit(0);
  }

  const target = SET !== null ?
    parseInt(SET, 10) :
    coins + parseInt(ADD, 10);

  if (!Number.isInteger(target) || target < 0) {
    console.error("\nLa cantidad tiene que ser un entero no negativo.");
    process.exit(1);
  }

  console.log(`\n${coins}  ->  ${target} monedas`);

  if (!COMMIT) {
    console.log("\nDRY-RUN. No se escribio nada. Usa --commit para aplicar.");
    process.exit(0);
  }

  await doc.ref.set({
    coins: target,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  console.log("\nListo. Reabre la tienda en el emulador para verlo.");
  process.exit(0);
}

run().catch((e) => {
  console.error("ERROR:", e.message || e);
  process.exit(1);
});
