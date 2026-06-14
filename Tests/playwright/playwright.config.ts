// tests/playwright/playwright.config.ts
//
// Default config — runs ALL specs against ALL servers (CI uses this).
// Counter (:3000) + MiniRouter (:3001) dev servers, plus the release SW demo
// served statically on :3002.
//
// Demo projects are scaffolded + persisted by `prepareDemo()` (see harness.ts):
// each lives under .e2e-cache/<key>/demo and reuses its .build between runs.
// Set SWIFLOW_E2E_CLEAN=1 (or `npm run test:clean`) to force fresh cold builds.
import { defineConfig } from "@playwright/test";
import { SWIFLOW, prepareDemo } from "./harness";

const DEMO_PROJECT = prepareDemo({ key: "counter" });
const ROUTER_DEMO_PROJECT = prepareDemo({ key: "router", template: "MiniRouter" });
// Service workers only register in release builds (dev mode skips registration
// to avoid fighting HMR), so the SW demo is built with `swiflow build`. The
// build writes swiflow-manifest.json to the project root, where the SW resolves it.
const SW_DEMO_PROJECT = prepareDemo({ key: "sw", release: true });

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
      cwd: ROUTER_DEMO_PROJECT,
      url: "http://127.0.0.1:3001",
      reuseExistingServer: false,
      timeout: 300_000,
    },
    {
      // Release build served by python3's built-in HTTP server. The build
      // already ran (inside prepareDemo at config-load time); this entry just
      // brings up the static server so Playwright can probe its readiness.
      // python3 is used rather than npx http-server / serve because it's
      // universally available on macOS and CI (no npm install required).
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
