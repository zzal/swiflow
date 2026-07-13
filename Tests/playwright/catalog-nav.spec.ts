import { test, expect } from "@playwright/test";

// Regression guard for the catalog's left sidebar navigation.
//
// The nav sits OUTSIDE the RouterRoot (the story outlet is its sibling), so the
// links are plain `#`-hash anchors, NOT `SwiflowRouter.Link`: a Router Link there
// would capture the no-op default router, and its click handler would
// `preventDefault()` the native hash navigation and then do nothing — dead links
// (the v0.4.16 catalog bug). Every other spec `goto`s the routes directly, so the
// link-CLICK path was never exercised; these tests click the links.
test.describe("Catalog sidebar navigation", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/");
  });

  test("clicking a sidebar link navigates the outlet and marks the link active", async ({ page }) => {
    const nav = page.locator(".catalog-nav");
    await nav.getByRole("link", { name: "Stacks" }).click();

    await expect(page).toHaveURL(/#\/component\/stacks$/);
    await expect(
      page.locator(".story-outlet").getByRole("heading", { level: 1, name: "Stacks" }),
    ).toBeVisible();
    await expect(nav.getByRole("link", { name: "Stacks" })).toHaveAttribute("aria-current", "page");
  });

  test("navigating between links moves the active marker", async ({ page }) => {
    const nav = page.locator(".catalog-nav");
    await nav.getByRole("link", { name: "Stacks" }).click();
    await nav.getByRole("link", { name: "Tabs" }).click();

    await expect(page).toHaveURL(/#\/component\/tabs$/);
    await expect(nav.getByRole("link", { name: "Tabs" })).toHaveAttribute("aria-current", "page");
    await expect(nav.getByRole("link", { name: "Stacks" })).not.toHaveAttribute("aria-current", "page");
  });

  test("Overview returns to the index route", async ({ page }) => {
    const nav = page.locator(".catalog-nav");
    await nav.getByRole("link", { name: "Tabs" }).click();
    await expect(page).toHaveURL(/#\/component\/tabs$/);

    await nav.getByRole("link", { name: "Overview" }).click();
    await expect(page).toHaveURL(/#\/$/);
    await expect(nav.getByRole("link", { name: "Overview" })).toHaveAttribute("aria-current", "page");
  });
});
