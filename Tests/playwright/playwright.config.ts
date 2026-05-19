// tests/playwright/playwright.config.ts
import { defineConfig } from "@playwright/test";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

// Resolve repo root from this file's location.
const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

// Scaffold a fresh demo project once per test session.
const DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-e2e-"));
const DEMO_PROJECT = join(DEMO_TMP, "demo");

// Build swiflow CLI if not present. execFileSync (no shell) so paths
// don't need quoting and there's no shell-interpolation surface.
if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the e2e harness...");
  execFileSync(
    "swift",
    ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" }
  );
}

// Init the demo. Args passed as an array — no shell escaping needed.
execFileSync(
  SWIFLOW,
  ["init", "demo", "--path", DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

export default defineConfig({
  testDir: ".",
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: {
    command: `${SWIFLOW} dev`,
    cwd: DEMO_PROJECT,
    url: "http://127.0.0.1:3000",
    reuseExistingServer: false,
    timeout: 300_000,  // cold WASM build can take ~3 min
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
