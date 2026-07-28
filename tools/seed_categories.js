const admin = require("firebase-admin");
const path = require("path");

const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

// Each category: 40 unique questions split 14/13/13 across difficulty 1/2/3.
// Used both as the source pool for Solo's 10 levels x 10 questions
// (fixed_categories/{id}/levels/{n}) and as the three difficulty-specific
// pools PvP/Daily/Realtime Invites draw from (fixed_pools/{id}/difficulty_{d}).
const CATEGORIES = {
  cine: {
    name: "Cine",
    order: 1,
    difficulty1: [
      { q: '¿Quién dirigió "Titanic"?', options: ["James Cameron", "Christopher Nolan", "Steven Spielberg", "Ridley Scott"], answerIndex: 0 },
      { q: '¿En qué año se estrenó "The Matrix"?', options: ["1997", "1999", "2001", "2003"], answerIndex: 1 },
      { q: "¿Qué actor interpreta a Jack Sparrow?", options: ["Orlando Bloom", "Brad Pitt", "Johnny Depp", "Tom Cruise"], answerIndex: 2 },
      { q: '¿Qué película tiene a Woody y Buzz?', options: ["Toy Story", "Shrek", "Frozen", "Cars"], answerIndex: 0 },
      { q: '¿Quién dirigió "Pulp Fiction"?', options: ["Quentin Tarantino", "Martin Scorsese", "David Fincher", "Peter Jackson"], answerIndex: 0 },
      { q: '¿Qué saga incluye a "Darth Vader"?', options: ["Star Wars", "Star Trek", "Dune", "Alien"], answerIndex: 0 },
      { q: '¿Cómo se llama la nave en "Alien" (1979)?', options: ["Nostromo", "Enterprise", "Serenity", "Galactica"], answerIndex: 0 },
      { q: '¿Quién interpreta a Neo en "The Matrix"?', options: ["Keanu Reeves", "Matt Damon", "Tom Hanks", "Christian Bale"], answerIndex: 0 },
      { q: '¿Qué película incluye la frase "I’ll be back"?', options: ["Terminator", "Rocky", "Rambo", "Die Hard"], answerIndex: 0 },
      { q: '¿Qué personaje dice "May the Force be with you"?', options: ["Varios personajes en Star Wars", "Harry Potter", "Frodo", "Neo"], answerIndex: 0 },
      { q: "¿Quién interpretó a Wolverine en la mayoría de películas de X-Men?", options: ["Hugh Jackman", "Ryan Reynolds", "Chris Evans", "Ben Affleck"], answerIndex: 0 },
      { q: '¿En qué ciudad transcurre mayormente "The Dark Knight"?', options: ["Gotham", "Metropolis", "New York", "Chicago"], answerIndex: 0 },
      { q: '¿Qué animal es Simba en "El Rey León"?', options: ["León", "Tigre", "Leopardo", "Guepardo"], answerIndex: 0 },
      { q: "¿Qué actor interpreta a Iron Man en el Universo Marvel?", options: ["Robert Downey Jr.", "Chris Hemsworth", "Chris Evans", "Mark Ruffalo"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿Qué película ganó el Óscar a Mejor Película en la ceremonia de 2020?", options: ["Joker", "1917", "Parasite", "Ford v Ferrari"], answerIndex: 2 },
      { q: "¿Qué película trata sobre sueños dentro de sueños?", options: ["Inception", "Interstellar", "Memento", "Tenet"], answerIndex: 0 },
      { q: '¿Quién dirigió "Interstellar"?', options: ["Christopher Nolan", "Denis Villeneuve", "James Cameron", "Ridley Scott"], answerIndex: 0 },
      { q: '¿Qué actor interpretó a Michael Corleone en "El Padrino"?', options: ["Al Pacino", "Robert De Niro", "Marlon Brando", "James Caan"], answerIndex: 0 },
      { q: '¿Qué estudio de animación creó "Toy Story"?', options: ["Pixar", "DreamWorks", "Illumination", "Studio Ghibli"], answerIndex: 0 },
      { q: '¿Quién dirigió "Jurassic Park" (1993)?', options: ["Steven Spielberg", "George Lucas", "James Cameron", "Robert Zemeckis"], answerIndex: 0 },
      { q: '¿En qué película aparece el personaje "Hannibal Lecter"?', options: ["El Silencio de los Inocentes", "Seven", "Zodiac", "Psycho"], answerIndex: 0 },
      { q: "¿Qué actriz interpretó a Hermione Granger en Harry Potter?", options: ["Emma Watson", "Emma Stone", "Natalie Portman", "Kristen Stewart"], answerIndex: 0 },
      { q: '¿Qué director es conocido por "Kill Bill" y "Django Unchained"?', options: ["Quentin Tarantino", "Martin Scorsese", "Guy Ritchie", "Robert Rodriguez"], answerIndex: 0 },
      { q: '¿Cuál fue la primera película de la saga "Star Wars" en estrenarse (1977)?', options: ["Una Nueva Esperanza", "El Imperio Contraataca", "El Retorno del Jedi", "La Amenaza Fantasma"], answerIndex: 0 },
      { q: "¿Qué película de Pixar trata sobre las emociones dentro de la mente de una niña?", options: ["Intensamente", "Coco", "Up", "Wall-E"], answerIndex: 0 },
      { q: '¿Quién interpretó al Joker en "The Dark Knight" (2008)?', options: ["Heath Ledger", "Joaquin Phoenix", "Jack Nicholson", "Jared Leto"], answerIndex: 0 },
      { q: "¿Qué película ganó el Óscar a Mejor Película Animada en 2018?", options: ["Coco", "Los Increíbles 2", "Ferdinand", "Hotel Transylvania 3"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: '¿Quién compuso la banda sonora original de "Star Wars"?', options: ["John Williams", "Hans Zimmer", "Danny Elfman", "Ennio Morricone"], answerIndex: 0 },
      { q: "¿Qué película de Alfred Hitchcock presenta la famosa escena de la ducha?", options: ["Psycho", "Vértigo", "Los Pájaros", "La Ventana Indiscreta"], answerIndex: 0 },
      { q: '¿Qué actriz protagonizó "Alien" (1979) interpretando a Ripley?', options: ["Sigourney Weaver", "Meryl Streep", "Jamie Lee Curtis", "Linda Hamilton"], answerIndex: 0 },
      { q: '¿En qué año se estrenó la primera película de "Blade Runner"?', options: ["1982", "1985", "1979", "1990"], answerIndex: 0 },
      { q: '¿Qué director dirigió "2001: Una Odisea del Espacio"?', options: ["Stanley Kubrick", "Steven Spielberg", "Ridley Scott", "George Lucas"], answerIndex: 0 },
      { q: "¿Cuál es el nombre del boxeador interpretado por Sylvester Stallone?", options: ["Rocky Balboa", "Apollo Creed", "Clubber Lang", "Tommy Gunn"], answerIndex: 0 },
      { q: "¿Qué película francesa muda, dirigida por Michel Hazanavicius, ganó el Óscar a Mejor Película en 2012?", options: ["The Artist", "Amélie", "La La Land", "Delicatessen"], answerIndex: 0 },
      { q: '¿Quién dirigió "Apocalypse Now"?', options: ["Francis Ford Coppola", "Martin Scorsese", "Oliver Stone", "Michael Cimino"], answerIndex: 0 },
      { q: '¿Qué actor interpretó a Tony Montana en "Scarface" (1983)?', options: ["Al Pacino", "Robert De Niro", "Al Lettieri", "Steven Bauer"], answerIndex: 0 },
      { q: "¿En qué película aparece por primera vez el personaje de James Bond?", options: ["Dr. No", "Goldfinger", "Skyfall", "Casino Royale"], answerIndex: 0 },
      { q: '¿Qué director es conocido por el uso de planos secuencia largos, como en "Birdman"?', options: ["Alejandro González Iñárritu", "Alfonso Cuarón", "Guillermo del Toro", "Pedro Almodóvar"], answerIndex: 0 },
      { q: "¿Qué película de Guillermo del Toro ganó el Óscar a Mejor Película en 2018?", options: ["La Forma del Agua", "El Laberinto del Fauno", "Hellboy", "Pacific Rim"], answerIndex: 0 },
      { q: "¿Cuál es el nombre del planeta natal de Superman?", options: ["Krypton", "Tatooine", "Pandora", "Arrakis"], answerIndex: 0 },
    ],
  },

  historia: {
    name: "Historia Global",
    order: 2,
    difficulty1: [
      { q: "¿En qué año comenzó la Segunda Guerra Mundial?", options: ["1939", "1914", "1945", "1929"], answerIndex: 0 },
      { q: "¿Quién fue el primer presidente de los Estados Unidos?", options: ["George Washington", "Thomas Jefferson", "Abraham Lincoln", "John Adams"], answerIndex: 0 },
      { q: "¿En qué continente se encuentra Egipto?", options: ["África", "Asia", "Europa", "América"], answerIndex: 0 },
      { q: "¿Qué muro cayó en 1989?", options: ["El Muro de Berlín", "La Gran Muralla China", "El Muro de Adriano", "El Muro de las Lamentaciones"], answerIndex: 0 },
      { q: "¿Quién descubrió América en 1492?", options: ["Cristóbal Colón", "Marco Polo", "Vasco da Gama", "Fernando de Magallanes"], answerIndex: 0 },
      { q: "¿En qué país se originó la Revolución Francesa?", options: ["Francia", "Inglaterra", "España", "Rusia"], answerIndex: 0 },
      { q: "¿Qué imperio construyó el Coliseo?", options: ["El Imperio Romano", "El Imperio Griego", "El Imperio Persa", "El Imperio Otomano"], answerIndex: 0 },
      { q: "¿Qué faraón mandó construir la Gran Pirámide de Guiza?", options: ["Keops", "Tutankamón", "Ramsés II", "Akenatón"], answerIndex: 0 },
      { q: "¿En qué año terminó la Segunda Guerra Mundial?", options: ["1945", "1939", "1918", "1950"], answerIndex: 0 },
      { q: "¿Qué civilización construyó Machu Picchu?", options: ["Los Incas", "Los Aztecas", "Los Mayas", "Los Olmecas"], answerIndex: 0 },
      { q: "¿Quién fue Napoleón Bonaparte?", options: ["Un emperador francés", "Un rey inglés", "Un zar ruso", "Un papa"], answerIndex: 0 },
      { q: "¿En qué siglo ocurrió la Revolución Industrial?", options: ["Siglo XVIII-XIX", "Siglo XV", "Siglo XX", "Siglo XVI"], answerIndex: 0 },
      { q: '¿Qué país fue conocido como el "Imperio del Sol Naciente"?', options: ["Japón", "China", "Corea", "Tailandia"], answerIndex: 0 },
      { q: "¿Quién lideró el movimiento de independencia pacífica de India?", options: ["Mahatma Gandhi", "Nehru", "Winston Churchill", "Nelson Mandela"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿En qué año cayó Constantinopla ante los otomanos?", options: ["1453", "1492", "1517", "1400"], answerIndex: 0 },
      { q: "¿Quién fue el líder de la Revolución Rusa de 1917?", options: ["Vladimir Lenin", "Joseph Stalin", "Karl Marx", "Leon Trotsky"], answerIndex: 0 },
      { q: "¿Qué tratado puso fin a la Primera Guerra Mundial?", options: ["Tratado de Versalles", "Tratado de Tordesillas", "Tratado de Utrecht", "Tratado de Roma"], answerIndex: 0 },
      { q: "¿Qué reina gobernó Inglaterra durante la derrota de la Armada Española (1588)?", options: ["Isabel I", "Victoria", "Isabel II", "María I"], answerIndex: 0 },
      { q: "¿Qué antiguo imperio tuvo su capital en Tenochtitlán?", options: ["El Imperio Azteca", "El Imperio Inca", "El Imperio Maya", "El Imperio Tolteca"], answerIndex: 0 },
      { q: "¿En qué año se firmó la Declaración de Independencia de Estados Unidos?", options: ["1776", "1789", "1800", "1763"], answerIndex: 0 },
      { q: "¿Quién fue asesinado en Sarajevo desencadenando la Primera Guerra Mundial?", options: ["El archiduque Francisco Fernando", "El zar Nicolás II", "El káiser Guillermo II", "El rey Jorge V"], answerIndex: 0 },
      { q: "¿Qué dinastía gobernó China durante la construcción de gran parte de la Gran Muralla actual?", options: ["Dinastía Ming", "Dinastía Han", "Dinastía Tang", "Dinastía Qing"], answerIndex: 0 },
      { q: "¿Qué país unificó Otto von Bismarck en el siglo XIX?", options: ["Alemania", "Italia", "Austria", "Prusia"], answerIndex: 0 },
      { q: "¿En qué batalla fue derrotado Napoleón definitivamente en 1815?", options: ["Waterloo", "Austerlitz", "Trafalgar", "Leipzig"], answerIndex: 0 },
      { q: "¿Qué explorador portugués llegó a la India por mar en 1498?", options: ["Vasco da Gama", "Fernando de Magallanes", "Cristóbal Colón", "Enrique el Navegante"], answerIndex: 0 },
      { q: "¿Qué revolución derrocó al zar Nicolás II en 1917?", options: ["La Revolución Rusa", "La Revolución Francesa", "La Revolución Industrial", "La Revolución Mexicana"], answerIndex: 0 },
      { q: "¿Qué imperio fue gobernado por Gengis Kan?", options: ["El Imperio Mongol", "El Imperio Otomano", "El Imperio Persa", "El Imperio Bizantino"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: "¿En qué año comenzó la Guerra de los Cien Años?", options: ["1337", "1400", "1315", "1450"], answerIndex: 0 },
      { q: "¿Qué tratado dividió las tierras del Nuevo Mundo entre España y Portugal en 1494?", options: ["Tratado de Tordesillas", "Tratado de Versalles", "Tratado de Utrecht", "Tratado de Westfalia"], answerIndex: 0 },
      { q: "¿Quién fue el último emperador de la dinastía Qing en China?", options: ["Puyi", "Guangxu", "Kangxi", "Qianlong"], answerIndex: 0 },
      { q: "¿Qué conferencia de 1945 acordó dividir Europa en zonas de influencia entre los Aliados?", options: ["Conferencia de Yalta", "Conferencia de Múnich", "Conferencia de Berlín", "Conferencia de Locarno"], answerIndex: 0 },
      { q: "¿En qué año se proclamó la Primera República Francesa?", options: ["1792", "1789", "1804", "1815"], answerIndex: 0 },
      { q: "¿Qué emperador romano se convirtió al cristianismo y promulgó el Edicto de Milán en 313?", options: ["Constantino", "Nerón", "Trajano", "Adriano"], answerIndex: 0 },
      { q: "¿Qué guerra civil enfrentó a Estados Unidos entre 1861 y 1865?", options: ["La Guerra Civil Estadounidense", "La Guerra de Independencia", "La Guerra Hispanoamericana", "La Guerra de 1812"], answerIndex: 0 },
      { q: "¿Qué imperio precolombino fue conquistado por Francisco Pizarro?", options: ["El Imperio Inca", "El Imperio Azteca", "El Imperio Maya", "El Imperio Chibcha"], answerIndex: 0 },
      { q: "¿En qué año se unificó Italia bajo el Reino de Italia?", options: ["1861", "1848", "1900", "1870"], answerIndex: 0 },
      { q: "¿Qué antiguo imperio fue gobernado por Cleopatra?", options: ["El Antiguo Egipto", "Persia", "Babilonia", "Cartago"], answerIndex: 0 },
      { q: "¿Qué revuelta campesina alemana ocurrió en 1524-1525?", options: ["La Guerra de los Campesinos Alemanes", "La Revuelta de los Comuneros", "La Guerra de los Treinta Años", "La Fronda"], answerIndex: 0 },
      { q: "¿Qué acuerdo de 1648 puso fin a la Guerra de los Treinta Años?", options: ["Paz de Westfalia", "Paz de Utrecht", "Paz de Augsburgo", "Tratado de Tordesillas"], answerIndex: 0 },
      { q: "¿Qué emperador bizantino murió defendiendo Constantinopla en 1453?", options: ["Constantino XI", "Justiniano I", "Basilio II", "Miguel VIII"], answerIndex: 0 },
    ],
  },

  ciencia: {
    name: "Ciencia",
    order: 3,
    difficulty1: [
      { q: "¿Cuál es el planeta más cercano al Sol?", options: ["Mercurio", "Venus", "Tierra", "Marte"], answerIndex: 0 },
      { q: "¿Cuál es el símbolo químico del oxígeno?", options: ["O", "Ox", "O2", "Og"], answerIndex: 0 },
      { q: "¿Cuántos huesos tiene el cuerpo humano adulto aproximadamente?", options: ["206", "150", "300", "450"], answerIndex: 0 },
      { q: "¿Qué gas necesitan las plantas para hacer fotosíntesis?", options: ["Dióxido de carbono", "Oxígeno", "Nitrógeno", "Hidrógeno"], answerIndex: 0 },
      { q: "¿Cuál es el órgano que bombea la sangre en el cuerpo?", options: ["El corazón", "El hígado", "El pulmón", "El riñón"], answerIndex: 0 },
      { q: "¿Qué planeta es conocido como el planeta rojo?", options: ["Marte", "Venus", "Júpiter", "Saturno"], answerIndex: 0 },
      { q: "¿Cuál es la velocidad de la luz aproximadamente?", options: ["300.000 km/s", "150.000 km/s", "1.000.000 km/s", "50.000 km/s"], answerIndex: 0 },
      { q: "¿Qué parte de la célula contiene el material genético?", options: ["El núcleo", "La mitocondria", "El citoplasma", "La membrana"], answerIndex: 0 },
      { q: "¿Qué metal es líquido a temperatura ambiente?", options: ["Mercurio", "Hierro", "Plomo", "Aluminio"], answerIndex: 0 },
      { q: "¿Qué científico propuso la teoría de la relatividad?", options: ["Albert Einstein", "Isaac Newton", "Galileo Galilei", "Nikola Tesla"], answerIndex: 0 },
      { q: "¿Cuántos planetas tiene el sistema solar actualmente?", options: ["8", "9", "7", "10"], answerIndex: 0 },
      { q: "¿Qué vitamina se obtiene principalmente del sol?", options: ["Vitamina D", "Vitamina C", "Vitamina A", "Vitamina B12"], answerIndex: 0 },
      { q: "¿Qué instrumento se usa para medir la temperatura?", options: ["Termómetro", "Barómetro", "Higrómetro", "Anemómetro"], answerIndex: 0 },
      { q: "¿Cuál es el hueso más largo del cuerpo humano?", options: ["El fémur", "La tibia", "El húmero", "La columna"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿Quién formuló las leyes del movimiento y la gravitación universal?", options: ["Isaac Newton", "Albert Einstein", "Galileo Galilei", "Johannes Kepler"], answerIndex: 0 },
      { q: "¿Cuál es la unidad básica de la herencia genética?", options: ["El gen", "El cromosoma", "La proteína", "El ribosoma"], answerIndex: 0 },
      { q: "¿Qué elemento tiene el número atómico 1?", options: ["Hidrógeno", "Helio", "Litio", "Oxígeno"], answerIndex: 0 },
      { q: "¿Qué científica descubrió la radiactividad junto con su esposo?", options: ["Marie Curie", "Rosalind Franklin", "Ada Lovelace", "Dorothy Hodgkin"], answerIndex: 0 },
      { q: "¿Cuál es el proceso por el cual las plantas producen su propio alimento?", options: ["Fotosíntesis", "Respiración", "Fermentación", "Digestión"], answerIndex: 0 },
      { q: "¿Qué tipo de célula no tiene núcleo definido?", options: ["Célula procariota", "Célula eucariota", "Célula animal", "Célula vegetal"], answerIndex: 0 },
      { q: "¿Qué teoría explica el origen y evolución del universo a partir de una gran explosión?", options: ["Big Bang", "Teoría de cuerdas", "Teoría del estado estacionario", "Teoría cuántica"], answerIndex: 0 },
      { q: "¿Qué gas es el principal responsable del efecto invernadero?", options: ["Dióxido de carbono", "Oxígeno", "Nitrógeno", "Argón"], answerIndex: 0 },
      { q: "¿Cuántos cromosomas tiene una célula humana normal?", options: ["46", "44", "48", "23"], answerIndex: 0 },
      { q: "¿Qué científico desarrolló la tabla periódica de los elementos?", options: ["Dmitri Mendeléyev", "Marie Curie", "Niels Bohr", "Ernest Rutherford"], answerIndex: 0 },
      { q: "¿Qué parte del cerebro controla el equilibrio y la coordinación?", options: ["El cerebelo", "El cerebro", "El bulbo raquídeo", "El tálamo"], answerIndex: 0 },
      { q: "¿Qué proceso libera energía al romper enlaces de moléculas de glucosa en las células?", options: ["Respiración celular", "Fotosíntesis", "Fermentación", "Ósmosis"], answerIndex: 0 },
      { q: "¿Qué científico formuló la teoría de la evolución por selección natural?", options: ["Charles Darwin", "Gregor Mendel", "Louis Pasteur", "Alfred Wallace"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: "¿Qué partícula subatómica tiene carga negativa?", options: ["Electrón", "Protón", "Neutrón", "Positrón"], answerIndex: 0 },
      { q: "¿Qué científico formuló el principio de incertidumbre en mecánica cuántica?", options: ["Werner Heisenberg", "Niels Bohr", "Max Planck", "Erwin Schrödinger"], answerIndex: 0 },
      { q: "¿Cuál es la unidad de medida de la fuerza en el Sistema Internacional?", options: ["Newton", "Joule", "Pascal", "Watt"], answerIndex: 0 },
      { q: "¿Qué enzima corta el ADN en fragmentos específicos, usada en ingeniería genética?", options: ["Enzima de restricción", "ADN polimerasa", "Ligasa", "Helicasa"], answerIndex: 0 },
      { q: "¿Qué científico descubrió la penicilina?", options: ["Alexander Fleming", "Louis Pasteur", "Robert Koch", "Edward Jenner"], answerIndex: 0 },
      { q: "¿Qué proceso describe la fusión de núcleos atómicos que ocurre en el Sol?", options: ["Fusión nuclear", "Fisión nuclear", "Radiación", "Ionización"], answerIndex: 0 },
      { q: "¿Qué modelo atómico propuso que los electrones orbitan el núcleo en niveles de energía definidos?", options: ["Modelo de Bohr", "Modelo de Thomson", "Modelo de Rutherford", "Modelo de Dalton"], answerIndex: 0 },
      { q: "¿Qué nombre recibe la fuerza que mantiene unidos a los nucleones dentro del núcleo atómico?", options: ["Fuerza nuclear fuerte", "Fuerza electromagnética", "Fuerza gravitacional", "Fuerza nuclear débil"], answerIndex: 0 },
      { q: "¿Qué científica fue pionera en el estudio de la estructura del ADN mediante cristalografía de rayos X?", options: ["Rosalind Franklin", "Marie Curie", "Barbara McClintock", "Lise Meitner"], answerIndex: 0 },
      { q: "¿Qué proceso bioquímico produce la mayor parte del ATP en las mitocondrias?", options: ["Fosforilación oxidativa", "Glucólisis", "Fotosíntesis", "Fermentación"], answerIndex: 0 },
      { q: "¿Qué unidad mide la cantidad de sustancia en química?", options: ["Mol", "Litro", "Gramo", "Joule"], answerIndex: 0 },
      { q: "¿Qué principio establece que la energía no se crea ni se destruye, solo se transforma?", options: ["Primera ley de la termodinámica", "Segunda ley de la termodinámica", "Ley de conservación de la masa", "Ley de Hooke"], answerIndex: 0 },
      { q: "¿Qué astrónomo propuso el modelo heliocéntrico del sistema solar?", options: ["Nicolás Copérnico", "Galileo Galilei", "Johannes Kepler", "Ptolomeo"], answerIndex: 0 },
    ],
  },

  musica: {
    name: "Música",
    order: 4,
    difficulty1: [
      { q: "¿Cuántas cuerdas tiene una guitarra estándar?", options: ["6", "4", "5", "7"], answerIndex: 0 },
      { q: "¿Qué banda británica formaron John Lennon y Paul McCartney?", options: ["The Beatles", "The Rolling Stones", "Queen", "Pink Floyd"], answerIndex: 0 },
      { q: '¿Quién es conocido como el "Rey del Pop"?', options: ["Michael Jackson", "Elvis Presley", "Prince", "Freddie Mercury"], answerIndex: 0 },
      { q: "¿Qué instrumento tiene teclas blancas y negras?", options: ["Piano", "Guitarra", "Violín", "Batería"], answerIndex: 0 },
      { q: '¿Qué cantante colombiana canta "Waka Waka"?', options: ["Shakira", "Karol G", "J Balvin", "Maluma"], answerIndex: 0 },
      { q: "¿Qué género musical se originó en Jamaica?", options: ["Reggae", "Salsa", "Flamenco", "Blues"], answerIndex: 0 },
      { q: "¿Qué instrumento de cuerda se toca con arco?", options: ["El violín", "La guitarra", "El arpa", "El banjo"], answerIndex: 0 },
      { q: "¿Quién fue el vocalista de la banda Queen?", options: ["Freddie Mercury", "Brian May", "Roger Taylor", "John Deacon"], answerIndex: 0 },
      { q: "¿Qué género musical tiene su origen en Argentina y se baila en pareja?", options: ["El tango", "La salsa", "El flamenco", "La cumbia"], answerIndex: 0 },
      { q: "¿Cuántas teclas tiene un piano estándar?", options: ["88", "76", "100", "64"], answerIndex: 0 },
      { q: '¿Qué cantante puertorriqueño es conocido como "El Rey del Reguetón"?', options: ["Daddy Yankee", "Bad Bunny", "Ozuna", "Wisin"], answerIndex: 0 },
      { q: "¿Qué instrumento de percusión se toca con las manos y es típico del jazz y la música afrocaribeña?", options: ["Los bongós", "El xilófono", "El triángulo", "La pandereta"], answerIndex: 0 },
      { q: '¿Qué banda cantó "Bohemian Rhapsody"?', options: ["Queen", "The Beatles", "Led Zeppelin", "The Who"], answerIndex: 0 },
      { q: '¿Qué artista canta "Despacito"?', options: ["Luis Fonsi", "Enrique Iglesias", "Ricky Martin", "Marc Anthony"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿Qué compositor alemán quedó sordo y aun así compuso su Novena Sinfonía?", options: ["Ludwig van Beethoven", "Wolfgang Amadeus Mozart", "Johann Sebastian Bach", "Franz Schubert"], answerIndex: 0 },
      { q: "¿Qué banda de rock formaron Mick Jagger y Keith Richards?", options: ["The Rolling Stones", "The Beatles", "Led Zeppelin", "The Who"], answerIndex: 0 },
      { q: '¿Qué cantante es conocida como la "Reina del Pop"?', options: ["Madonna", "Britney Spears", "Whitney Houston", "Cher"], answerIndex: 0 },
      { q: "¿Qué género musical surgió en Nueva Orleans a principios del siglo XX?", options: ["Jazz", "Blues", "Rock", "Country"], answerIndex: 0 },
      { q: '¿Qué compositor austríaco escribió "Las Bodas de Fígaro"?', options: ["Wolfgang Amadeus Mozart", "Ludwig van Beethoven", "Joseph Haydn", "Franz Liszt"], answerIndex: 0 },
      { q: '¿Qué banda británica lanzó el álbum "The Dark Side of the Moon"?', options: ["Pink Floyd", "Led Zeppelin", "Deep Purple", "Genesis"], answerIndex: 0 },
      { q: "¿Qué género musical brasileño nació a finales de los años 50 combinando samba y jazz?", options: ["Bossa nova", "Forró", "Axé", "Samba-reggae"], answerIndex: 0 },
      { q: "¿Qué instrumento es característico del flamenco español?", options: ["La guitarra española", "El acordeón", "El violín", "El arpa"], answerIndex: 0 },
      { q: '¿Qué cantante estadounidense es conocida como "The Queen of Soul"?', options: ["Aretha Franklin", "Diana Ross", "Whitney Houston", "Tina Turner"], answerIndex: 0 },
      { q: '¿Qué compositor ruso escribió "El Cascanueces"?', options: ["Piotr Ilich Tchaikovsky", "Sergei Rachmaninoff", "Igor Stravinsky", "Dmitri Shostakovich"], answerIndex: 0 },
      { q: "¿Qué banda de rock de Seattle lideró el movimiento grunge en los 90 con Kurt Cobain?", options: ["Nirvana", "Pearl Jam", "Soundgarden", "Alice in Chains"], answerIndex: 0 },
      { q: "¿Qué género musical colombiano tiene el acordeón como instrumento principal?", options: ["El vallenato", "La cumbia", "La salsa", "El bolero"], answerIndex: 0 },
      { q: '¿Qué cantante cubana es conocida como "La Guarachera de Cuba" y reina de la salsa?', options: ["Celia Cruz", "Gloria Estefan", "La India", "Celia Gómez"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: '¿Qué compositor barroco alemán compuso "El Clave Bien Temperado"?', options: ["Johann Sebastian Bach", "Georg Friedrich Händel", "Antonio Vivaldi", "Claudio Monteverdi"], answerIndex: 0 },
      { q: '¿Qué compositor italiano compuso "Las Cuatro Estaciones"?', options: ["Antonio Vivaldi", "Johann Sebastian Bach", "Georg Friedrich Händel", "Gioachino Rossini"], answerIndex: 0 },
      { q: "¿Qué movimiento musical de vanguardia del siglo XX utilizó el dodecafonismo, creado por Arnold Schoenberg?", options: ["Serialismo", "Impresionismo", "Minimalismo", "Romanticismo"], answerIndex: 0 },
      { q: '¿Qué compositor francés es asociado con el impresionismo musical y compuso "Claro de Luna"?', options: ["Claude Debussy", "Maurice Ravel", "Erik Satie", "Camille Saint-Saëns"], answerIndex: 0 },
      { q: "¿Qué cantautor estadounidense ganó el Premio Nobel de Literatura en 2016?", options: ["Bob Dylan", "Leonard Cohen", "Paul Simon", "Neil Young"], answerIndex: 0 },
      { q: "¿Qué ópera de Giuseppe Verdi está ambientada en el Antiguo Egipto?", options: ["Aida", "La Traviata", "Rigoletto", "Otello"], answerIndex: 0 },
      { q: '¿Qué compositor alemán del Romanticismo es conocido por "La Cabalgata de las Valquirias"?', options: ["Richard Wagner", "Johannes Brahms", "Franz Schubert", "Robert Schumann"], answerIndex: 0 },
      { q: "¿Qué término musical indica que una pieza debe tocarse rápido y con alegría?", options: ["Allegro", "Adagio", "Largo", "Andante"], answerIndex: 0 },
      { q: '¿Qué compositor compuso la ópera "La Flauta Mágica"?', options: ["Wolfgang Amadeus Mozart", "Ludwig van Beethoven", "Franz Joseph Haydn", "Christoph Willibald Gluck"], answerIndex: 0 },
      { q: "¿Qué género musical afroamericano, surgido en los años 70 en el Bronx, incluye el rap como elemento central?", options: ["Hip hop", "Funk", "Disco", "R&B"], answerIndex: 0 },
      { q: '¿Qué compositor húngaro es conocido por sus "Rapsodias Húngaras"?', options: ["Franz Liszt", "Béla Bartók", "Zoltán Kodály", "Johannes Brahms"], answerIndex: 0 },
      { q: "¿Qué cantaor español es considerado una leyenda del flamenco y trabajó junto a Paco de Lucía?", options: ["Camarón de la Isla", "Enrique Morente", "José Mercé", "Diego El Cigala"], answerIndex: 0 },
      { q: '¿Qué compositor ruso escribió la "Sinfonía Patética" (Sinfonía n.º 6)?', options: ["Piotr Ilich Tchaikovsky", "Dmitri Shostakovich", "Sergei Prokofiev", "Modest Mussorgsky"], answerIndex: 0 },
    ],
  },

  arte: {
    name: "Arte",
    order: 5,
    difficulty1: [
      { q: "¿Quién pintó la Mona Lisa?", options: ["Leonardo da Vinci", "Miguel Ángel", "Rafael", "Sandro Botticelli"], answerIndex: 0 },
      { q: '¿Quién pintó "La noche estrellada"?', options: ["Vincent van Gogh", "Pablo Picasso", "Claude Monet", "Salvador Dalí"], answerIndex: 0 },
      { q: "¿Qué pintor español es famoso por el cubismo?", options: ["Pablo Picasso", "Salvador Dalí", "Joan Miró", "Diego Velázquez"], answerIndex: 0 },
      { q: "¿Quién pintó el techo de la Capilla Sixtina?", options: ["Miguel Ángel", "Leonardo da Vinci", "Rafael", "Donatello"], answerIndex: 0 },
      { q: '¿Qué pintora mexicana es conocida por sus autorretratos, como "Las Dos Fridas"?', options: ["Frida Kahlo", "Diego Rivera", "José Clemente Orozco", "Rufino Tamayo"], answerIndex: 0 },
      { q: "¿Qué museo alberga la Mona Lisa?", options: ["El Louvre", "El Prado", "El MoMA", "El Hermitage"], answerIndex: 0 },
      { q: "¿Qué pintor holandés se cortó una oreja?", options: ["Vincent van Gogh", "Rembrandt", "Johannes Vermeer", "Piet Mondrian"], answerIndex: 0 },
      { q: "¿Qué famosa escultura de mármol de Miguel Ángel representa a un joven bíblico?", options: ["David", "Pietà", "Moisés", "El Pensador"], answerIndex: 0 },
      { q: '¿Qué pintor pintó "Guernica"?', options: ["Pablo Picasso", "Salvador Dalí", "Joan Miró", "Francisco Goya"], answerIndex: 0 },
      { q: '¿Qué pintor es conocido por los relojes derretidos en "La persistencia de la memoria"?', options: ["Salvador Dalí", "Pablo Picasso", "René Magritte", "Max Ernst"], answerIndex: 0 },
      { q: '¿Qué escultor francés creó "El Pensador"?', options: ["Auguste Rodin", "Claude Monet", "Edgar Degas", "Camille Claudel"], answerIndex: 0 },
      { q: '¿Qué pintor pintó "El grito"?', options: ["Edvard Munch", "Vincent van Gogh", "Gustav Klimt", "Egon Schiele"], answerIndex: 0 },
      { q: "¿Qué arquitecto catalán diseñó la Sagrada Familia en Barcelona?", options: ["Antoni Gaudí", "Santiago Calatrava", "Rafael Moneo", "Le Corbusier"], answerIndex: 0 },
      { q: '¿Qué pintor italiano del Renacimiento pintó "El nacimiento de Venus"?', options: ["Sandro Botticelli", "Leonardo da Vinci", "Rafael", "Tiziano"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿Qué movimiento artístico se caracteriza por captar la luz y el momento fugaz, iniciado por Claude Monet?", options: ["Impresionismo", "Expresionismo", "Cubismo", "Surrealismo"], answerIndex: 0 },
      { q: '¿Qué pintor holandés del Barroco pintó "La ronda de noche"?', options: ["Rembrandt", "Johannes Vermeer", "Frans Hals", "Jan van Eyck"], answerIndex: 0 },
      { q: "¿Qué pintora mexicana estuvo casada con el muralista Diego Rivera?", options: ["Frida Kahlo", "María Izquierdo", "Remedios Varo", "Leonora Carrington"], answerIndex: 0 },
      { q: "¿Qué movimiento artístico del siglo XX, liderado por Dalí y Magritte, exploraba el mundo de los sueños?", options: ["Surrealismo", "Cubismo", "Fauvismo", "Dadaísmo"], answerIndex: 0 },
      { q: '¿Qué pintor español pintó "Las Meninas"?', options: ["Diego Velázquez", "Francisco Goya", "El Greco", "Bartolomé Esteban Murillo"], answerIndex: 0 },
      { q: '¿Qué pintor austríaco es conocido por "El Beso" y el estilo Art Nouveau?', options: ["Gustav Klimt", "Egon Schiele", "Oskar Kokoschka", "Koloman Moser"], answerIndex: 0 },
      { q: "¿Qué escultor renacentista, también pintor, arquitecto y poeta, es autor de la Pietà?", options: ["Miguel Ángel", "Donatello", "Brunelleschi", "Ghiberti"], answerIndex: 0 },
      { q: "¿Qué corriente artística fragmenta los objetos en formas geométricas, desarrollada por Picasso y Braque?", options: ["Cubismo", "Futurismo", "Constructivismo", "Suprematismo"], answerIndex: 0 },
      { q: "¿Qué pintor francés es conocido por sus obras de bailarinas de ballet?", options: ["Edgar Degas", "Claude Monet", "Auguste Renoir", "Paul Cézanne"], answerIndex: 0 },
      { q: '¿Qué pintor italiano pintó "La última cena"?', options: ["Leonardo da Vinci", "Miguel Ángel", "Rafael", "Tiziano"], answerIndex: 0 },
      { q: '¿Qué pintor neerlandés del siglo XVII es famoso por "La joven de la perla"?', options: ["Johannes Vermeer", "Rembrandt", "Frans Hals", "Pieter de Hooch"], answerIndex: 0 },
      { q: "¿Qué artista pop estadounidense es conocido por sus serigrafías de latas de sopa Campbell?", options: ["Andy Warhol", "Roy Lichtenstein", "Jasper Johns", "Keith Haring"], answerIndex: 0 },
      { q: '¿Qué pintor español, conocido como "el pintor de la corte", creó "Los fusilamientos del 3 de mayo"?', options: ["Francisco Goya", "Diego Velázquez", "El Greco", "Joaquín Sorolla"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: '¿Qué pintor flamenco del siglo XV pintó "El jardín de las delicias"?', options: ["El Bosco", "Jan van Eyck", "Pieter Bruegel el Viejo", "Rogier van der Weyden"], answerIndex: 0 },
      { q: "¿Qué movimiento artístico ruso de principios del siglo XX, liderado por Kazimir Malévich, se centró en formas geométricas puras?", options: ["Suprematismo", "Constructivismo", "Rayonismo", "Futurismo"], answerIndex: 0 },
      { q: '¿Qué escultor italiano del Renacimiento esculpió un "David" de bronce antes que Miguel Ángel?', options: ["Donatello", "Verrocchio", "Ghiberti", "Brunelleschi"], answerIndex: 0 },
      { q: '¿Qué pintor alemán es considerado el maestro del grabado renacentista, autor de "Melencolia I"?', options: ["Alberto Durero", "Hans Holbein", "Lucas Cranach", "Matthias Grünewald"], answerIndex: 0 },
      { q: "¿Qué corriente pictórica del siglo XVII se caracteriza por el uso dramático del claroscuro, con Caravaggio como referente?", options: ["Tenebrismo", "Rococó", "Manierismo", "Neoclasicismo"], answerIndex: 0 },
      { q: "¿Qué pintor español manierista, de origen griego, trabajó principalmente en Toledo?", options: ["El Greco", "Diego Velázquez", "Francisco de Zurbarán", "José de Ribera"], answerIndex: 0 },
      { q: "¿Qué movimiento artístico francés del siglo XVIII se caracteriza por la ornamentación y los colores pastel, previo al Neoclasicismo?", options: ["Rococó", "Barroco", "Romanticismo", "Academicismo"], answerIndex: 0 },
      { q: '¿Qué arquitecto suizo-francés, pionero del movimiento moderno, promovió los "cinco puntos de la arquitectura"?', options: ["Le Corbusier", "Mies van der Rohe", "Walter Gropius", "Frank Lloyd Wright"], answerIndex: 0 },
      { q: "¿Qué pintor neerlandés del siglo XX, pionero de la abstracción geométrica, pintó composiciones con líneas y colores primarios?", options: ["Piet Mondrian", "Theo van Doesburg", "Kazimir Malévich", "Wassily Kandinsky"], answerIndex: 0 },
      { q: "¿Qué pintor ruso es considerado uno de los pioneros del arte abstracto junto con Malévich y Mondrian?", options: ["Wassily Kandinsky", "Marc Chagall", "El Lissitzky", "Natalia Goncharova"], answerIndex: 0 },
      { q: "¿Qué movimiento de vanguardia, surgido en Zúrich durante la Primera Guerra Mundial, rechazaba la lógica y la razón en el arte?", options: ["Dadaísmo", "Surrealismo", "Futurismo", "Expresionismo"], answerIndex: 0 },
      { q: '¿Qué escultor rumano-francés es conocido por sus formas abstractas y minimalistas como "El pájaro en el espacio"?', options: ["Constantin Brâncuși", "Alberto Giacometti", "Henry Moore", "Jean Arp"], answerIndex: 0 },
      { q: "¿Qué pintor italiano del Renacimiento temprano es autor de los frescos de la Capilla Brancacci en Florencia?", options: ["Masaccio", "Fra Angelico", "Piero della Francesca", "Domenico Ghirlandaio"], answerIndex: 0 },
    ],
  },
  geografia: {
    name: "Geografía",
    order: 6,
    difficulty1: [
      { q: "¿Cuál es el país más grande del mundo por superficie?", options: ["Rusia", "Canadá", "China", "Estados Unidos"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Francia?", options: ["París", "Londres", "Madrid", "Roma"], answerIndex: 0 },
      { q: "¿Cuál es el río más largo del mundo?", options: ["El Nilo", "El Amazonas", "El Misisipi", "El Yangtsé"], answerIndex: 0 },
      { q: "¿Cuál es el continente más grande?", options: ["Asia", "África", "América", "Europa"], answerIndex: 0 },
      { q: "¿Qué océano es el más grande del mundo?", options: ["El Pacífico", "El Atlántico", "El Índico", "El Ártico"], answerIndex: 0 },
      { q: "¿Cuál es la montaña más alta del mundo?", options: ["El Monte Everest", "El Aconcagua", "El Kilimanjaro", "El K2"], answerIndex: 0 },
      { q: "¿Qué país tiene forma de bota?", options: ["Italia", "España", "Grecia", "Portugal"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Japón?", options: ["Tokio", "Kioto", "Osaka", "Seúl"], answerIndex: 0 },
      { q: "¿En qué continente está Egipto?", options: ["África", "Asia", "Europa", "Oceanía"], answerIndex: 0 },
      { q: "¿Cuál es el desierto cálido más grande del mundo?", options: ["El Sahara", "El Gobi", "El Atacama", "El Kalahari"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Brasil?", options: ["Brasilia", "Río de Janeiro", "São Paulo", "Salvador"], answerIndex: 0 },
      { q: "¿Qué país conformado por miles de islas tiene como capital Yakarta?", options: ["Indonesia", "Filipinas", "Malasia", "Tailandia"], answerIndex: 0 },
      { q: "¿Cuál es el país más poblado del mundo actualmente?", options: ["India", "China", "Estados Unidos", "Indonesia"], answerIndex: 0 },
      { q: "¿Cuál es la capital de España?", options: ["Madrid", "Barcelona", "Sevilla", "Valencia"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿Cuál es el país más pequeño del mundo?", options: ["Ciudad del Vaticano", "Mónaco", "San Marino", "Liechtenstein"], answerIndex: 0 },
      { q: "¿Qué estrecho separa España de África?", options: ["Estrecho de Gibraltar", "Estrecho de Bering", "Estrecho de Magallanes", "Canal de la Mancha"], answerIndex: 0 },
      { q: "¿Cuál es la cordillera montañosa más larga del mundo?", options: ["Los Andes", "El Himalaya", "Las Montañas Rocosas", "Los Alpes"], answerIndex: 0 },
      { q: "¿Qué país tiene más husos horarios?", options: ["Francia", "Rusia", "Estados Unidos", "China"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Australia?", options: ["Canberra", "Sídney", "Melbourne", "Perth"], answerIndex: 0 },
      { q: "¿Qué lago es el más grande del mundo por superficie?", options: ["El Mar Caspio", "El Lago Superior", "El Lago Victoria", "El Lago Baikal"], answerIndex: 0 },
      { q: "¿Qué país limita con más países del mundo, empatado con Rusia?", options: ["China", "Brasil", "India", "Alemania"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Canadá?", options: ["Ottawa", "Toronto", "Vancouver", "Montreal"], answerIndex: 0 },
      { q: "¿Qué río atraviesa Egipto?", options: ["El Nilo", "El Éufrates", "El Tigris", "El Jordán"], answerIndex: 0 },
      { q: "¿Cuál es el punto más bajo de la Tierra en tierra firme?", options: ["El Mar Muerto", "El Valle de la Muerte", "El Mar Caspio", "La Depresión de Turfan"], answerIndex: 0 },
      { q: '¿Qué país es conocido como "la tierra del fuego y el hielo" por sus volcanes y glaciares?', options: ["Islandia", "Groenlandia", "Noruega", "Nueva Zelanda"], answerIndex: 0 },
      { q: "¿Cuál es la capital legislativa de Sudáfrica?", options: ["Ciudad del Cabo", "Pretoria", "Johannesburgo", "Bloemfontein"], answerIndex: 0 },
      { q: "¿Qué país europeo tiene la mayor cantidad de fiordos?", options: ["Noruega", "Suecia", "Finlandia", "Islandia"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: "¿Cuál es la capital de Kazajistán?", options: ["Astaná", "Almaty", "Bishkek", "Tashkent"], answerIndex: 0 },
      { q: "¿Qué país tiene tres capitales oficiales (administrativa, legislativa y judicial)?", options: ["Sudáfrica", "Bolivia", "Países Bajos", "Sri Lanka"], answerIndex: 0 },
      { q: "¿Cuál es el punto más profundo de los océanos?", options: ["La Fosa de las Marianas", "La Fosa de Puerto Rico", "La Fosa de Tonga", "La Fosa de Kermadec"], answerIndex: 0 },
      { q: "¿Qué país tiene la línea de costa más larga del mundo?", options: ["Canadá", "Rusia", "Indonesia", "Noruega"], answerIndex: 0 },
      { q: "¿Cuál es la capital de Mongolia?", options: ["Ulán Bator", "Astaná", "Bishkek", "Dusambé"], answerIndex: 0 },
      { q: "¿Qué estrecho conecta el Mar Mediterráneo con el Mar Negro junto con el Bósforo?", options: ["Los Dardanelos", "El Estrecho de Ormuz", "El Estrecho de Malaca", "El Canal de Suez"], answerIndex: 0 },
      { q: "¿Qué país sin salida al mar está rodeado completamente por Sudáfrica?", options: ["Lesoto", "Suazilandia", "Botsuana", "Malaui"], answerIndex: 0 },
      { q: "¿Cuál es la cascada más alta del mundo?", options: ["El Salto Ángel", "Las Cataratas del Iguazú", "Las Cataratas Victoria", "Las Cataratas del Niágara"], answerIndex: 0 },
      { q: "¿Qué archipiélago pertenece a Ecuador y es famoso por su biodiversidad estudiada por Darwin?", options: ["Islas Galápagos", "Islas Canarias", "Islas Malvinas", "Islas Salomón"], answerIndex: 0 },
      { q: "¿Cuál es el país más extenso de África?", options: ["Argelia", "República Democrática del Congo", "Sudán", "Libia"], answerIndex: 0 },
      { q: "¿Qué meridiano se usa como referencia para el Tiempo Universal (0°)?", options: ["El Meridiano de Greenwich", "El Meridiano de París", "El Meridiano de Ecuador", "El Antimeridiano"], answerIndex: 0 },
      { q: "¿Qué país centroamericano no tiene ejército desde 1948?", options: ["Costa Rica", "Panamá", "Nicaragua", "Belice"], answerIndex: 0 },
      { q: "¿Cuál es la capital administrativa de Sri Lanka?", options: ["Sri Jayawardenapura Kotte", "Colombo", "Kandy", "Galle"], answerIndex: 0 },
    ],
  },

  deportes: {
    name: "Deportes",
    order: 7,
    difficulty1: [
      { q: "¿Cuántos jugadores hay en un equipo de fútbol en el campo?", options: ["11", "10", "9", "12"], answerIndex: 0 },
      { q: "¿Cada cuántos años se celebran los Juegos Olímpicos de verano?", options: ["4", "2", "3", "5"], answerIndex: 0 },
      { q: "¿En qué deporte se usa una raqueta y una pelota amarilla sobre una cancha con red?", options: ["Tenis", "Bádminton", "Squash", "Ping pong"], answerIndex: 0 },
      { q: "¿Cuántos puntos vale un touchdown en fútbol americano (sin conversión)?", options: ["6", "7", "3", "2"], answerIndex: 0 },
      { q: "¿En qué país se originaron los Juegos Olímpicos antiguos?", options: ["Grecia", "Italia", "Egipto", "Francia"], answerIndex: 0 },
      { q: "¿Cuántos jugadores conforman un equipo de baloncesto en la cancha?", options: ["5", "6", "7", "4"], answerIndex: 0 },
      { q: "¿Qué deporte practica Lionel Messi?", options: ["Fútbol", "Baloncesto", "Tenis", "Rugby"], answerIndex: 0 },
      { q: "¿Cuántos aros de colores tiene el símbolo olímpico?", options: ["5", "4", "6", "3"], answerIndex: 0 },
      { q: '¿En qué deporte se realiza un "jaque mate"?', options: ["Ajedrez", "Damas", "Dominó", "Backgammon"], answerIndex: 0 },
      { q: "¿Qué deporte se juega en Wimbledon?", options: ["Tenis", "Golf", "Críquet", "Rugby"], answerIndex: 0 },
      { q: "¿Cuántos sets como máximo se juegan en un partido de tenis masculino de Grand Slam?", options: ["5", "3", "7", "4"], answerIndex: 0 },
      { q: "¿Qué país ha ganado más Copas Mundiales de fútbol?", options: ["Brasil", "Alemania", "Argentina", "Italia"], answerIndex: 0 },
      { q: "¿En qué deporte se compite en una piscina?", options: ["Natación", "Atletismo", "Ciclismo", "Remo"], answerIndex: 0 },
      { q: "¿Cuántos jugadores hay en un equipo de voleibol en cancha?", options: ["6", "5", "7", "4"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: "¿En qué ciudad se realizaron los Juegos Olímpicos de 2016?", options: ["Río de Janeiro", "Londres", "Tokio", "Pekín"], answerIndex: 0 },
      { q: '¿Qué boxeador es conocido como "El Más Grande" (The Greatest)?', options: ["Muhammad Ali", "Mike Tyson", "Sugar Ray Robinson", "Joe Frazier"], answerIndex: 0 },
      { q: "¿Cuántos hoyos tiene un campo de golf estándar?", options: ["18", "16", "20", "9"], answerIndex: 0 },
      { q: "¿Qué tenista ha ganado más títulos individuales de Grand Slam masculino (a 2023)?", options: ["Novak Djokovic", "Roger Federer", "Rafael Nadal", "Pete Sampras"], answerIndex: 0 },
      { q: "¿Qué país organizó el Mundial de Fútbol de 2014?", options: ["Brasil", "Sudáfrica", "Rusia", "Catar"], answerIndex: 0 },
      { q: "¿En qué deporte destaca Usain Bolt?", options: ["Atletismo (velocidad)", "Natación", "Ciclismo", "Salto largo"], answerIndex: 0 },
      { q: "¿Cuántos jinetes componen un equipo de polo?", options: ["4", "5", "6", "3"], answerIndex: 0 },
      { q: "¿Qué selección ganó el Mundial de Fútbol de 2022 en Catar?", options: ["Argentina", "Francia", "Brasil", "Croacia"], answerIndex: 0 },
      { q: '¿En qué deporte se usa el término "birdie"?', options: ["Golf", "Tenis", "Béisbol", "Bádminton"], answerIndex: 0 },
      { q: "¿Cuántos años dura un ciclo olímpico entre Juegos de Verano?", options: ["4", "2", "3", "5"], answerIndex: 0 },
      { q: "¿Qué nadador estadounidense ha ganado más medallas olímpicas de la historia?", options: ["Michael Phelps", "Mark Spitz", "Ryan Lochte", "Ian Thorpe"], answerIndex: 0 },
      { q: '¿Qué país es conocido por dominar el rugby con el equipo "All Blacks"?', options: ["Nueva Zelanda", "Australia", "Sudáfrica", "Inglaterra"], answerIndex: 0 },
      { q: '¿En qué deporte se disputa la "Vuelta a España"?', options: ["Ciclismo", "Atletismo", "Automovilismo", "Motociclismo"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: "¿Qué ciclista ganó siete Tours de Francia consecutivos antes de ser descalificado por dopaje?", options: ["Lance Armstrong", "Miguel Induráin", "Eddy Merckx", "Bernard Hinault"], answerIndex: 0 },
      { q: "¿En qué ciudad se celebraron los primeros Juegos Olímpicos de la era moderna en 1896?", options: ["Atenas", "Roma", "París", "Londres"], answerIndex: 0 },
      { q: "¿Qué boxeador ganó la medalla de oro olímpica en 1960 antes de ser campeón mundial de los pesos pesados?", options: ["Muhammad Ali (Cassius Clay)", "Joe Frazier", "George Foreman", "Sonny Liston"], answerIndex: 0 },
      { q: "¿Qué futbolista brasileño es el único en ganar tres Copas del Mundo como jugador?", options: ["Pelé", "Ronaldo", "Ronaldinho", "Kaká"], answerIndex: 0 },
      { q: '¿En qué deporte se usa el término "grand slam" para los cuatro torneos más importantes del año?', options: ["Tenis", "Golf", "Bádminton", "Squash"], answerIndex: 0 },
      { q: "¿Qué país ha ganado más medallas de oro en la historia de los Juegos Olímpicos de Verano?", options: ["Estados Unidos", "Unión Soviética", "China", "Reino Unido"], answerIndex: 0 },
      { q: "¿Qué corredor jamaiquino ostenta el récord mundial de los 100 metros planos?", options: ["Usain Bolt", "Yohan Blake", "Tyson Gay", "Justin Gatlin"], answerIndex: 0 },
      { q: "¿Qué maratonista keniano ha sido plusmarquista mundial de maratón?", options: ["Eliud Kipchoge", "Kenenisa Bekele", "Mo Farah", "Haile Gebrselassie"], answerIndex: 0 },
      { q: "¿Qué tenista ha ganado más veces el torneo de Roland Garros en la historia?", options: ["Rafael Nadal", "Novak Djokovic", "Roger Federer", "Björn Borg"], answerIndex: 0 },
      { q: "¿Qué equipo de la NBA ha ganado más campeonatos en la historia?", options: ["Boston Celtics", "Los Angeles Lakers", "Chicago Bulls", "Golden State Warriors"], answerIndex: 0 },
      { q: "¿Qué gimnasta estadounidense es la más condecorada en la historia de la gimnasia artística?", options: ["Simone Biles", "Nadia Comăneci", "Gabby Douglas", "Shannon Miller"], answerIndex: 0 },
      { q: "¿Qué país organizó y ganó el primer Mundial de Fútbol en 1930?", options: ["Uruguay", "Argentina", "Brasil", "Italia"], answerIndex: 0 },
      { q: "¿En qué disciplina compite un decatleta?", options: ["Atletismo combinado (10 pruebas)", "Natación", "Gimnasia", "Triatlón"], answerIndex: 0 },
    ],
  },

  videojuegos: {
    name: "Videojuegos",
    order: 8,
    difficulty1: [
      { q: "¿Qué compañía creó a Mario Bros?", options: ["Nintendo", "Sony", "Sega", "Microsoft"], answerIndex: 0 },
      { q: "¿Qué personaje azul y veloz es la mascota de Sega?", options: ["Sonic", "Mario", "Crash Bandicoot", "Rayman"], answerIndex: 0 },
      { q: '¿Qué videojuego popularizó el género "battle royale" junto con PUBG?', options: ["Fortnite", "Minecraft", "Roblox", "Among Us"], answerIndex: 0 },
      { q: '¿Qué compañía creó la saga "The Legend of Zelda"?', options: ["Nintendo", "PlayStation", "Xbox", "Sega"], answerIndex: 0 },
      { q: "¿Qué juego de construcción y supervivencia usa bloques cúbicos?", options: ["Minecraft", "Terraria", "Roblox", "Fortnite"], answerIndex: 0 },
      { q: '¿Qué compañía desarrolla la saga "Call of Duty"?', options: ["Activision", "Electronic Arts", "Ubisoft", "Rockstar Games"], answerIndex: 0 },
      { q: '¿Qué personaje es protagonista de "Grand Theft Auto V" junto a Michael y Franklin?', options: ["Trevor", "Niko", "CJ", "Tommy"], answerIndex: 0 },
      { q: "¿Qué juego de rol de mundo abierto sigue a Geralt de Rivia?", options: ["The Witcher 3", "Skyrim", "Dark Souls", "Elden Ring"], answerIndex: 0 },
      { q: "¿Qué compañía creó la consola PlayStation?", options: ["Sony", "Nintendo", "Microsoft", "Sega"], answerIndex: 0 },
      { q: "¿Qué juego de fútbol es desarrollado por EA Sports?", options: ["FC (antes FIFA)", "PES", "Football Manager", "Rocket League"], answerIndex: 0 },
      { q: '¿En qué videojuego los jugadores deben adivinar quién es el "impostor"?', options: ["Among Us", "Fall Guys", "Fortnite", "Minecraft"], answerIndex: 0 },
      { q: "¿Qué saga de videojuegos sigue las aventuras de un fontanero italiano?", options: ["Super Mario", "Sonic", "Crash Bandicoot", "Rayman"], answerIndex: 0 },
      { q: "¿Qué compañía desarrolla la consola Xbox?", options: ["Microsoft", "Sony", "Nintendo", "Sega"], answerIndex: 0 },
      { q: "¿Qué juego de simulación de vida permite construir casas y controlar personajes cotidianos?", options: ["The Sims", "SimCity", "Cities: Skylines", "Roller Coaster Tycoon"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: '¿Qué estudio desarrolló "The Last of Us"?', options: ["Naughty Dog", "Rockstar Games", "Bethesda", "CD Projekt Red"], answerIndex: 0 },
      { q: '¿Qué compañía polaca desarrolló "The Witcher 3"?', options: ["CD Projekt Red", "Ubisoft", "Bethesda", "Bioware"], answerIndex: 0 },
      { q: '¿Qué saga de disparos en primera persona incluye "Halo"?', options: ["Halo", "Call of Duty", "Battlefield", "Doom"], answerIndex: 0 },
      { q: "¿Qué juego de FromSoftware es considerado pionero del género souls-like?", options: ["Dark Souls", "Bloodborne", "Elden Ring", "Sekiro"], answerIndex: 0 },
      { q: "¿Qué videojuego de Rockstar está ambientado en el lejano oeste con Arthur Morgan como protagonista?", options: ["Red Dead Redemption 2", "Grand Theft Auto V", "L.A. Noire", "Max Payne"], answerIndex: 0 },
      { q: '¿Qué compañía japonesa desarrolla la saga "Final Fantasy"?', options: ["Square Enix", "Capcom", "Konami", "Bandai Namco"], answerIndex: 0 },
      { q: "¿Qué videojuego de Nintendo presenta a un elfo llamado Link en un mundo de fantasía?", options: ["The Legend of Zelda", "Fire Emblem", "Kirby", "Metroid"], answerIndex: 0 },
      { q: "¿Qué juego de terror y supervivencia de Capcom sigue a personajes en Raccoon City?", options: ["Resident Evil", "Silent Hill", "Dead Space", "The Evil Within"], answerIndex: 0 },
      { q: '¿Qué compañía desarrolla la saga "Assassin\'s Creed"?', options: ["Ubisoft", "Rockstar Games", "Bethesda", "Square Enix"], answerIndex: 0 },
      { q: "¿Qué videojuego de battle royale fue creado por Epic Games?", options: ["Fortnite", "PUBG", "Apex Legends", "Warzone"], answerIndex: 0 },
      { q: "¿Qué juego de estrategia de Blizzard se ambienta en un universo de ciencia ficción con tres razas?", options: ["StarCraft", "Warcraft", "Diablo", "Overwatch"], answerIndex: 0 },
      { q: "¿Qué videojuego de Naughty Dog sigue a Joel y Ellie en un mundo postapocalíptico?", options: ["The Last of Us", "Uncharted", "Days Gone", "Horizon Zero Dawn"], answerIndex: 0 },
      { q: '¿Qué compañía desarrolla la saga "Pokémon" junto con Nintendo?', options: ["Game Freak", "HAL Laboratory", "Intelligent Systems", "Retro Studios"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: '¿Quién es el creador principal de las sagas "Super Mario" y "The Legend of Zelda"?', options: ["Shigeru Miyamoto", "Satoru Iwata", "Hideo Kojima", "Shigesato Itoi"], answerIndex: 0 },
      { q: '¿Qué diseñador japonés es conocido por crear la saga "Metal Gear"?', options: ["Hideo Kojima", "Shigeru Miyamoto", "Yoji Shinkawa", "Hidetaka Miyazaki"], answerIndex: 0 },
      { q: '¿Qué diseñador es conocido como el creador de "Dark Souls", "Bloodborne" y "Elden Ring"?', options: ["Hidetaka Miyazaki", "Hideo Kojima", "Shigeru Miyamoto", "Yoko Taro"], answerIndex: 0 },
      { q: "¿En qué año se lanzó la primera PlayStation?", options: ["1994", "1990", "1998", "2000"], answerIndex: 0 },
      { q: "¿Qué videojuego arcade de Namco de 1980, con un personaje amarillo que come puntos, es un ícono de la industria?", options: ["Pac-Man", "Space Invaders", "Donkey Kong", "Frogger"], answerIndex: 0 },
      { q: '¿Qué compañía creó la consola "Sega Genesis/Mega Drive"?', options: ["Sega", "Nintendo", "Atari", "NEC"], answerIndex: 0 },
      { q: "¿Qué juego arcade de 1981 introdujo por primera vez al personaje que luego se convertiría en Mario?", options: ["Donkey Kong", "Mario Bros.", "Punch-Out!!", "Excitebike"], answerIndex: 0 },
      { q: '¿Qué estudio sueco creó "Minecraft" originalmente?', options: ["Mojang", "King", "DICE", "Massive Entertainment"], answerIndex: 0 },
      { q: "¿Qué motor gráfico, desarrollado por Epic Games, es ampliamente usado en la industria?", options: ["Unreal Engine", "Unity", "CryEngine", "Frostbite"], answerIndex: 0 },
      { q: '¿Qué entrega de "Final Fantasy" es considerada la más vendida de la saga?', options: ["Final Fantasy VII", "Final Fantasy X", "Final Fantasy VI", "Final Fantasy IX"], answerIndex: 0 },
      { q: '¿Qué compañía desarrolló originalmente la saga "Tomb Raider" con Lara Croft?', options: ["Core Design", "Crystal Dynamics", "Eidos", "Square Enix"], answerIndex: 0 },
      { q: "¿Qué videojuego dirigido por Fumito Ueda presenta a un niño y una criatura gigante llamada Trico?", options: ["The Last Guardian", "Shadow of the Colossus", "Ico", "Journey"], answerIndex: 0 },
      { q: '¿Qué compañía es responsable de la consola "Atari 2600", pionera en los años 70?', options: ["Atari", "Magnavox", "Coleco", "Mattel"], answerIndex: 0 },
    ],
  },

  libros: {
    name: "Libros",
    order: 9,
    difficulty1: [
      { q: '¿Quién escribió "Don Quijote de la Mancha"?', options: ["Miguel de Cervantes", "Lope de Vega", "Federico García Lorca", "Gabriel García Márquez"], answerIndex: 0 },
      { q: '¿Quién escribió la saga de "Harry Potter"?', options: ["J.K. Rowling", "J.R.R. Tolkien", "C.S. Lewis", "Suzanne Collins"], answerIndex: 0 },
      { q: '¿Qué autor colombiano escribió "Cien años de soledad"?', options: ["Gabriel García Márquez", "Mario Vargas Llosa", "Julio Cortázar", "Jorge Luis Borges"], answerIndex: 0 },
      { q: "¿Qué escritor creó a Sherlock Holmes?", options: ["Arthur Conan Doyle", "Agatha Christie", "Edgar Allan Poe", "H.G. Wells"], answerIndex: 0 },
      { q: '¿Qué autor escribió "Romeo y Julieta"?', options: ["William Shakespeare", "Charles Dickens", "Oscar Wilde", "Jane Austen"], answerIndex: 0 },
      { q: '¿Qué saga de fantasía incluye libros como "El Señor de los Anillos"?', options: ["El Señor de los Anillos", "Harry Potter", "Narnia", "Percy Jackson"], answerIndex: 0 },
      { q: '¿Qué autora escribió "Orgullo y prejuicio"?', options: ["Jane Austen", "Charlotte Brontë", "Virginia Woolf", "Mary Shelley"], answerIndex: 0 },
      { q: "¿Qué libro narra la historia de un niño mago que estudia en Hogwarts?", options: ["Harry Potter", "Percy Jackson", "Eragon", "Las Crónicas de Narnia"], answerIndex: 0 },
      { q: '¿Qué escritora chilena escribió "La casa de los espíritus"?', options: ["Isabel Allende", "Pablo Neruda", "Gabriela Mistral", "Roberto Bolaño"], answerIndex: 0 },
      { q: '¿Qué autor escribió "1984"?', options: ["George Orwell", "Aldous Huxley", "Ray Bradbury", "Franz Kafka"], answerIndex: 0 },
      { q: "¿Qué escritora británica creó al detective Hércules Poirot?", options: ["Agatha Christie", "Arthur Conan Doyle", "P.D. James", "Dorothy Sayers"], answerIndex: 0 },
      { q: '¿Qué autor escribió "El Principito"?', options: ["Antoine de Saint-Exupéry", "Julio Verne", "Víctor Hugo", "Albert Camus"], answerIndex: 0 },
      { q: "¿Qué saga trata sobre un joven llamado Percy Jackson, hijo de un dios griego?", options: ["Percy Jackson y los dioses del Olimpo", "Harry Potter", "Narnia", "Eragon"], answerIndex: 0 },
      { q: "¿Qué escritor peruano ganó el Premio Nobel de Literatura en 2010?", options: ["Mario Vargas Llosa", "Gabriel García Márquez", "Octavio Paz", "Pablo Neruda"], answerIndex: 0 },
    ],
    difficulty2: [
      { q: '¿Qué autor mexicano escribió "Pedro Páramo"?', options: ["Juan Rulfo", "Octavio Paz", "Carlos Fuentes", "José Emilio Pacheco"], answerIndex: 0 },
      { q: "¿Qué novela de Fiódor Dostoyevski narra la historia de un estudiante que comete un asesinato?", options: ["Crimen y castigo", "Los hermanos Karamázov", "El idiota", "Guerra y paz"], answerIndex: 0 },
      { q: '¿Qué autor argentino escribió "Rayuela"?', options: ["Julio Cortázar", "Jorge Luis Borges", "Adolfo Bioy Casares", "Ernesto Sabato"], answerIndex: 0 },
      { q: '¿Qué escritor estadounidense escribió "Matar a un ruiseñor"?', options: ["Harper Lee", "Mark Twain", "Ernest Hemingway", "John Steinbeck"], answerIndex: 0 },
      { q: '¿Qué autora escribió la trilogía distópica "Los Juegos del Hambre"?', options: ["Suzanne Collins", "Veronica Roth", "James Dashner", "Stephenie Meyer"], answerIndex: 0 },
      { q: '¿Qué escritor ruso escribió "Guerra y paz"?', options: ["León Tolstói", "Fiódor Dostoyevski", "Antón Chéjov", "Nikolái Gógol"], answerIndex: 0 },
      { q: '¿Qué autor español de la Generación del 27 escribió "Romancero gitano"?', options: ["Federico García Lorca", "Rafael Alberti", "Vicente Aleixandre", "Pedro Salinas"], answerIndex: 0 },
      { q: '¿Qué escritora inglesa escribió "Frankenstein"?', options: ["Mary Shelley", "Jane Austen", "Emily Brontë", "Virginia Woolf"], answerIndex: 0 },
      { q: "¿Qué novela de Gabriel García Márquez narra la historia de Florentino Ariza esperando a Fermina Daza?", options: ["El amor en los tiempos del cólera", "Cien años de soledad", "Crónica de una muerte anunciada", "El otoño del patriarca"], answerIndex: 0 },
      { q: '¿Qué autor checo escribió "La metamorfosis"?', options: ["Franz Kafka", "Milan Kundera", "Bohumil Hrabal", "Karel Čapek"], answerIndex: 0 },
      { q: '¿Qué escritor estadounidense escribió "El gran Gatsby"?', options: ["F. Scott Fitzgerald", "Ernest Hemingway", "William Faulkner", "John Steinbeck"], answerIndex: 0 },
      { q: "¿Qué saga juvenil sigue a una chica llamada Katniss Everdeen?", options: ["Los Juegos del Hambre", "Divergente", "Maze Runner", "Crepúsculo"], answerIndex: 0 },
      { q: "¿Qué poeta chilena ganó el Premio Nobel de Literatura en 1945?", options: ["Gabriela Mistral", "Pablo Neruda", "Isabel Allende", "Vicente Huidobro"], answerIndex: 0 },
    ],
    difficulty3: [
      { q: "¿Qué novela de Umberto Eco está ambientada en un monasterio medieval con una serie de misteriosos asesinatos?", options: ["El nombre de la rosa", "El péndulo de Foucault", "Baudolino", "La isla del día de antes"], answerIndex: 0 },
      { q: '¿Qué escritor irlandés escribió "Ulises", una obra maestra del modernismo?', options: ["James Joyce", "Samuel Beckett", "Oscar Wilde", "W.B. Yeats"], answerIndex: 0 },
      { q: '¿Qué autor colombiano escribió "El coronel no tiene quien le escriba"?', options: ["Gabriel García Márquez", "Álvaro Mutis", "Jorge Isaacs", "José Eustasio Rivera"], answerIndex: 0 },
      { q: '¿Qué novelista francés escribió "En busca del tiempo perdido"?', options: ["Marcel Proust", "Victor Hugo", "Gustave Flaubert", "Émile Zola"], answerIndex: 0 },
      { q: '¿Qué escritor argentino, célebre por sus cuentos y laberintos literarios, escribió "Ficciones"?', options: ["Jorge Luis Borges", "Julio Cortázar", "Adolfo Bioy Casares", "Ernesto Sabato"], answerIndex: 0 },
      { q: '¿Qué autor ruso escribió "Crimen y castigo" mientras enfrentaba dificultades económicas propias?', options: ["Fiódor Dostoyevski", "León Tolstói", "Iván Turguénev", "Nikolái Gógol"], answerIndex: 0 },
      { q: '¿Qué escritor uruguayo escribió "Las venas abiertas de América Latina"?', options: ["Eduardo Galeano", "Mario Benedetti", "Juan Carlos Onetti", "Horacio Quiroga"], answerIndex: 0 },
      { q: "¿Qué obra de teatro de Shakespeare trata sobre un príncipe danés que busca vengar la muerte de su padre?", options: ["Hamlet", "Macbeth", "Otelo", "El rey Lear"], answerIndex: 0 },
      { q: '¿Qué escritor portugués ganó el Premio Nobel de Literatura en 1998 por obras como "Ensayo sobre la ceguera"?', options: ["José Saramago", "Fernando Pessoa", "Eça de Queirós", "Miguel Torga"], answerIndex: 0 },
      { q: '¿Qué autor estadounidense escribió "Moby Dick"?', options: ["Herman Melville", "Nathaniel Hawthorne", "Mark Twain", "Edgar Allan Poe"], answerIndex: 0 },
      { q: '¿Qué escritor británico escribió la distopía "Un mundo feliz"?', options: ["Aldous Huxley", "George Orwell", "H.G. Wells", "Anthony Burgess"], answerIndex: 0 },
      { q: "¿Qué poeta español fue fusilado al inicio de la Guerra Civil Española en 1936?", options: ["Federico García Lorca", "Miguel Hernández", "Antonio Machado", "Rafael Alberti"], answerIndex: 0 },
      { q: '¿Qué autor brasileño escribió "Dom Casmurro"?', options: ["Machado de Assis", "Jorge Amado", "Paulo Coelho", "Clarice Lispector"], answerIndex: 0 },
    ],
  },
};

function allQuestions(cat) {
  return [...cat.difficulty1, ...cat.difficulty2, ...cat.difficulty3];
}

// Deterministic rotation so 10 levels x 10 questions draw evenly from the
// 40-question pool (same spirit as the old seed_fixed_levels.js, just with
// a much bigger source pool so repeats are far less noticeable).
function pickQuestions(pool, count, levelNumber) {
  const out = [];
  let idx = (levelNumber * 7) % pool.length;
  for (let i = 0; i < count; i++) {
    out.push(pool[idx]);
    idx = (idx + 1) % pool.length;
  }
  return out;
}

const LEVEL_COUNT = 10;
const QUESTIONS_PER_LEVEL = 10;

async function seedSoloLevels(categoryId, cat) {
  const categoryRef = db.collection("fixed_categories").doc(categoryId);

  await categoryRef.set(
    {
      name: cat.name,
      order: cat.order,
      levelCount: LEVEL_COUNT,
      isActive: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const pool = allQuestions(cat);

  for (let level = 1; level <= LEVEL_COUNT; level++) {
    const questions = pickQuestions(pool, QUESTIONS_PER_LEVEL, level);

    await categoryRef.collection("levels").doc(String(level)).set(
      {
        levelNumber: level,
        questionCount: QUESTIONS_PER_LEVEL,
        questions,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  console.log(`  fixed_categories/${categoryId}: ${LEVEL_COUNT} niveles (pool de ${pool.length} preguntas)`);
}

async function seedDifficultyPools(categoryId, cat) {
  const tiers = [
    [1, cat.difficulty1],
    [2, cat.difficulty2],
    [3, cat.difficulty3],
  ];

  for (const [d, list] of tiers) {
    const metaRef = db
      .collection("fixed_pools")
      .doc(categoryId)
      .collection(`difficulty_${d}`)
      .doc("meta");

    await metaRef.set(
      { updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    const questionsCol = db
      .collection("fixed_pools")
      .doc(categoryId)
      .collection(`difficulty_${d}`)
      .doc("pool")
      .collection("questions");

    const batch = db.batch();

    list.forEach((q, idx) => {
      batch.set(questionsCol.doc(`q${idx + 1}`), {
        ...q,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`  fixed_pools/${categoryId}/difficulty_${d}: ${list.length} preguntas`);
  }
}

async function run() {
  for (const [categoryId, cat] of Object.entries(CATEGORIES)) {
    console.log(`Sembrando ${cat.name} (${categoryId})...`);
    await seedSoloLevels(categoryId, cat);
    await seedDifficultyPools(categoryId, cat);
  }

  console.log("Listo.");
  process.exit(0);
}

run().catch((e) => {
  console.error("Error:", e);
  process.exit(1);
});
