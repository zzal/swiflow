// Tests/playwright/devtools-api.spec.ts
//
// Contract test for the window.__swiflow API surface that Phase 19's
// devtools panel depends on. Runs against the Counter dev server on
// port 3000 (configured in playwright.config.ts). If any of these
// assertions break, the panel parser must be updated in lock-step.

import { test, expect } from "@playwright/test";

test.describe("__swiflow API contract (devtools panel dependency)", () => {
  test.use({ baseURL: "http://127.0.0.1:3000" });

  test("window.__swiflow exists with tree, state, perf, handlers functions in dev mode", async ({ page }) => {
    await page.goto("/");
    // Wait for the app to mount (Counter heading is the established readiness signal).
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const apiShape = await page.evaluate(() => ({
      hasNamespace: typeof (window as any).__swiflow === "object",
      hasTree: typeof (window as any).__swiflow?.tree === "function",
      hasState: typeof (window as any).__swiflow?.state === "function",
      hasPerf: typeof (window as any).__swiflow?.perf === "function",
      hasHandlers: typeof (window as any).__swiflow?.handlers === "function",
    }));

    expect(apiShape).toEqual({
      hasNamespace: true,
      hasTree: true,
      hasState: true,
      hasPerf: true,
      hasHandlers: true,
    });
  });

  test("tree() returns object keyed by selector with indented string values", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const tree = await page.evaluate(() => (window as any).__swiflow.tree());

    expect(typeof tree).toBe("object");
    const selectors = Object.keys(tree);
    expect(selectors.length).toBeGreaterThan(0);

    for (const sel of selectors) {
      expect(typeof tree[sel]).toBe("string");
      expect(tree[sel].length).toBeGreaterThan(0);
      // Spot-check the canonical line shape: TypeName "path" maybe-followed-by " [body→]".
      const firstLine = tree[sel].split("\n")[0];
      expect(firstLine).toMatch(/^\S+ "[^"]*"( \[body→\])?$/);
    }
  });

  test("perf() returns object keyed by selector with renders / lastPatchCount / lastRenderMs numbers", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const perf = await page.evaluate(() => (window as any).__swiflow.perf());

    expect(typeof perf).toBe("object");
    for (const sel of Object.keys(perf)) {
      expect(typeof perf[sel].renders).toBe("number");
      expect(typeof perf[sel].lastPatchCount).toBe("number");
      expect(typeof perf[sel].lastRenderMs).toBe("number");
    }
  });

  test("state(path) returns @State object for the root component path; null for unknown path", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    // The Counter demo's root component holds the count @State. Path "" hits the root.
    const rootState = await page.evaluate(() => (window as any).__swiflow.state(""));
    expect(rootState).not.toBeNull();
    expect(typeof rootState).toBe("object");
    // Counter's @State field is named `count`. If the example renames it,
    // bump the expected name — the SHAPE (object keyed by field name with
    // primitive value) is what matters.
    expect(rootState).toHaveProperty("count");
    expect(typeof rootState.count).toBe("number");

    const unknownState = await page.evaluate(() => (window as any).__swiflow.state("999.999.999"));
    expect(unknownState).toBeNull();
  });
});
