// Preguntas nuevas para completar los pools de categorias fijas hasta 30/40/30.
// Una entrada por categoria activa de fixed_categories.
module.exports = {
  arte: require("./fill_pools/arte"),
  ciencia: require("./fill_pools/ciencia"),
  cine: require("./fill_pools/cine"),
  deportes: require("./fill_pools/deportes"),
  geografia: require("./fill_pools/geografia"),
  historia: require("./fill_pools/historia"),
  libros: require("./fill_pools/libros"),
  musica: require("./fill_pools/musica"),
  videojuegos: require("./fill_pools/videojuegos"),
};
