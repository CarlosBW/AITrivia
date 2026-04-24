const admin = require("firebase-admin");
const path = require("path");

const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");

// Cambia aquí si quieres otra categoría
const CATEGORY_ID = "cine";      // fixed_categories/cine
const CATEGORY_NAME = "Cine";
const LEVEL_COUNT = 10;
const QUESTIONS_PER_LEVEL = 10;

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

function makeQuestionPool() {
  // Pool simple (puedes reemplazar/expandir luego)
  return [
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
      q: '¿Qué película ganó el Óscar a Mejor Película en 2020 (ceremonia 2020)?',
      options: ["Joker", "1917", "Parasite", "Once Upon a Time in Hollywood"],
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
      q: '¿En qué saga aparece el personaje "Darth Vader"?',
      options: ["Star Wars", "Star Trek", "Dune", "Alien"],
      answerIndex: 0,
    },
    {
      q: '¿Qué película tiene la frase "I’ll be back"?',
      options: ["Terminator", "Rocky", "Rambo", "Die Hard"],
      answerIndex: 0,
    },
    {
      q: '¿Quién dirigió "Pulp Fiction"?',
      options: ["Quentin Tarantino", "Martin Scorsese", "David Fincher", "Peter Jackson"],
      answerIndex: 0,
    },
    {
      q: '¿Qué película animada tiene a Woody y Buzz?',
      options: ["Toy Story", "Shrek", "Frozen", "Cars"],
      answerIndex: 0,
    },
    // extras (para rotación)
    {
      q: '¿En qué ciudad transcurre mayormente "The Dark Knight"?',
      options: ["Gotham", "Metropolis", "New York", "Chicago"],
      answerIndex: 0,
    },
    {
      q: '¿Quién interpretó a Wolverine en la mayoría de películas de X-Men?',
      options: ["Hugh Jackman", "Ryan Reynolds", "Chris Evans", "Ben Affleck"],
      answerIndex: 0,
    },
    {
      q: '¿Qué película trata sobre sueños dentro de sueños?',
      options: ["Inception", "Interstellar", "Memento", "Tenet"],
      answerIndex: 0,
    },
    {
      q: '¿Qué personaje dice "May the Force be with you"?',
      options: ["Varios personajes en Star Wars", "Harry Potter", "Frodo", "Neo"],
      answerIndex: 0,
    },
  ];
}

function pickQuestions(pool, count, levelNumber) {
  // Selección determinística (simple) para que no se repitan igual por nivel
  const out = [];
  let idx = (levelNumber * 3) % pool.length;
  for (let i = 0; i < count; i++) {
    out.push(pool[idx]);
    idx = (idx + 1) % pool.length;
  }
  return out;
}

async function run() {
  const pool = makeQuestionPool();

  // 1) Asegurar doc de categoría
  const categoryRef = db.collection("fixed_categories").doc(CATEGORY_ID);
  await categoryRef.set(
    {
      name: CATEGORY_NAME,
      order: 1,
      levelCount: LEVEL_COUNT,
      isActive: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // 2) Crear niveles 1..10
  for (let level = 1; level <= LEVEL_COUNT; level++) {
    const levelRef = categoryRef.collection("levels").doc(String(level));
    const questions = pickQuestions(pool, QUESTIONS_PER_LEVEL, level);

    await levelRef.set(
      {
        levelNumber: level,
        questionCount: QUESTIONS_PER_LEVEL,
        questions: questions,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log(`✅ Creado: ${CATEGORY_ID}/levels/${level} (${QUESTIONS_PER_LEVEL} preguntas)`);
  }

  console.log("🎉 Seed completado.");
  process.exit(0);
}

run().catch((e) => {
  console.error("❌ Error:", e);
  process.exit(1);
});
