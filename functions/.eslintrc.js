module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/generated/**/*", // Ignore generated files.
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    // The google config enforces LF, but this repo is developed on Windows
    // with git's core.autocrlf=true, so every checkout writes CRLF and the
    // rule can never pass — it was failing on thousands of lines and, since
    // `firebase deploy` runs this lint as a predeploy step, it silently
    // blocked every Cloud Functions deploy. Purely cosmetic rule; off.
    "linebreak-style": 0,
  },
};
