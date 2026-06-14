// Tests/playwright/playwright.counter.config.ts
//
// Counter-only Playwright config. Runs ONLY counter.spec.ts +
// devtools-api.spec.ts against ONLY the Counter dev server on :3000 — skips the
// MiniRouter (:3001) dev server and the SW release demo (:3002). Use this for
// fast local iteration on the Counter / `@State` / HMR happy path.
//
//     npm run test:counter
//     # or directly:
//     npx playwright test --config=playwright.counter.config.ts
//
// CI continues to use the default playwright.config.ts, which runs ALL
// servers and ALL specs.
//
// Demo scaffolding/persistence lives in harness.ts (a side-effect-free module
// whose `prepareDemo()` runs at the same point the inline setup used to). The
// demo persists under .e2e-cache/counter/demo across runs; SWIFLOW_E2E_CLEAN=1
// forces a fresh cold build.
import { defineConfig } from "@playwright/test";
import { SWIFLOW, prepareDemo } from "./harness";

const DEMO_PROJECT = prepareDemo({ key: "counter" });

export default defineConfig({
  testDir: ".",
  testMatch: ["counter.spec.ts", "devtools-api.spec.ts"],
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
