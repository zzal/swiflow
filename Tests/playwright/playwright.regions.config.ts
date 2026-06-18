// Tests/playwright/playwright.regions.config.ts
//
// Builds examples/RegionDemo IN-PLACE (swiflow dev --path …) on :3004 — no
// `swiflow init` scaffold (RegionDemo isn't a template; its AssemblyScript wasm
// guest can't round-trip the UTF-8 codegen). The e2e drives the real example
// source, proving an external wasm guest runs through the Regions runtime.
import { defineConfig } from "@playwright/test";
import { join } from "node:path";
import { SWIFLOW, REPO_ROOT, ensureCli } from "./harness";

const EXAMPLE_DIR = join(REPO_ROOT, "examples", "RegionDemo");

ensureCli();

export default defineConfig({
  testDir: ".",
  testMatch: ["region.spec.ts"],
  fullyParallel: false,
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL: "http://127.0.0.1:3004", trace: "on-first-retry" },
  webServer: [
    {
      command: `'${SWIFLOW}' dev --path '${EXAMPLE_DIR}' --port 3004`,
      url: "http://127.0.0.1:3004",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
