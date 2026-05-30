// Tests/playwright/edgecases.spec.ts
import { test, expect, type Page, type Locator } from "@playwright/test";

// Seed a sentinel input: type a value AND tag its live DOM node, so we can
// later prove the SAME node survived a sibling mutation.
//
// NOTE on detection: focus is deliberately NOT used as an identity signal.
// Every trap mutates structure via a button click, and clicking a button moves
// focus to that button regardless of whether the sentinel node was recreated.
// The reliable signals that a node was *reused* (not recreated) are: the typed
// value persists (an uncontrolled input loses it on recreation) and a custom
// DOM property we stamp on the node object persists (a fresh node won't have it).
async function seedSentinel(page: Page, testid: string, value: string, tag: string): Promise<Locator> {
  const input = page.getByTestId(testid);
  await input.fill(value);
  await input.evaluate((el, t) => { (el as unknown as Record<string, unknown>).__tag = t; }, tag);
  return input;
}

async function expectSurvived(input: Locator, value: string, tag: string) {
  await expect(input).toHaveValue(value);
  expect(await input.evaluate((el) => (el as unknown as Record<string, unknown>).__tag)).toBe(tag);
}

test.describe("EdgeCases reconciliation traps", () => {
  test("trap1: conditional before sentinel — node identity + value survive toggle", async ({ page }) => {
    await page.goto("/");
    const input = await seedSentinel(page, "trap1-input", "hello", "t1");
    // Toggle the conditional that sits BEFORE the input, twice.
    await page.getByTestId("trap1-toggle").click();
    await page.getByTestId("trap1-toggle").click();
    // Same node (tag persists) holding its value ⇒ not recreated.
    await expectSurvived(input, "hello", "t1");
  });

  test("trap2: for-of-if — toggling one item's flag preserves sibling inputs", async ({ page }) => {
    await page.goto("/");
    const sib = await seedSentinel(page, "trap2-input-2", "keep-me", "t2");
    await page.getByTestId("trap2-toggle-0").click();
    await page.getByTestId("trap2-toggle-0").click();
    await expectSurvived(sib, "keep-me", "t2");
  });

  test("trap3: for-of-if-of-for — inner mutation leaves other outer items intact", async ({ page }) => {
    await page.goto("/");
    const other = await seedSentinel(page, "trap3-input-1", "outer1", "t3");
    await page.getByTestId("trap3-add-0").click();
    await page.getByTestId("trap3-add-0").click();
    await expectSurvived(other, "outer1", "t3");
  });

  test("trap4: loop-in-conditional — details open-state survives toggling the loop", async ({ page }) => {
    await page.goto("/");
    const details = page.getByTestId("trap4-details");
    await details.locator("summary").click();                // open it
    await expect(details).toHaveAttribute("open", "");
    await page.getByTestId("trap4-toggle").click();           // hide loop
    await page.getByTestId("trap4-toggle").click();           // show loop again
    await expect(details).toHaveAttribute("open", "");        // still open ⇒ not recreated
  });

  test("trap5: keyed reorder with fragments — keyed input reused on swap", async ({ page }) => {
    await page.goto("/");
    await seedSentinel(page, "trap5-input-a", "valueA", "t5");
    await page.getByTestId("trap5-togglex").click();   // toggle interspersed fragment
    await page.getByTestId("trap5-swap").click();       // reorder keyed inputs
    // The keyed input "a" moved position but kept identity + value.
    await expectSurvived(page.getByTestId("trap5-input-a"), "valueA", "t5");
  });

  test("trap6: two adjacent conditionals — sentinel survives all 4 combos", async ({ page }) => {
    await page.goto("/");
    await seedSentinel(page, "trap6-input", "combo", "t6");
    for (const id of ["trap6-a", "trap6-b", "trap6-a", "trap6-b"]) {
      await page.getByTestId(id).click();
      await expectSurvived(page.getByTestId("trap6-input"), "combo", "t6");
    }
  });

  test("trap7: component lifecycle — onAppear/onDisappear once each; sibling @State survives", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("trap7-keeper-inc").click();
    await page.getByTestId("trap7-keeper-inc").click();
    await expect(page.getByTestId("trap7-keeper-count")).toHaveText("2");
    await page.getByTestId("trap7-toggle").click();  // show child → up 1
    await page.getByTestId("trap7-toggle").click();  // hide child → down 1
    await expect(page.getByTestId("trap7-appears")).toHaveText("up:1");
    await expect(page.getByTestId("trap7-disappears")).toHaveText("down:1");
    await expect(page.getByTestId("trap7-keeper-count")).toHaveText("2"); // sibling @State survived
  });

  test("trap8: rapid cycle — sentinel intact, no leaked children", async ({ page }) => {
    await page.goto("/");
    const input = await seedSentinel(page, "trap8-input", "stable", "t8");
    for (let i = 0; i < 7; i++) await page.getByTestId("trap8-toggle").click(); // odd ⇒ ends shown
    await expect(page.getByTestId("trap8-list").locator("li")).toHaveCount(3);   // exactly 3, no dups
    await expectSurvived(input, "stable", "t8");
  });

  test("trap9: keyed items carry inner state across reorder", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("trap9-expand-y").click();          // expand item y
    await seedSentinel(page, "trap9-input-y", "Y-data", "t9");
    await page.getByTestId("trap9-rotate").click();            // x,y,z → y,z,x
    // y's input still exists with value + identity (state moved with the item).
    await expectSurvived(page.getByTestId("trap9-input-y"), "Y-data", "t9");
  });

  test("trap10: raw spread — separate-element sentinel unaffected; no crash", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto("/");
    const input = await seedSentinel(page, "trap10-input", "safe", "t10");
    await page.getByTestId("trap10-grow").click();
    await page.getByTestId("trap10-grow").click();
    // The documented limitation shifts the in-element END marker, but the
    // sentinel input lives in a SEPARATE element and must be unaffected.
    await expectSurvived(input, "safe", "t10");
    await expect(page.getByTestId("trap10-spread")).toContainText("END");
    expect(errors, "no console errors from the raw spread").toHaveLength(0);
  });

  test("trap11: bulk add/remove/swap — existing rows reused (identity + value survive)", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("trap11-add1-back").click();   // seed 1 row
    const firstTestid = await page.getByTestId("trap11-list").locator("li input").first().getAttribute("data-testid");
    const typed = await seedSentinel(page, firstTestid!, "ANCHOR", "t11");
    await page.getByTestId("trap11-add100-front").click(); // prepend 100 (the stressor)
    await expect(page.getByTestId("trap11-count")).toHaveText("101");
    // The original row was NOT recreated: same node (tag persists) + value.
    await expectSurvived(typed, "ANCHOR", "t11");
    await page.getByTestId("trap11-swap").click();          // swap ends
    await expectSurvived(page.getByTestId(firstTestid!), "ANCHOR", "t11");
  });
});
