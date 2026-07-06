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
// The MiniRouter demo is served in place from `examples/MiniRouter` — it's a
// read-only feature demo, not a scaffoldable `--template` (InitCommand excludes
// MiniRouter/RegionDemo/AsyncFetch), so `swiflow dev` builds it against the
// repo's Swiflow via its own `../..` path dependency.
//
// CI continues to use the default playwright.config.ts, which runs ALL
// servers and ALL specs.
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const ROUTER_DIR = join(REPO_ROOT, "examples", "MiniRouter");

ensureCli();

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
      command: `'${SWIFLOW}' dev --path '${ROUTER_DIR}' --port 3001`,
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
