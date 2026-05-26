// Tests/playwright/sw-cache.spec.ts
//
// Verifies that the Swiflow service worker caches App.wasm on the first visit
// and serves it from cache on the second visit (fromServiceWorker() === true).
//
// This spec runs against a RELEASE build served statically on port 3002
// (set up in playwright.config.ts). The SW is intentionally disabled in dev
// mode (window.SWIFLOW_DEV) so this test cannot run against the dev server.
import { test, expect } from "@playwright/test";

const SW_BASE = "http://127.0.0.1:3002";

test("service worker caches App.wasm on second visit", async ({ page }) => {
  // ── First visit: SW registers, install event fires, WASM fetched from network
  await page.goto(`${SW_BASE}/`);

  // Wait for the SW to activate and claim the page. After claim() the
  // controller is set immediately; poll until it's non-null.
  await page.waitForFunction(
    () => navigator.serviceWorker.controller !== null,
    null,
    { timeout: 30_000 }
  );

  // Sanity: the Counter app must be interactive (confirms WASM init succeeded).
  const incrementBtn = page.getByRole("button", { name: "Increment" });
  await expect(incrementBtn).toBeVisible({ timeout: 30_000 });

  // ── Second visit: attach response listener BEFORE reload so we capture all
  //    responses, then reload the page.
  const sources: string[] = [];
  page.on("response", (res) => {
    if (res.url().includes("App.wasm")) {
      sources.push(res.fromServiceWorker() ? "from-sw" : "from-network");
    }
  });

  await page.reload();

  // After reload the SW controller is the same registration; it should still
  // be non-null immediately (controller persists across same-origin navigations
  // once the SW has claimed the client).
  await page.waitForFunction(
    () => navigator.serviceWorker.controller !== null,
    null,
    { timeout: 30_000 }
  );
  await expect(incrementBtn).toBeVisible({ timeout: 30_000 });

  // The second load must include at least one App.wasm response served from
  // the service worker cache — the whole point of Track 1.
  expect(sources, "expected App.wasm to be served from the service worker on reload").toContain("from-sw");
});
