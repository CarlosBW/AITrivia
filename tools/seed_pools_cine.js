const admin = require("firebase-admin");
const path = require("path");

const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

const CATEGORY_ID = "cine";

// Pool ejemplo (agrega más luego)
const POOL_D1 = [
  {
    q: '¿Quién dirigió "Titanic"?',
    options: ["James Cameron", "Christopher Nolan", "Steven Spielberg", "Ridley Scott"],
    answerIndex: 0,
  },
  {
    q: '¿En qué año se estrenó "The Matrix"?',
    options: ["1997", "1999", "2001", "2003"],
    answerIndex: 1,
  },
  {
    q: "¿Qué actor interpreta a Jack Sparrow?",
    options: ["Orlando Bloom", "Brad Pitt", "Johnny Depp", "Tom Cruise"],
    answerIndex: 2,
  },
  {
    q: '¿Qué película tiene a Woody y Buzz?',
    options: ["Toy Story", "Shrek", "Frozen", "Cars"],
    answerIndex: 0,
  },
  {
    q: '¿Quién dirigió "Pulp Fiction"?',
    options: ["Quentin Tarantino", "Martin Scorsese", "David Fincher", "Peter Jackson"],
    answerIndex: 0,
  },
  {
    q: '¿Qué saga incluye a "Darth Vader"?',
    options: ["Star Wars", "Star Trek", "Dune", "Alien"],
    answerIndex: 0,
  },
  {
    q: '¿Qué película ganó Mejor Película en la ceremonia 2020?',
    options: ["Joker", "1917", "Parasite", "Ford v Ferrari"],
    answerIndex: 2,
  },
  {
    q: '¿Cómo se llama la nave en "Alien" (1979)?',
    options: ["Nostromo", "Enterprise", "Serenity", "Galactica"],
    answerIndex: 0,
  },
  {
    q: '¿Quién interpreta a Neo en "The Matrix"?',
    options: ["Keanu Reeves", "Matt Damon", "Tom Hanks", "Christian Bale"],
    answerIndex: 0,
  },
  {
    q: '¿Qué película incluye la frase "I’ll be back"?',
    options: ["Terminator", "Rocky", "Rambo", "Die Hard"],
    answerIndex: 0,
  },
  // agrega más para más variedad
];

async function seedDifficulty(d, list) {
  // 1) meta doc (opcional, solo para marcar update)
  const metaRef = db
    .collection("fixed_pools")
    .doc(CATEGORY_ID)
    .collection(`difficulty_${d}`)
    .doc("meta");

  await metaRef.set(
    { updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  // 2) collection real de preguntas
  const questionsCol = db
    .collection("fixed_pools")
    .doc(CATEGORY_ID)
    .collection(`difficulty_${d}`)
    .doc("pool") // <-- doc intermedio
    .collection("questions");

  const batch = db.batch();

  list.forEach((q, idx) => {
    const ref = questionsCol.doc(`q${idx + 1}`);
    batch.set(ref, {
      ...q,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
  console.log(`✅ Seeded pool: fixed_pools/${CATEGORY_ID}/difficulty_${d}/pool/questions (${list.length})`);
}

async function run() {
  await seedDifficulty(1, POOL_D1);
  console.log("🎉 Pools listos.");
  process.exit(0);
}

run().catch((e) => {
  console.error("❌ Error:", e);
  process.exit(1);
});
