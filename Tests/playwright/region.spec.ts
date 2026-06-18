// Tests/playwright/region.spec.ts
//
// End-to-end proof of Swiflow Regions: the RegionDemo app hosts an external
// AssemblyScript Game-of-Life wasm guest in a Web Worker via OffscreenCanvas,
// and the guest's `generation` events round-trip back into Swift @State.
import { test, expect } from "@playwright/test";

test.describe("Regions — Game of Life guest", () => {
  test.use({ baseURL: "http://127.0.0.1:3004" });

  test("the guest boots, advances, and round-trips events to @State", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(String(e)));

    await page.goto("/");
    await expect(page.getByRole("heading", { name: /Game of Life/ })).toBeVisible();

    // The <sf-region> mounts a canvas the worker drives via OffscreenCanvas.
    await expect(page.locator("sf-region canvas")).toBeVisible();

    // The generation counter climbs only as the guest emits `generation` events
    // (every 64 ticks) — proving guest → worker → host → @State round-trips.
    await expect(
      page.getByText(/Generation: (6[4-9]|[1-9]\d{2,})/),
    ).toBeVisible({ timeout: 15_000 });

    // The guest never hit its error path, and nothing logged to console.error.
    await expect(page.getByText("guest failed to load")).toHaveCount(0);
    expect(errors, `console errors:\n${errors.join("\n")}`).toEqual([]);
  });
});
