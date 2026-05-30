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
});
