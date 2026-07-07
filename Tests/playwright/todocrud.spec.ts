import { test, expect } from "@playwright/test";

// Real-backend e2e: examples/TodoCRUD's WASM app against its actual Bun + SQLite
// API (seeded with 3 todos, the first done). Exercises the SwiflowQuery
// read / optimistic-write / reconcile / rollback path over real HTTP + CORS +
// JSValueDecoder. Opt-in: `npm run test:todocrud` (needs Bun) or the
// `run-e2e-backend` CI label. The backend is in-memory and re-seeded per process,
// so tests assume the seeded baseline at first load (run order is serial).
test.describe("TodoCRUD (real backend)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await expect(page.getByText("Read the SwiflowQuery guide")).toBeVisible();
  });

  test("reads the seeded list", async ({ page }) => {
    await expect(page.getByText("Wire a real CRUD API")).toBeVisible();
    await expect(page.getByText("Watch optimistic updates reconcile")).toBeVisible();
  });

  test("optimistic add appears instantly and reconciles to the server row", async ({ page }) => {
    const title = `Buy milk ${Date.now()}`;
    await page.getByPlaceholder("What needs doing?").fill(title);
    await page.getByRole("button", { name: "Add" }).click();
    // Optimistic: the row is visible immediately (before the POST + refetch settle).
    await expect(page.getByText(title)).toBeVisible();
    // Stays after the post-mutation GET /todos reconciles to the server row.
    await expect(page.getByText(title)).toBeVisible();
    // Survives a reload — it really persisted server-side for the process life.
    await page.reload();
    await expect(page.getByText(title)).toBeVisible();
  });

  test("toggle persists across reload", async ({ page }) => {
    await page.getByRole("checkbox", { name: "Wire a real CRUD API" }).check();
    await expect(page.getByRole("checkbox", { name: "Wire a real CRUD API" })).toBeChecked();
    await page.reload();
    await expect(page.getByRole("checkbox", { name: "Wire a real CRUD API" })).toBeChecked();
  });

  test("delete removes the row", async ({ page }) => {
    await page.getByRole("button", { name: "Delete Watch optimistic updates reconcile" }).click();
    await expect(page.getByText("Watch optimistic updates reconcile")).toHaveCount(0);
  });

  test("cancelling a superseded fetch aborts it at the network layer", async ({ page }) => {
    // The list polls every 5s. Stall the NEXT poll GET so it stays in flight,
    // then fire an optimistic add: setQueryData supersedes ["todos"], which
    // cancels the in-flight fetch task — FetchTransport's AbortController must
    // surface that as a real network-level abort, not a request that silently
    // downloads to completion after its result was already superseded.
    let stalledOne = false;
    await page.route("**/todos", async (route) => {
      if (!stalledOne && route.request().method() === "GET") {
        stalledOne = true;   // hold exactly one GET (the poll); never continue it
        return;
      }
      await route.continue();
    });

    const polled = await page.waitForRequest(
      (r) => r.url().endsWith("/todos") && r.method() === "GET",
      { timeout: 10_000 });   // poll cadence is 5s

    const aborted = page.waitForEvent("requestfailed", {
      predicate: (r) => r === polled,
      timeout: 5_000,
    });

    const title = `Abort poll ${Date.now()}`;
    await page.getByPlaceholder("What needs doing?").fill(title);
    await page.getByRole("button", { name: "Add" }).click();

    const failure = (await aborted).failure();
    expect(failure?.errorText).toContain("ABORTED");

    // The add itself is unaffected: the optimistic row shows and reconciles
    // (its POST and the follow-up repair GET pass through the route).
    await expect(page.getByText(title)).toBeVisible();
    await page.unroute("**/todos");
  });

  test("a forced network failure rolls the optimistic add back", async ({ page }) => {
    // Abort the POST so perform() fails → the optimistic row must roll back and
    // the error message must show. No backend change needed.
    await page.route("**/todos", (route) =>
      route.request().method() === "POST" ? route.abort() : route.continue());

    const title = `Will fail ${Date.now()}`;
    await page.getByPlaceholder("What needs doing?").fill(title);
    await page.getByRole("button", { name: "Add" }).click();

    await expect(page.getByText(title)).toBeVisible();   // optimistic insert
    await expect(page.getByText(title)).toHaveCount(0);  // rolled back after the abort
    await expect(page.getByText("Add failed.")).toBeVisible();

    await page.unroute("**/todos");
  });
});
