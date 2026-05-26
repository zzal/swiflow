// Tests/playwright/playwright.sw.config.ts
//
// SW-only Playwright config. Runs ONLY sw-cache.spec.ts against ONLY the
// release-mode static server on :3002 — skips the Counter (:3000) and
// RouterDemo (:3001) dev servers entirely. Use this for fast local
// iteration on the SW caching behaviour.
//
//     npx playwright test --config=playwright.sw.config.ts
//
// CI continues to use the default playwright.config.ts, which runs ALL
// three webServers and ALL specs (including this one) on every PR.
//
// The SW demo setup (scaffold + release build) is intentionally
// duplicated from playwright.config.ts rather than extracted to a shared
// module: Playwright eagerly evaluates config files at load time, so
// sharing setup via module import introduces hoist-ordering and side-
// effect-on-import concerns that aren't worth ~20 lines of avoided
// duplication. Keep this block in sync with the matching section in
// playwright.config.ts; the comment headers in both files reference
// each other.
import { defineConfig } from "@playwright/test";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

const SW_DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-sw-e2e-"));
const SW_DEMO_PROJECT = join(SW_DEMO_TMP, "demo");

if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the SW e2e harness...");
  execFileSync(
    "swift",
    ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" }
  );
}

console.log("Initialising SW e2e demo project...");
execFileSync(
  SWIFLOW,
  ["init", "demo", "--path", SW_DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

console.log("Running swiflow build for SW e2e demo (release WASM — ~3 min cold)...");
execFileSync(
  SWIFLOW,
  ["build", "--path", SW_DEMO_PROJECT],
  { stdio: "inherit", cwd: SW_DEMO_PROJECT }
);

export default defineConfig({
  testDir: ".",
  testMatch: ["sw-cache.spec.ts", "progress.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:3002",
    trace: "on-first-retry",
  },
  webServer: [
    {
      // python3 is universally available on macOS and CI (no npm install).
      command: "python3 -m http.server 3002",
      cwd: SW_DEMO_PROJECT,
      url: "http://127.0.0.1:3002",
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
