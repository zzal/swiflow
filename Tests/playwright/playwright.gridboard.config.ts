// Tests/playwright/playwright.gridboard.config.ts
//
// Serves examples/GridBoard IN-PLACE (swiflow dev --path …) on :3009 —
// smoke coverage for the GridBoard showcase template.
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "GridBoard");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["gridboard.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3009", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3009`,
      url: "http://127.0.0.1:3009",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
