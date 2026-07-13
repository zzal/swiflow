import { test, expect } from "@playwright/test";

// SwiflowUIDemo DataTable: columns Name, Age (right-aligned, sortable), Role (Badge),
// Edit (button). Rendered with sortable + selection + pageSize 5 over 14 rows.
// Cell order per row: [1] select checkbox, [2] Name, [3] Age, [4] Role, [5] Edit.
//
// The demo ALSO renders a virtualized table (`.sw-table--virtual`), so the paged-table
// tests scope to `.sw-table:not(.sw-table--virtual)`; the virtualization test below targets
// `.sw-table--virtual`.
const PAGED = ".sw-table:not(.sw-table--virtual)";

test.describe("DataTable", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/component/datatable");
    await expect(page.locator(".sw-table").first()).toBeVisible();
  });

  test("clicking the Age header sorts ascending then descending (aria-sort + ordered values)", async ({ page }) => {
    const table = page.locator(PAGED);
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
    const table = page.locator(PAGED);
    await table.locator("thead input[type=checkbox]").check();
    const rowBoxes = table.locator("tbody input[type=checkbox]");
    const n = await rowBoxes.count();
    expect(n).toBeGreaterThan(0);
    for (let i = 0; i < n; i++) await expect(rowBoxes.nth(i)).toBeChecked();
  });

  test("pager Next advances to a different page of rows", async ({ page }) => {
    const table = page.locator(PAGED);
    const firstName = table.locator("tbody tr td:nth-child(2)").first();
    const before = await firstName.innerText();
    // Scope to the paged table's own pager: the demo page also has a wizard
    // `Button("Next")`, so an unscoped getByRole("button", {name:"Next"}) is
    // ambiguous. `.sw-pagination` (the standalone Pagination component DataTable
    // renders) is a sibling of the <table>, not inside it, so it can't be reached
    // through the PAGED (table) locator.
    await page.locator(".sw-pagination").getByRole("button", { name: "Next" }).click();
    await expect(firstName).not.toHaveText(before);
  });

  test("virtualized table windows rows to the viewport and re-windows on scroll", async ({ page }) => {
    await page.goto("/#/component/datatable-virtual");
    const vtable = page.locator(".sw-table--virtual");
    await expect(vtable).toBeVisible();
    await expect(vtable).toHaveAttribute("aria-rowcount", "2000");

    const rows = vtable.locator("tbody tr");
    const scroll = page.locator(".sw-table__scroll:has(.sw-table--virtual)");

    // After onAppear measures the viewport, only a window (viewport + overscan) of the 2000
    // rows is in the DOM — poll to absorb the initial pre-measure paint.
    await expect.poll(async () => rows.count()).toBeLessThan(60);
    await expect(rows.first()).toContainText("Person 0");

    // Columns must lay out HORIZONTALLY via the inline grid template (regression guard: a broken
    // grid-template-columns collapses cells into one stacked column). Assert the first row's three
    // cells share a row (same y) and march left→right (strictly increasing x).
    const cells = rows.first().locator("td");
    const boxes = await Promise.all(
      (await cells.all()).map((c) => c.boundingBox()),
    );
    expect(boxes.length).toBe(3);
    for (const b of boxes) expect(b).not.toBeNull();
    expect(Math.abs(boxes[1]!.y - boxes[0]!.y)).toBeLessThan(4);   // same line
    expect(Math.abs(boxes[2]!.y - boxes[0]!.y)).toBeLessThan(4);
    expect(boxes[1]!.x).toBeGreaterThan(boxes[0]!.x);              // columns advance rightward
    expect(boxes[2]!.x).toBeGreaterThan(boxes[1]!.x);

    // Scroll down; the window shifts to later rows but stays small.
    await scroll.evaluate((el) => { (el as HTMLElement).scrollTop = 4000; });
    await expect.poll(async () => (await rows.first().innerText())).not.toContain("Person 0");
    expect(await rows.count()).toBeLessThan(60);

    // Header stays pinned (sticky on <thead>, not the header <tr>) while the body scrolls:
    // its top must sit at the scroll container's top, not scroll away.
    const headTop = await vtable.locator("thead").evaluate((el) => el.getBoundingClientRect().top);
    const containerTop = await scroll.evaluate((el) => el.getBoundingClientRect().top);
    expect(Math.abs(headTop - containerTop)).toBeLessThan(3);

    // Single row separator (no double line): the row carries the border, cells don't.
    const tdBorder = await rows.first().locator("td").first()
      .evaluate((el) => getComputedStyle(el).borderBottomWidth);
    expect(tdBorder).toBe("0px");
  });
});
