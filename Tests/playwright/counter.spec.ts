// tests/playwright/counter.spec.ts
import { test, expect, type ConsoleMessage } from "@playwright/test";

test.describe("Counter demo", () => {
  test("No console errors on page load", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    // Wait for the heading to confirm the app mounted fully.
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    expect(
      errors.map((e) => e.text()),
      "console.error messages on page load"
    ).toHaveLength(0);
  });

  test("Renders, increments via @State, persists between clicks", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");

    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();
    await expect(page.getByText("Count: 0")).toBeVisible();

    const button = page.getByRole("button", { name: "Increment" });
    await button.click();
    await expect(page.getByText("Count: 1")).toBeVisible();

    await button.click();
    await expect(page.getByText("Count: 2")).toBeVisible();

    // Sanity: the old "Count: 0" should no longer exist anywhere.
    await expect(page.getByText("Count: 0")).toHaveCount(0);

    expect(errors.map((e) => e.text()), "console.error during interaction").toHaveLength(0);
  });

  test("Multiple rapid clicks all register (rAF batching does not drop)", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    const button = page.getByRole("button", { name: "Increment" });
    for (let i = 0; i < 5; i++) {
      await button.click();
    }
    await expect(page.getByText("Count: 5")).toBeVisible();

    expect(errors.map((e) => e.text()), "console.error during rapid clicks").toHaveLength(0);
  });

  test("Sign in dialog animates open/close via CSS, not a View Transition", async ({ page }) => {
    await page.goto("/");
    // The dialog fades/slides via CSS: `transition-behavior: allow-discrete`
    // on overlay/display keeps it painted through the exit animation, and
    // there is deliberately NO view-transition-name (that approach glitched
    // the top-layer dialog when transitions were interrupted).
    const styles = await page.locator(".signin-dialog").evaluate((el) => {
      const cs = getComputedStyle(el);
      return { transitionBehavior: cs.transitionBehavior, viewTransitionName: cs.viewTransitionName };
    });
    expect(styles.transitionBehavior).toContain("allow-discrete");
    expect(styles.viewTransitionName).toBe("none");
  });

  test("Toast mounts as a popover and auto-dismisses", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Show toast" }).click();
    const toast = page.getByRole("status");
    await expect(toast).toBeVisible();
    await expect(toast).toContainText("Saved!");
    await expect(toast).toHaveAttribute("popover", "manual");
    // Auto-dismiss within ~3s (2.5s timer + exit animation). Give it 4s of slack.
    await expect(toast).toHaveCount(0, { timeout: 4_000 });
  });

  test("Sign in dialog opens via showModal and closes on Escape", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Sign in…" }).click();
    const dialog = page.locator("dialog.signin-dialog");
    // Native <dialog> sets the open attribute when showModal() is called.
    await expect(dialog).toHaveAttribute("open", "");
    await expect(page.getByRole("heading", { name: "Sign In" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog).not.toHaveAttribute("open", "");
  });

  test("Toast auto-dismiss does not close an open dialog", async ({ page }) => {
    await page.goto("/");
    // Regression: the toast is a conditional child. When its 2.5s timer
    // unmounts it, index-based child diffing must not shift/recreate the
    // dialog (a recreated modal <dialog> drops its top-layer state and
    // vanishes). Open the dialog, fire the toast, wait past the auto-dismiss,
    // and assert the dialog is still open.
    await page.getByRole("button", { name: "Show toast" }).click();
    await page.getByRole("button", { name: "Sign in…" }).click();
    const dialog = page.locator("dialog.signin-dialog");
    await expect(dialog).toHaveAttribute("open", "");
    // Wait for the toast to mount and then auto-dismiss (2.5s + exit).
    await expect(page.getByRole("status")).toBeVisible();
    await expect(page.getByRole("status")).toHaveCount(0, { timeout: 4_000 });
    // The dialog must have survived the toast's removal.
    await expect(dialog).toHaveAttribute("open", "");
    await expect(page.getByRole("heading", { name: "Sign In" })).toBeVisible();
  });

  test("About popover opens via popovertarget and closes on Escape", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "About Swiflow" }).click();
    const popover = page.locator("#about-popover");
    await expect(popover).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(popover).toBeHidden();
  });

  test("'What's running here?' details toggles open and closed", async ({ page }) => {
    await page.goto("/");
    const detailsEl = page.locator(".inspector");
    await expect(detailsEl).not.toHaveAttribute("open", "");
    await page.getByText("What's running here?").click();
    await expect(detailsEl).toHaveAttribute("open", "");
    await page.getByText("What's running here?").click();
    await expect(detailsEl).not.toHaveAttribute("open", "");
  });
});
