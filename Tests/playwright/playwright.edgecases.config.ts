// Tests/playwright/playwright.edgecases.config.ts
//
// Builds examples/EdgeCases IN-PLACE (swiflow dev --path …) on :3003 — no
// `swiflow init` scaffold, so the e2e tests the real example source directly.
// Mirrors playwright.counter.config.ts's release-CLI-build guard.
import { defineConfig } from "@playwright/test";
import { existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");
const EXAMPLE_DIR = join(REPO_ROOT, "examples", "EdgeCases");

if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the e2e harness...");
  execFileSync("swift", ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" });
}

export default defineConfig({
  testDir: ".",
  testMatch: ["edgecases.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3003", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3003`,
      url: "http://127.0.0.1:3003",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
