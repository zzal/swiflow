// Tests/playwright/playwright.counter.config.ts
//
// Counter-only Playwright config. Runs ONLY counter.spec.ts against ONLY
// the Counter dev server on :3000 — skips the RouterDemo (:3001) dev
// server and the SW release demo (:3002). Use this for fast local
// iteration on the Counter / `@State` / HMR happy path.
//
//     npm run test:counter
//     # or directly:
//     npx playwright test --config=playwright.counter.config.ts
//
// CI continues to use the default playwright.config.ts, which runs ALL
// servers and ALL specs.
//
// The Counter demo setup (scaffold via `swiflow init`) is intentionally
// duplicated from playwright.config.ts rather than extracted to a shared
// module: Playwright eagerly evaluates config files at load time, so
// sharing setup via module import introduces hoist-ordering and side-
// effect-on-import concerns that aren't worth ~20 lines of avoided
// duplication. Mirror playwright.sw.config.ts's split decision.
import { defineConfig } from "@playwright/test";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

const DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-e2e-"));
const DEMO_PROJECT = join(DEMO_TMP, "demo");

if (!existsSync(SWIFLOW)) {
  console.log("Building swiflow CLI (release) for the e2e harness...");
  execFileSync(
    "swift",
    ["build", "-c", "release", "--product", "swiflow"],
    { cwd: REPO_ROOT, stdio: "inherit" }
  );
}

execFileSync(
  SWIFLOW,
  ["init", "demo", "--path", DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

export default defineConfig({
  testDir: ".",
  testMatch: ["counter.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: [
    {
      command: `'${SWIFLOW}' dev`,
      cwd: DEMO_PROJECT,
      url: "http://127.0.0.1:3000",
      reuseExistingServer: false,
      timeout: 300_000,  // cold WASM build can take ~3 min
    },
  ],
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
