// Tests/playwright/progress.spec.ts
//
// Verifies that documentElement.dataset.swiflowProgress reaches "100" by the
// time the page finishes loading WASM.
//
// This spec runs against a RELEASE build served statically on port 3002
// (set up in playwright.sw.config.ts and playwright.config.ts). The progress
// attribute is written by fetchWithProgress() in the JS driver and is
// meaningless in dev mode without the release WASM stream.
import { test, expect } from "@playwright/test";

const SW_BASE = "http://127.0.0.1:3002";

test.describe("progress attribute during WASM load", () => {
  test("transitions to 100 by the time the page is loaded", async ({ page }) => {
    // Install a MutationObserver BEFORE any page script runs, so we
    // capture every value the attribute takes — including any
    // intermediate percents on a cold load.
    const seen: string[] = [];
    await page.exposeFunction("__recordProgress", (v: string) => {
      seen.push(v);
    });
    await page.addInitScript(() => {
      const html = document.documentElement;
      const obs = new MutationObserver(() => {
        const v = html.dataset.swiflowProgress;
        if (v != null) {
          (window as any).__recordProgress(v);
        }
      });
      obs.observe(html, {
        attributes: true,
        attributeFilter: ["data-swiflow-progress"],
      });
    });

    await page.goto(`${SW_BASE}/`);

    // Poll until the attribute reads "100" (or timeout). On a cold
    // load this passes through intermediate percents; on a SW cache
    // hit the stream completes within a tick.
    await expect
      .poll(
        () =>
          page.evaluate(
            () => document.documentElement.dataset.swiflowProgress
          ),
        { timeout: 60_000, intervals: [100, 200, 500] }
      )
      .toBe("100");

    // At least one value must have been written; the final one is "100".
    expect(seen.length).toBeGreaterThanOrEqual(1);
    expect(seen[seen.length - 1]).toBe("100");
  });
});
