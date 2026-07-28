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
