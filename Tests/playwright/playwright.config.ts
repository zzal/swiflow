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
const ROUTER_DEMO_ROOT = join(REPO_ROOT, "examples", "RouterDemo");

// SW cache e2e: scaffold a separate demo project and run a release build
// so the service worker registers (SW is skipped in dev mode).
const SW_DEMO_TMP = mkdtempSync(join(tmpdir(), "swiflow-sw-e2e-"));
const SW_DEMO_PROJECT = join(SW_DEMO_TMP, "demo");

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

// ── SW cache e2e setup ────────────────────────────────────────────────────────
// NOTE: this block is duplicated in playwright.sw.config.ts so that local
// dev can run `npm run test:sw` without spinning up the Counter or
// RouterDemo dev servers. Keep both copies in sync.
// Service workers only register in release builds (dev mode skips registration
// to avoid fighting HMR). We scaffold a separate demo and run `swiflow build`;
// the build writes swiflow-manifest.json directly to the project root, where
// the SW resolves it.
console.log("Initialising SW e2e demo project...");
execFileSync(
  SWIFLOW,
  ["init", "demo", "--path", SW_DEMO_TMP, "--swiflow-source", REPO_ROOT],
  { stdio: "inherit" }
);

console.log("Running swiflow build for SW e2e demo (release WASM — this can take ~3 min)...");
execFileSync(
  SWIFLOW,
  ["build", "--path", SW_DEMO_PROJECT],
  { stdio: "inherit", cwd: SW_DEMO_PROJECT }
);
// ─────────────────────────────────────────────────────────────────────────────

export default defineConfig({
  testDir: ".",
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
    {
      command: `'${SWIFLOW}' dev --port 3001`,
      cwd: ROUTER_DEMO_ROOT,
      url: "http://127.0.0.1:3001",
      reuseExistingServer: false,
      timeout: 300_000,
    },
    {
      // Release build served by python3's built-in HTTP server. The build
      // already ran synchronously above (at config-load time); this entry
      // just brings up the static server so Playwright can probe its
      // readiness via the `url` field.
      // python3 is used rather than npx http-server / npx serve because
      // python3 is universally available on macOS and CI (no npm install
      // required), and the zero-dependency option is always preferred.
      command: "python3 -m http.server 3002",
      cwd: SW_DEMO_PROJECT,
      url: "http://127.0.0.1:3002",
      reuseExistingServer: false,
      timeout: 30_000,  // static server starts instantly; generous for CI
    },
  ],
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
