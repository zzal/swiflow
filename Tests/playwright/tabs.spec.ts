import { test, expect } from "@playwright/test";

// The SwiflowUIDemo Tabs story: a single tablist bound to one Binding<String> selection —
// three tabs, Overview/Details/Settings (initial selection "overview") — each a
// `button[role=tab]` in a `[role=tablist]`, each panel a `[role=tabpanel]` (render-all:
// every panel's content is always in the DOM, inactive ones just carry the `hidden`
// attribute) — see TabsStory.swift / Tabs.swift. Keyboard is roving-tabindex, automatic
// activation: ArrowLeft/Right (wrapping) and Home/End move focus AND selection together,
// so the selected tab is always the sole `tabindex="0"` member of the tablist.
test.describe("Tabs roving tablist", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/component/tabs");
  });

  test("the first tab is selected by default; its panel is visible, the others hidden", async ({ page }) => {
    const overview = page.getByRole("tab", { name: "Overview" });
    const details = page.getByRole("tab", { name: "Details" });
    const settings = page.getByRole("tab", { name: "Settings" });

    await expect(overview).toHaveAttribute("aria-selected", "true");
    await expect(details).toHaveAttribute("aria-selected", "false");
    await expect(settings).toHaveAttribute("aria-selected", "false");

    // getByRole("tabpanel") excludes elements hidden from the accessibility tree by
    // default (inactive panels carry `hidden`), so it resolves to exactly the one
    // selected panel: assert its text AND that it is the *only* visible panel.
    // (A bare getByText would also match the story's collapsed code-snippet copy of
    // these same strings, so panel assertions must stay scoped to role=tabpanel.)
    await expect(page.getByRole("tabpanel")).toHaveText("A quick summary of the project.");
    await expect(page.getByRole("tabpanel")).toHaveCount(1);
  });

  test("clicking the second tab selects it: aria-selected flips, its panel shows, the first hides", async ({ page }) => {
    await page.getByRole("tab", { name: "Details" }).click();

    await expect(page.getByRole("tab", { name: "Overview" })).toHaveAttribute("aria-selected", "false");
    await expect(page.getByRole("tab", { name: "Details" })).toHaveAttribute("aria-selected", "true");

    await expect(page.getByRole("tabpanel")).toHaveText("Everything the overview left out.");
    await expect(page.getByRole("tabpanel")).toHaveCount(1);
  });

  test("focusing the selected tab and pressing ArrowRight moves selection AND focus to the next tab", async ({ page }) => {
    const overview = page.getByRole("tab", { name: "Overview" });
    const details = page.getByRole("tab", { name: "Details" });

    await overview.click(); // already selected; a click also focuses the button (Chromium)
    await expect(overview).toBeFocused();

    await page.keyboard.press("ArrowRight");

    await expect(details).toHaveAttribute("aria-selected", "true");
    await expect(details).toBeFocused();
    await expect(overview).toHaveAttribute("aria-selected", "false");
  });

  test("ArrowRight from the last tab wraps around to the first", async ({ page }) => {
    const overview = page.getByRole("tab", { name: "Overview" });
    const settings = page.getByRole("tab", { name: "Settings" });

    await settings.click();
    await expect(settings).toHaveAttribute("aria-selected", "true");
    await expect(settings).toBeFocused();

    await page.keyboard.press("ArrowRight");

    await expect(overview).toHaveAttribute("aria-selected", "true");
    await expect(overview).toBeFocused();
    await expect(settings).toHaveAttribute("aria-selected", "false");
  });

  test("Home/End jump to the first/last tab, moving focus with them", async ({ page }) => {
    const overview = page.getByRole("tab", { name: "Overview" });
    const details = page.getByRole("tab", { name: "Details" });
    const settings = page.getByRole("tab", { name: "Settings" });

    await details.click(); // start in the middle
    await expect(details).toBeFocused();

    await page.keyboard.press("End");
    await expect(settings).toHaveAttribute("aria-selected", "true");
    await expect(settings).toBeFocused();

    await page.keyboard.press("Home");
    await expect(overview).toHaveAttribute("aria-selected", "true");
    await expect(overview).toBeFocused();
  });

  test("roving tabindex: only the selected tab is tabbable, the rest are -1", async ({ page }) => {
    const overview = page.getByRole("tab", { name: "Overview" });
    const details = page.getByRole("tab", { name: "Details" });
    const settings = page.getByRole("tab", { name: "Settings" });

    await expect(overview).toHaveAttribute("tabindex", "0");
    await expect(details).toHaveAttribute("tabindex", "-1");
    await expect(settings).toHaveAttribute("tabindex", "-1");

    await details.click();

    await expect(overview).toHaveAttribute("tabindex", "-1");
    await expect(details).toHaveAttribute("tabindex", "0");
    await expect(settings).toHaveAttribute("tabindex", "-1");
  });
});
