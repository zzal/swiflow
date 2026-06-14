// Tests/playwright/playwright.sw.config.ts
//
// SW-only Playwright config. Runs ONLY sw-cache.spec.ts + progress.spec.ts
// against ONLY the release-mode static server on :3002 — skips the Counter
// (:3000) and MiniRouter (:3001) dev servers entirely. Use this for fast local
// iteration on the SW caching behaviour.
//
//     npm run test:sw
//     # or directly:
//     npx playwright test --config=playwright.sw.config.ts
//
// The SW demo is scaffolded and release-built (`release: true`) by
// prepareDemo(). Service workers only register in release builds (dev mode
// skips registration to avoid fighting HMR); the build writes
// swiflow-manifest.json to the project root, where the SW resolves it. The demo
// persists under .e2e-cache/sw/demo, so the ~3 min release build only pays its
// full cost on the first run / after SWIFLOW_E2E_CLEAN=1 — subsequent runs do a
// fast incremental relink.
//
// CI continues to use the default playwright.config.ts, which runs ALL
// three webServers and ALL specs (including this one) on every PR.
import { defineConfig } from "@playwright/test";
import { prepareDemo } from "./harness";

const SW_DEMO_PROJECT = prepareDemo({ key: "sw", release: true });

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
