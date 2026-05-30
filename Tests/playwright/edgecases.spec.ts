// Tests/playwright/edgecases.spec.ts
import { test, expect, type Page } from "@playwright/test";

// Type into a sentinel input and confirm it took focus.
async function focusType(page: Page, testid: string, value: string) {
  const input = page.getByTestId(testid);
  await input.click();
  await input.fill(value);
  return input;
}

test.describe("EdgeCases reconciliation traps", () => {
  test("trap1: conditional before focused input — focus+value survive toggle", async ({ page }) => {
    await page.goto("/");
    const input = await focusType(page, "trap1-input", "hello");
    await page.getByTestId("trap1-toggle").click();
    await page.getByTestId("trap1-toggle").click();
    await expect(input).toBeFocused();
    await expect(input).toHaveValue("hello");
  });
});
