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
