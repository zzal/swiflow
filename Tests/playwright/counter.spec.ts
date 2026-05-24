// tests/playwright/counter.spec.ts
import { test, expect, type ConsoleMessage } from "@playwright/test";

test.describe("Counter demo", () => {
  test("No console errors on page load", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    // Wait for the heading to confirm the app mounted fully.
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    expect(
      errors.map((e) => e.text()),
      "console.error messages on page load"
    ).toHaveLength(0);
  });

  test("Renders, increments via @State, persists between clicks", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

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

    expect(errors.map((e) => e.text()), "console.error during interaction").toHaveLength(0);
  });

  test("Multiple rapid clicks all register (rAF batching does not drop)", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    const button = page.getByRole("button", { name: "Increment" });
    for (let i = 0; i < 5; i++) {
      await button.click();
    }
    await expect(page.getByText("Count: 5")).toBeVisible();

    expect(errors.map((e) => e.text()), "console.error during rapid clicks").toHaveLength(0);
  });
});
