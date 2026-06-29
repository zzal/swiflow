import { test, expect } from "@playwright/test";

// The SwiflowUIDemo dropdown: trigger "Actions"; items Edit, Duplicate,
// Archive (disabled/inert), [divider], Delete. Enabled roving order: Edit, Duplicate, Delete.
test.describe("Dropdown roving menu", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Actions" }).click();
    await expect(page.getByRole("menu")).toBeVisible();
  });

  test("focus lands on the first item on open", async ({ page }) => {
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
  });

  test("ArrowDown moves to next and wraps; ArrowUp wraps back", async ({ page }) => {
    await page.keyboard.press("ArrowDown");
    await expect(page.getByRole("menuitem", { name: "Duplicate" })).toBeFocused();
    await page.keyboard.press("ArrowDown"); // skips the disabled "Archive"
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
    await page.keyboard.press("ArrowDown"); // wraps to first
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
    await page.keyboard.press("ArrowUp");   // wraps to last
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
  });

  test("Home/End jump to the first/last enabled item", async ({ page }) => {
    await page.keyboard.press("End");
    await expect(page.getByRole("menuitem", { name: "Delete" })).toBeFocused();
    await page.keyboard.press("Home");
    await expect(page.getByRole("menuitem", { name: "Edit" })).toBeFocused();
  });

  test("the disabled item is inert (not a tabbable menuitem)", async ({ page }) => {
    const archive = page.locator('[inert]', { hasText: "Archive" });
    await expect(archive).toHaveCount(1);
  });

  test("Escape closes and returns focus to the trigger", async ({ page }) => {
    await page.keyboard.press("Escape");
    await expect(page.getByRole("menu")).toBeHidden();
    await expect(page.getByRole("button", { name: "Actions" })).toBeFocused();
  });

  test("Enter activates an item and closes the menu", async ({ page }) => {
    await page.keyboard.press("Enter"); // activates focused "Edit"
    await expect(page.getByRole("menu")).toBeHidden();
  });
});
