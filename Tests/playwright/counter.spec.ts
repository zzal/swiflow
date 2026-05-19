// tests/playwright/counter.spec.ts
import { test, expect } from "@playwright/test";

test.describe("Counter demo", () => {
  test("Renders, increments via @State, persists between clicks", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();
    await expect(page.getByText("Count: 0")).toBeVisible();

    const button = page.getByRole("button", { name: "Increment" });
    await button.click();
    await expect(page.getByText("Count: 1")).toBeVisible();

    await button.click();
    await expect(page.getByText("Count: 2")).toBeVisible();

    // Sanity: the old "Count: 0" should no longer exist anywhere.
    await expect(page.getByText("Count: 0")).toHaveCount(0);
  });

  test("Multiple rapid clicks all register (rAF batching does not drop)", async ({ page }) => {
    await page.goto("/");
    const button = page.getByRole("button", { name: "Increment" });
    for (let i = 0; i < 5; i++) {
      await button.click();
    }
    await expect(page.getByText("Count: 5")).toBeVisible();
  });
});
