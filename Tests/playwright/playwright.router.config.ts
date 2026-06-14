// Tests/playwright/playwright.router.config.ts
//
// Router-only Playwright config. Runs ONLY router.spec.ts against ONLY the
// MiniRouter dev server on :3001 — skips the Counter (:3000) dev server and the
// SW release demo (:3002). Use this for fast local iteration on
// `SwiflowRouter` / `Link` / hash-mode navigation.
//
//     npm run test:router
//     # or directly:
//     npx playwright test --config=playwright.router.config.ts
//
// The MiniRouter demo is scaffolded via `swiflow init demo --template
// MiniRouter` (dogfoods --template) and persisted under .e2e-cache/router/demo
// across runs. SWIFLOW_E2E_CLEAN=1 forces a fresh cold build.
//
// CI continues to use the default playwright.config.ts, which runs ALL
// servers and ALL specs.
import { defineConfig } from "@playwright/test";
import { SWIFLOW, prepareDemo } from "./harness";

const ROUTER_DEMO_PROJECT = prepareDemo({ key: "router", template: "MiniRouter" });

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
