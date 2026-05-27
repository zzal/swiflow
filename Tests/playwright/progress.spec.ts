// Tests/playwright/progress.spec.ts
//
// Verifies that documentElement.dataset.swiflowProgress reaches "100" by the
// time the page finishes loading WASM.
//
// This spec runs against a RELEASE build served statically on port 3002
// (set up in playwright.sw.config.ts and playwright.config.ts). The progress
// attribute is written by fetchWithProgress() in the JS driver and is
// meaningless in dev mode without the release WASM stream.
//
// The MutationObserver writes to window.__swiflowProgressLog inside the page
// rather than calling out via page.exposeFunction(). exposeFunction crosses
// the CDP boundary asynchronously; the test can finish (poll resolves to
// "100" within ~900ms) before those async calls land, leaving `seen.length`
// at 0. Keeping the log on window and reading it once via page.evaluate
// avoids the race.
import { test, expect } from "@playwright/test";

const SW_BASE = "http://127.0.0.1:3002";

test.describe("progress attribute during WASM load", () => {
  test("transitions to 100 by the time the page is loaded", async ({ page }) => {
    // Install a MutationObserver BEFORE any page script runs, so we
    // capture every value the attribute takes — including any
    // intermediate percents on a cold load.
    await page.addInitScript(() => {
      // `addInitScript` runs BEFORE any HTML is parsed, so
      // `document.documentElement` is null at this point — attaching the
      // MO here directly throws (silently, inside PW's eval) and leaves
      // the observer un-installed. Stash the log array on `window`
      // (which DOES exist), then arm a one-shot observer on `document`
      // that installs the real MO the moment `<html>` is parsed.
      const w = window as unknown as { __swiflowProgressLog: string[] };
      w.__swiflowProgressLog = [];

      const attachProgressObserver = () => {
        const html = document.documentElement;
        const obs = new MutationObserver(() => {
          const v = html.dataset.swiflowProgress;
          if (v != null) w.__swiflowProgressLog.push(v);
        });
        obs.observe(html, {
          attributes: true,
          attributeFilter: ["data-swiflow-progress"],
        });
      };

      if (document.documentElement) {
        attachProgressObserver();
      } else {
        const waitForHtml = new MutationObserver(() => {
          if (document.documentElement) {
            waitForHtml.disconnect();
            attachProgressObserver();
          }
        });
        waitForHtml.observe(document, { childList: true });
      }
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

    // Read the page-side log AFTER the poll resolves. All MO callbacks
    // that fired during load have already drained into the array by now.
    const seen = await page.evaluate(
      () =>
        (window as unknown as { __swiflowProgressLog: string[] })
          .__swiflowProgressLog
    );

    // At least one value must have been written; the final one is "100".
    expect(seen.length).toBeGreaterThanOrEqual(1);
    expect(seen[seen.length - 1]).toBe("100");
  });
});
