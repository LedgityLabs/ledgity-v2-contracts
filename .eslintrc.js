module.exports = {
  env: {
    browser: false,
    es2021: true,
    mocha: true,
    node: true,
  },
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    ecmaVersion: 12,
    sourceType: "module",
  },
  rules: {
    // TypeScript specific rules
    "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    "@typescript-eslint/no-explicit-any": "warn",
    "@typescript-eslint/explicit-function-return-type": "off",
    "@typescript-eslint/explicit-module-boundary-types": "off",
    "@typescript-eslint/no-non-null-assertion": "warn",
    
    // General JavaScript/TypeScript rules
    "no-console": "warn",
    "no-debugger": "error",
    "no-unused-vars": "off", // Use TypeScript version instead
    "prefer-const": "error",
    "no-var": "error",
    
    // Code style
    "quotes": ["error", "double"],
    "semi": ["error", "always"],
    "comma-dangle": ["error", "always-multiline"],
    "object-curly-spacing": ["error", "always"],
    "array-bracket-spacing": ["error", "never"],
    
    // Best practices
    "eqeqeq": ["error", "always"],
    "curly": ["error", "all"],
    "no-eval": "error",
    "no-implied-eval": "error",
    "no-new-func": "error",
  },
  overrides: [
    {
      files: ["hardhat.config.*"],
      env: {
        node: true,
      },
    },
    {
      files: ["deployers/**/*", "tasks/**/*"],
      rules: {
        "no-console": "off", // Allow console logs in deployment scripts
      },
    },
  ],
  ignorePatterns: [
    "node_modules/",
    "dist/",
    "artifacts/",
    "cache/",
    "typechain-types/",
    "foundry/",
    "data/abis/",
    "*.json",
  ],
};
