import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    setupFiles: ["./tests/setup.ts"],
    testTimeout: 30_000,
    hookTimeout: 120_000,
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
});
