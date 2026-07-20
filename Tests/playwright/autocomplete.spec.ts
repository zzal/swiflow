// Tests/playwright/autocomplete.spec.ts
//
// Autocomplete's behavior is the kit's most imperative surface —
// showPopover()/hidePopover() + scrollIntoView driven from refs, which no
// host-layer test can see (the harness renders the DECLARED tree only).
// Runs under the swiflowui config (SwiflowUIDemo catalog).
import { test, expect } from "@playwright/test";

test.describe("Autocomplete (imperative popover surface)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/component/autocomplete");
    await expect(page.locator(".sw-ac input").first()).toBeVisible({ timeout: 120_000 });
  });

  test("typing opens the listbox popover; Escape closes it", async ({ page }) => {
    const input = page.locator(".sw-ac input").first();
    const listbox = page.locator(".sw-ac [role=listbox]").first();
    await input.click();
    await input.pressSequentially("a");
    await expect(listbox).toBeVisible();
    // The listbox opens through the native Popover API, not display toggling.
    const isPopoverOpen = await listbox.evaluate((el) => el.matches(":popover-open"));
    expect(isPopoverOpen).toBe(true);
    await input.press("Escape");
    await expect(listbox).toBeHidden();
  });

  test("ArrowDown moves the active option and keeps it scrolled into view", async ({ page }) => {
    const input = page.locator(".sw-ac input").first();
    await input.click();
    await input.pressSequentially("a");
    const listbox = page.locator(".sw-ac [role=listbox]").first();
    await expect(listbox).toBeVisible();

    const optionCount = await listbox.locator("[role=option]").count();
    expect(optionCount).toBeGreaterThan(1);
    // Walk past the fold; the active option must stay visible in the
    // listbox's scrollport (the ref-driven scrollIntoView).
    for (let i = 0; i < optionCount; i++) await input.press("ArrowDown");
    const active = listbox.locator('[role=option][aria-selected="true"], [role=option].sw-ac__option--active').first();
    await expect(active).toBeVisible();
    const inView = await active.evaluate((el) => {
      const opt = el.getBoundingClientRect();
      const box = el.closest("[role=listbox]")!.getBoundingClientRect();
      return opt.top >= box.top - 1 && opt.bottom <= box.bottom + 1;
    });
    expect(inView).toBe(true);
  });

  test("selecting an option closes the popover and fills the input", async ({ page }) => {
    const input = page.locator(".sw-ac input").first();
    await input.click();
    await input.pressSequentially("a");
    const listbox = page.locator(".sw-ac [role=listbox]").first();
    await expect(listbox).toBeVisible();
    const first = listbox.locator("[role=option]").first();
    const label = (await first.innerText()).trim();
    await first.click();
    await expect(listbox).toBeHidden();
    await expect(input).toHaveValue(label);
  });
});
