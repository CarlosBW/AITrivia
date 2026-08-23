/**
 * CSV minimo (RFC 4180) sin dependencias.
 *
 * Hace falta un parser de verdad y no un `split(",")`: los enunciados llevan
 * comas, comillas y signos de interrogacion de apertura, y una hoja de
 * calculo los devuelve entrecomillados con las comillas internas dobladas.
 */

/** Serializa una matriz de celdas. `sep` permite `;` para Excel en es-ES. */
function stringify(rows, sep = ",") {
  const cell = (value) => {
    const text = value == null ? "" : String(value);
    if (text.includes(sep) || text.includes('"') || /[\r\n]/.test(text)) {
      return `"${text.replace(/"/g, '""')}"`;
    }
    return text;
  };
  // BOM para que Excel abra el archivo como UTF-8; sin el, los acentos y las
  // eñes llegan rotos y la correccion vuelve peor que el original.
  return "﻿" + rows.map((r) => r.map(cell).join(sep)).join("\r\n") + "\r\n";
}

/** Parsea un CSV completo a una matriz de celdas. */
function parse(text, sep = ",") {
  const input = text.replace(/^﻿/, "");
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  let i = 0;

  const endField = () => {
    row.push(field);
    field = "";
  };
  const endRow = () => {
    endField();
    rows.push(row);
    row = [];
  };

  while (i < input.length) {
    const c = input[i];

    if (quoted) {
      if (c === '"') {
        if (input[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        quoted = false;
        i++;
        continue;
      }
      field += c;
      i++;
      continue;
    }

    if (c === '"' && field === "") {
      quoted = true;
      i++;
    } else if (c === sep) {
      endField();
      i++;
    } else if (c === "\r") {
      i++;
    } else if (c === "\n") {
      endRow();
      i++;
    } else {
      field += c;
      i++;
    }
  }

  if (field !== "" || row.length) endRow();

  // Una hoja de calculo suele dejar filas vacias al final.
  return rows.filter((r) => r.some((cell) => cell.trim() !== ""));
}

/** Parsea usando la primera fila como cabecera y devuelve objetos. */
function parseObjects(text, sep = ",") {
  const rows = parse(text, sep);
  if (!rows.length) return {header: [], records: []};

  const header = rows[0].map((h) => h.trim());
  const records = rows.slice(1).map((cells, index) => {
    const record = {__line: index + 2};
    header.forEach((name, col) => {
      record[name] = (cells[col] ?? "").trim();
    });
    return record;
  });

  return {header, records};
}

module.exports = {stringify, parse, parseObjects};
