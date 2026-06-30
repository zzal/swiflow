// Tests/playwright/playwright.todocrud.config.ts
//
// Opt-in real-backend e2e for examples/TodoCRUD: boots the actual Bun + SQLite
// backend AND `swiflow dev`, then runs todocrud.spec.ts against real HTTP/CORS.
// Gated in CI behind the `run-e2e-backend` label; locally: `npm run test:todocrud`
// (requires Bun on PATH).
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "TodoCRUD");
const BACKEND = join(EXAMPLE_DIR, "backend", "server.ts");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["todocrud.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3002", trace: "on-first-retry" },
  webServer: [
    {
      command: `bun run '${BACKEND}'`,
      url: "http://127.0.0.1:8080/todos", // GET /todos is the readiness probe
      reuseExistingServer: false,
      timeout: 60_000,
    },
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3002`,
      url: "http://127.0.0.1:3002",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
