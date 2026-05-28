// Tests/playwright/playwright.router.config.ts
//
// Router-only Playwright config. Runs ONLY router.spec.ts against ONLY
// the MiniRouter dev server on :3001 — skips the Counter (:3000) dev
// server and the SW release demo (:3002). Use this for fast local
// iteration on `SwiflowRouter` / `Link` / hash-mode navigation.
//
//     npm run test:router
//     # or directly:
//     npx playwright test --config=playwright.router.config.ts
//
// The MiniRouter demo is scaffolded fresh into a temp dir via
// `swiflow init demo --template MiniRouter`. That dogfoods the
// --template flag end-to-end and keeps the e2e harness independent
// of any state in examples/MiniRouter/.
//
// CI continues to use the default playwright.config.ts, which runs ALL
// servers and ALL specs.
import { defineConfig } from "@playwright/test";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

const ROUTER_DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-router-e2e-"));
const ROUTER_DEMO_PROJECT = join(ROUTER_DEMO_TMP, "demo");

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
  ["init", "demo", "--template", "MiniRouter", "--path", ROUTER_DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

export default defineConfig({
  testDir: ".",
  testMatch: ["router.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:3001",
    trace: "on-first-retry",
  },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --port 3001`,
      cwd: ROUTER_DEMO_PROJECT,
      url: "http://127.0.0.1:3001",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
