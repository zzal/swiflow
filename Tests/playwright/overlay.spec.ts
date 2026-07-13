import { test, expect } from "@playwright/test";

// The SwiflowUIDemo Modal story: trigger "Settings…" opens a native
// <dialog class="sw-dialog sw-modal sw-modal--lg"> (an h2 title "Settings", a
// Toggle, and a "Close" button) via showModal()/close() — see ModalDialogHost.swift.
// dismissOnBackdrop defaults to true for a generic Modal (unlike Alert/Prompt).
test.describe("Modal", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/component/modal");
  });

  test("opens via its trigger", async ({ page }) => {
    const dialog = page.locator("dialog.sw-modal");
    await expect(dialog).toBeHidden();

    await page.getByRole("button", { name: "Settings…" }).click();

    await expect(dialog).toBeVisible();
    await expect(dialog).toHaveAttribute("open", "");
    await expect(dialog.getByRole("heading", { name: "Settings", exact: true })).toBeVisible();
  });

  test("Escape closes it, and the binding round-trips (reopens cleanly)", async ({ page }) => {
    const dialog = page.locator("dialog.sw-modal");
    await page.getByRole("button", { name: "Settings…" }).click();
    await expect(dialog).toBeVisible();

    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();

    // Proves the native `close` event synced `isPresented` back to false — if it
    // hadn't, this second trigger click would set an already-true binding and
    // silently no-op (syncOpenState sees want == isOpen, never calls showModal()
    // again, so the dialog would stay visually closed).
    await page.getByRole("button", { name: "Settings…" }).click();
    await expect(dialog).toBeVisible();
  });

  test("backdrop click closes it (dismissOnBackdrop defaults to true)", async ({ page }) => {
    const dialog = page.locator("dialog.sw-modal");
    await page.getByRole("button", { name: "Settings…" }).click();
    await expect(dialog).toBeVisible();

    // The dialog itself carries zero padding/border (see DialogChrome.swift) so its
    // box coincides exactly with .sw-dialog__body's — a click anywhere on the
    // visible card always targets the body (a child), never the dialog. A true
    // backdrop click has to land on the native ::backdrop, which the browser
    // dispatches as a `click` whose target IS the <dialog> (isSelfTarget). A corner
    // of the viewport is reliably outside the centered card.
    await page.mouse.click(5, 5);
    await expect(dialog).toBeHidden();
  });

  test("a click inside the body does NOT close it", async ({ page }) => {
    const dialog = page.locator("dialog.sw-modal");
    await page.getByRole("button", { name: "Settings…" }).click();
    await expect(dialog).toBeVisible();

    // Click on the body's own padding (not on a child control) — the event
    // target is .sw-dialog__body, a descendant of the dialog, so isSelfTarget
    // is false and the backdrop-dismiss handler doesn't fire.
    await dialog.locator(".sw-dialog__body").click({ position: { x: 5, y: 5 } });
    await expect(dialog).toBeVisible();
  });
});

// The SwiflowUIDemo Popover story: four triggers ("Top"/"Bottom"/"Leading"/"Trailing"),
// each opening its own `.sw-popover[popover="auto"]` panel anchored to that trigger.
// ESC + outside-click light-dismiss are entirely native (Popover API) — see Popover.swift.
test.describe("Popover", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/#/component/popover");
  });

  test("opens via its trigger", async ({ page }) => {
    const panel = page.locator(".sw-popover", { hasText: "anchored above the trigger" });
    await expect(panel).toBeHidden();

    await page.getByRole("button", { name: "Top" }).click();

    await expect(panel).toBeVisible();
  });

  test("Escape closes it", async ({ page }) => {
    const panel = page.locator(".sw-popover", { hasText: "anchored above the trigger" });
    await page.getByRole("button", { name: "Top" }).click();
    await expect(panel).toBeVisible();

    await page.keyboard.press("Escape");
    await expect(panel).toBeHidden();
  });

  test("clicking outside light-dismisses it", async ({ page }) => {
    const panel = page.locator(".sw-popover", { hasText: "anchored above the trigger" });
    await page.getByRole("button", { name: "Top" }).click();
    await expect(panel).toBeVisible();

    await page.mouse.click(5, 5);
    await expect(panel).toBeHidden();
  });

  test("content is interactive while open", async ({ page }) => {
    const panel = page.locator(".sw-popover", { hasText: "anchored above the trigger" });
    await page.getByRole("button", { name: "Top" }).click();
    await expect(panel).toBeVisible();

    // The panel's content includes a live Link — clicking it should navigate,
    // proving the panel content isn't behind an inert/pointer-events barrier.
    await panel.getByRole("link", { name: "See Modal too" }).click();
    await expect(page).toHaveURL(/#\/component\/modal$/);
  });
});
