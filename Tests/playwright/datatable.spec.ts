import { test, expect } from "@playwright/test";

// SwiflowUIDemo DataTable: columns Name, Age (right-aligned, sortable), Role (Badge),
// Edit (button). Rendered with sortable + selection + pageSize 5 over 14 rows.
// Cell order per row: [1] select checkbox, [2] Name, [3] Age, [4] Role, [5] Edit.
test.describe("DataTable", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".sw-table")).toBeVisible();
  });

  test("clicking the Age header sorts ascending then descending (aria-sort + ordered values)", async ({ page }) => {
    const table = page.locator(".sw-table");
    const ageHeader = table.getByRole("button", { name: /^Age/ });
    await ageHeader.click();

    const th = table.locator("th[aria-sort]").filter({ hasText: "Age" });
    await expect(th).toHaveAttribute("aria-sort", "ascending");

    // Age is the 3rd cell; assert the visible column is non-decreasing.
    const asc = (await table.locator("tbody tr td:nth-child(3)").allInnerTexts()).map((t) => parseInt(t, 10));
    expect(asc).toEqual([...asc].sort((a, b) => a - b));

    await ageHeader.click();
    await expect(th).toHaveAttribute("aria-sort", "descending");
    const desc = (await table.locator("tbody tr td:nth-child(3)").allInnerTexts()).map((t) => parseInt(t, 10));
    expect(desc).toEqual([...desc].sort((a, b) => b - a));
  });

  test("header select-all checks every visible row checkbox", async ({ page }) => {
    const table = page.locator(".sw-table");
    await table.locator("thead input[type=checkbox]").check();
    const rowBoxes = table.locator("tbody input[type=checkbox]");
    const n = await rowBoxes.count();
    expect(n).toBeGreaterThan(0);
    for (let i = 0; i < n; i++) await expect(rowBoxes.nth(i)).toBeChecked();
  });

  test("pager Next advances to a different page of rows", async ({ page }) => {
    const table = page.locator(".sw-table");
    const firstName = table.locator("tbody tr td:nth-child(2)").first();
    const before = await firstName.innerText();
    await page.getByRole("button", { name: "Next" }).click();
    await expect(firstName).not.toHaveText(before);
  });
});
