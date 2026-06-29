// Tests/playwright/playwright.swiflowui.config.ts
//
// Builds examples/SwiflowUIDemo IN-PLACE (swiflow dev --path …) on :3004 — no
// `swiflow init` scaffold, so the e2e tests the real demo source directly and
// never touches the .e2e-cache/sw scaffold cache (the SourceKit-LSP race).
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "SwiflowUIDemo");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["dropdown.spec.ts", "datatable.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3004", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3004`,
      url: "http://127.0.0.1:3004",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
