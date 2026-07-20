// Tests/playwright/gridboard.spec.ts
//
// Smoke: the map renders in the SVG namespace, the HUD shows a live
// query time, focus + scrub interactions reach the engine.
import { test, expect } from "@playwright/test";

test.describe("GridBoard smoke", () => {
  test("map renders, HUD live, focus + scrub react", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("svg.gb-map")).toBeVisible({ timeout: 120_000 });
    await expect(page.locator("path.gb-zone")).toHaveCount(13);

    await page.locator('path.gb-zone[data-zone="QC"]').click();
    await expect(page.locator(".gb-panel-title")).toHaveText("Québec");

    await expect(page.locator(".gb-hud")).toContainText("ms");

    const readout = page.locator(".gb-readout");
    const before = await readout.innerText();
    const track = page.locator("svg.gb-track");
    // The scrubber lives below the fold at default viewport height and
    // page.mouse does not auto-scroll — bring it into view first.
    await track.scrollIntoViewIfNeeded();
    const box = await track.boundingBox();
    if (!box) throw new Error("scrubber track not laid out");
    await track.click({ position: { x: box.width * 0.8, y: box.height / 2 } });
    await expect(readout).not.toHaveText(before);
  });
});

test.describe("GridBoard leak soak", () => {
  test("driver listener/node maps stay bounded during playback", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("svg.gb-map")).toBeVisible({ timeout: 120_000 });

    const stats = () =>
      page.evaluate(() => (window as any).swiflow.__stats() as {
        nodes: number; listeners: number; mountedRoots: number;
      });

    // Start playback (the ▶ button), soak at animation-rate rendering,
    // and require the driver's retention maps to stay flat: the memoKey
    // handler leak and the animateExit listener leak both grew exactly
    // these counters, render over render.
    await page.locator("button", { hasText: "▶" }).first().click();
    await page.waitForTimeout(2_000);
    const early = await stats();
    await page.waitForTimeout(6_000);
    const late = await stats();
    await page.locator("button", { hasText: "❚❚" }).first().click();

    // Identical UI, ~360 re-renders later: allow a few transient nodes
    // (toasts/lens), never monotonic growth.
    expect(late.listeners - early.listeners).toBeLessThanOrEqual(5);
    expect(late.nodes - early.nodes).toBeLessThanOrEqual(20);
    expect(late.mountedRoots).toBe(early.mountedRoots);
  });
});
