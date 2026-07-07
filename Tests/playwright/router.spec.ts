// Tests/playwright/router.spec.ts
import { test, expect, type ConsoleMessage } from "@playwright/test";

test.describe("MiniRouter — hash-mode navigation", () => {
  test.use({ baseURL: "http://127.0.0.1:3001" });

  test("Home page renders on load", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => { if (msg.type() === "error") errors.push(msg); });

    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();
    expect(errors.map((e) => e.text()), "no console errors on load").toHaveLength(0);
  });

  test("Link navigation changes URL hash and renders About page", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();

    // The NavBar renders Link("/about", "About"); MiniRouter has no explicit
    // "Go to About" link.
    await page.getByRole("link", { name: "About" }).click();

    // URL hash must change to /about
    await expect(page).toHaveURL(/#\/about$/);
    // About heading must appear
    await expect(page.getByRole("heading", { name: "About" })).toBeVisible();
    // Home heading must be gone
    await expect(page.getByRole("heading", { name: "Home" })).toHaveCount(0);
  });

  test("the current page's Link carries aria-current=page; others don't", async ({ page }) => {
    await page.goto("/");
    // Home is exact-matched and current on load.
    await expect(page.getByRole("link", { name: "Home" })).toHaveAttribute("aria-current", "page");
    await expect(page.getByRole("link", { name: "About" })).not.toHaveAttribute("aria-current", "page");

    await page.getByRole("link", { name: "About" }).click();
    await expect(page).toHaveURL(/#\/about$/);

    // The marker follows the navigation.
    await expect(page.getByRole("link", { name: "About" })).toHaveAttribute("aria-current", "page");
    await expect(page.getByRole("link", { name: "Home" })).not.toHaveAttribute("aria-current", "page");

    // User 42 is prefix-matched: active on the /users/42 child route.
    await page.getByRole("link", { name: "User 42" }).click();
    await expect(page).toHaveURL(/#\/users\/42$/);
    await expect(page.getByRole("link", { name: "User 42" })).toHaveAttribute("aria-current", "page");
  });

  test("Back button returns to Home page and restores URL", async ({ page }) => {
    // Navigate via Link rather than `page.goto("/#/about")` directly so the
    // browser history contains a real prior entry — without it,
    // `window.history.back()` lands on `about:blank` (Playwright's initial
    // page) instead of bouncing within the app.
    await page.goto("/");
    await page.getByRole("link", { name: "About" }).click();
    await expect(page).toHaveURL(/#\/about$/);
    await expect(page.getByRole("heading", { name: "About" })).toBeVisible();

    await page.getByRole("button", { name: "Back" }).click();

    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();
    // URL hash must no longer point at /about
    const url = page.url();
    expect(url).not.toMatch(/#\/about/);
  });
});
