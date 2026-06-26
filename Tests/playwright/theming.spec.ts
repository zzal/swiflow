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
    // Chromium serializes a 0s transition-duration as "1e-05s" under reduced-motion, so
    // assert effectively-zero rather than the literal "0s".
    expect(btnDur.split(",").every((d) => parseFloat(d) <= 0.001)).toBe(true);
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

  test("--sw-warning / --sw-info status tokens resolve in the browser (info aliases the accent)", async ({ page }) => {
    // The base sheet is injected at runtime by any SwiflowUI app (the counter demo's Button
    // pulls it in — sibling tests read --sw-accent the same way). Probe the new tokens by
    // resolving them on a throwaway element rather than via a Badge (this demo has no badges).
    await gotoMounted(page);
    const t = await page.evaluate(() => {
      const resolve = (name: string) => {
        const el = document.createElement("span");
        el.style.color = `var(${name})`;
        document.body.appendChild(el);
        const c = getComputedStyle(el).color;
        el.remove();
        return c;
      };
      return {
        warning: resolve("--sw-warning"),
        success: resolve("--sw-success"),
        info: resolve("--sw-info"),
        accent: resolve("--sw-accent"),
      };
    });
    // warning is a real amber color present in the base sheet, distinct from success (green)
    expect(t.warning).toMatch(/^rgb/);
    expect(t.warning).not.toBe(t.success);
    // info aliases the accent by default (--sw-info: var(--sw-accent))
    expect(t.info).toBe(t.accent);
  });

  test("registered scalar tokens reject invalid values (proves @property is live)", async ({ page }) => {
    // A registered <length> property rejects an invalid value at computed-value time,
    // so the element keeps the inherited :root value (1px). An UNregistered custom
    // property would instead echo the raw "banana" string. Reading getComputedStyle
    // (not .style) is what surfaces the registration.
    await gotoMounted(page);
    const resolved = await page.evaluate(() => {
      const el = document.createElement("span");
      document.body.appendChild(el);
      el.style.setProperty("--sw-border-width", "banana");
      const v = getComputedStyle(el).getPropertyValue("--sw-border-width").trim();
      el.remove();
      return v;
    });
    expect(resolved).toBe("1px"); // invalid value rejected → inherited, not "banana"
  });

  test("registered color tokens are active and harmless (Unit B gate)", async ({ page }) => {
    // A registered <color> resolves normally AND rejects an invalid override (the element
    // inherits the :root value rather than echoing garbage) — proving registration is live
    // without changing any rendered color. An unregistered prop would echo "not-a-color".
    await gotoMounted(page);
    const r = await page.evaluate(() => {
      const accent = getComputedStyle(document.documentElement).getPropertyValue("--sw-accent").trim();
      const el = document.createElement("span");
      document.body.appendChild(el);
      el.style.setProperty("--sw-accent", "not-a-color");
      const overridden = getComputedStyle(el).getPropertyValue("--sw-accent").trim();
      el.remove();
      return { accent, overridden };
    });
    expect(r.accent).not.toBe("");        // base sheet resolves to a real color
    expect(r.overridden).toBe(r.accent);  // invalid override rejected → inherited, not "not-a-color"
  });
});
