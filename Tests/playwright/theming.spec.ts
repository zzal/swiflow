// tests/playwright/theming.spec.ts
//
// Runtime proof of the SwiflowUI theming contract: the unit tests
// (ThemeTests.swift) assert the `@media` token layers are *emitted*; these assert
// the browser actually *applies* them on the live HelloWorld page (which now uses
// SwiflowUI components after the dogfood). Set the media emulation BEFORE navigating
// and wait for the WASM app to mount (so the token sheets are injected) before reading.
import { test, expect, type Page } from "@playwright/test";

// The SwiflowUI base/control sheets inject when the app mounts (WASM boots async after
// `goto`), so always wait for a component before reading tokens/styles.
async function gotoMounted(page: Page) {
  await page.goto("/");
  await page.getByRole("button", { name: "Increment" }).waitFor();
}

const durationToken = (page: Page) =>
  page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--sw-duration").trim());
const borderWidthToken = (page: Page) =>
  page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--sw-border-width").trim());

test.describe("SwiflowUI theming responds to media features", () => {
  test("prefers-color-scheme flips the resolved palette (light-dark tokens)", async ({ page }) => {
    // .sw-btn--primary background is var(--sw-accent), a light-dark() token — its
    // *resolved* color must differ between schemes. Load fresh under each scheme so
    // the injected sheets resolve light-dark() from the start.
    const accentBg = () =>
      page.getByRole("button", { name: "Increment" }).evaluate((el) => getComputedStyle(el).backgroundColor);

    await page.emulateMedia({ colorScheme: "light" });
    await gotoMounted(page);
    const light = await accentBg();

    await page.emulateMedia({ colorScheme: "dark" });
    await gotoMounted(page);
    const dark = await accentBg();

    expect(light).not.toBe(dark);
  });

  test("prefers-reduced-motion collapses --sw-duration to 0s (and a component's transitions with it)", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await gotoMounted(page);
    expect(await durationToken(page)).not.toBe("0s");           // motion on by default

    await page.emulateMedia({ reducedMotion: "reduce" });
    await gotoMounted(page);
    expect(await durationToken(page)).toBe("0s");                // @media re-points the token
    // …and a real component that reads it (the .sw-btn transition) collapses too.
    const btnDur = await page.getByRole("button", { name: "Increment" })
      .evaluate((el) => getComputedStyle(el).transitionDuration);
    expect(btnDur.split(",").every((d) => d.trim() === "0s")).toBe(true);
  });

  test("prefers-contrast: more thickens --sw-border-width", async ({ page }) => {
    await page.emulateMedia({ contrast: "no-preference" });
    await gotoMounted(page);
    expect(await borderWidthToken(page)).toBe("1px");

    await page.emulateMedia({ contrast: "more" });
    await gotoMounted(page);
    expect(await borderWidthToken(page)).toBe("2px");
  });

  test("an app :root --sw-accent override (in <head>) wins over the base sheet", async ({ page }) => {
    // Inject a static override into the INITIAL HTML <head> — parsed before the runtime-
    // appended base sheet. It only wins if base tokens are in @layer swiflow.base
    // (unlayered beats layered regardless of source order). rgb() keeps the computed value
    // unambiguous and scheme-independent.
    await page.route("**/*", async (route) => {
      if (route.request().resourceType() !== "document") return route.continue();
      const res = await route.fetch();
      const html = (await res.text()).replace(
        "</head>",
        "<style>:root { --sw-accent: rgb(225, 29, 72) }</style></head>"
      );
      await route.fulfill({ response: res, body: html });
    });
    await gotoMounted(page);
    const bg = await page.getByRole("button", { name: "Increment" })
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(bg).toBe("rgb(225, 29, 72)");
  });
});
