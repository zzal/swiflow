// tests/playwright/counter.spec.ts
import { test, expect, type ConsoleMessage, type Page } from "@playwright/test";

// Wrap window.swiflow.applyPatches so the NEXT batch has its first
// throw-on-bad-handle patch corrupted to reference a handle that was never
// created. The driver's own nodes.get(...) then returns undefined and the real
// DOM op throws — a genuine failure, caught by the driver's per-patch try/catch
// entirely within Swiflow's pipeline (applyPatches returns false, which is what
// makes Swift resync). Self-disarms after one batch so the resync's own patches
// apply normally. This is a test-only wrapper in the page context; production
// ships no failure-injection hook.
//
// `removeHandler` is deliberately EXCLUDED: its applyOne handler looks the
// listener up by a `handle:event` key and no-ops when the (corrupted) key is
// absent — it would NOT throw, so the injection would silently fail to trigger
// any resync (a real bug this suite previously masked). Every other listed op
// unconditionally dereferences nodes.get(handle), guaranteeing the throw.
async function armNextPatchFailure(page: Page): Promise<void> {
  await page.evaluate(() => {
    const HANDLE_FIELD: Record<string, string> = {
      appendChild: "parent", insertBefore: "parent", removeChild: "parent",
      setAttribute: "handle", removeAttribute: "handle",
      setProperty: "handle", removeProperty: "handle",
      setStyle: "handle", removeStyle: "handle", setText: "handle",
      addHandler: "handle",
    };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sw = (window as any).swiflow;
    const orig = sw.applyPatches;
    let armed = true;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    sw.applyPatches = function (patches: any[]) {
      if (armed) {
        const idx = patches.findIndex((p) => p && HANDLE_FIELD[p.op]);
        if (idx !== -1) {
          armed = false;
          const field = HANDLE_FIELD[patches[idx].op];
          const corrupted = patches.slice();
          corrupted[idx] = { ...corrupted[idx], [field]: 999999999 };
          return orig.call(sw, corrupted);
        }
      }
      return orig.call(sw, patches);
    };
  });
}

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

  test("Toast (SwiflowUI ToastStack) appears and auto-dismisses", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Show toast" }).click();
    const toast = page.getByRole("status");
    await expect(toast).toBeVisible();
    await expect(toast).toContainText("Saved!");
    // SwiflowUI's Toast is a role=status live region in a fixed ToastStack (not a
    // popover). Auto-dismiss after the 4s default + exit animation; give 8s slack.
    // (No hover/focus on the toast here, so the countdown isn't paused.)
    await expect(toast).toHaveCount(0, { timeout: 8_000 });
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
    // The toast now lives in a separate ToastStack (sibling of the card), but the
    // invariant still matters: a toast removing itself from its own queue must not
    // disturb the open modal <dialog> (a recreated modal drops its top-layer state
    // and vanishes). Open the dialog, fire the toast, wait past the auto-dismiss,
    // and assert the dialog is still open.
    await page.getByRole("button", { name: "Show toast" }).click();
    await page.getByRole("button", { name: "Sign in…" }).click();
    const dialog = page.locator("dialog.signin-dialog");
    await expect(dialog).toHaveAttribute("open", "");
    // Wait for the toast to mount and then auto-dismiss (4s default + exit).
    await expect(page.getByRole("status")).toBeVisible();
    await expect(page.getByRole("status")).toHaveCount(0, { timeout: 8_000 });
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

  test("a failed patch during a full render triggers a resync instead of a silently stuck UI", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    await expect(page.getByText("Count: 0")).toBeVisible();

    await armNextPatchFailure(page);

    // "Show toast" mutates the ROOT Counter (@ReducerState var toasts) → a full
    // render whose batch the wrapper corrupts.
    await page.getByRole("button", { name: "Show toast" }).click();

    // Despite the injected failure, the app self-heals. The toast data lives on
    // Counter (the persistent ROOT), so resyncFullRemount's fresh diff — which
    // reuses that same root instance — rebuilds the toast and it still appears.
    const toast = page.getByRole("status");
    await expect(toast).toBeVisible();
    await expect(toast).toContainText("Saved!");

    // The whole tree was rebuilt from scratch — prove the app is fully
    // interactive afterward, not just visually intact.
    await page.getByRole("button", { name: "Increment" }).click();
    await expect(page.getByText("Count: 1")).toBeVisible();

    const texts = errors.map((e) => e.text());
    // A patch MUST have actually failed — otherwise the injection silently
    // no-oped and never exercised the resync at all (the failure mode this
    // suite previously had when it corrupted a removeHandler patch).
    expect(texts.some((t) => t.includes("patch failed")),
      "the injection must cause a real, caught patch failure").toBe(true);
    // …and nothing worse: a recoverable patch failure must NOT surface the
    // fatal "WASM execution stopped — reload" overlay error (it did, before we
    // stopped routing caught failures to the dev overlay).
    const unexpected = texts.filter((t) => !t.includes("patch failed"));
    expect(unexpected, "no console errors beyond the expected patch-failed log").toHaveLength(0);
  });

  test("a failed patch during a SCOPED (non-root) re-render also resyncs the whole tree", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg);
    });

    await page.goto("/");
    await expect(page.getByText("Count: 0")).toBeVisible();

    // Open the modal. SignIn is an EMBEDDED, non-root @Component that owns its
    // own @State (email/password/ctrl) — so mutating one of its fields marks
    // ONLY SignIn dirty and drives flushDirty's SCOPED arm (planRerender
    // excludes the root), a different resync call site than the full-render arm
    // above. The dialog is opened imperatively via showModal(), so it carries
    // the `open` attribute + native top-layer state — the lever this test uses
    // to prove a full-tree resync actually ran.
    await page.getByRole("button", { name: "Sign in…" }).click();
    const dialog = page.locator("dialog.signin-dialog");
    await expect(dialog).toHaveAttribute("open", "");
    const email = page.getByLabel("Email");
    await expect(email).toBeVisible();

    // Arm AFTER the dialog settles, so the next batch is the keystroke's SCOPED
    // SignIn re-render (its corrupted op is the setProperty writing the field's
    // value).
    await armNextPatchFailure(page);

    // Type one character — SignIn's controlled Email field writes to SignIn's
    // own @State, triggering the SCOPED re-render whose patch batch we corrupt.
    await email.pressSequentially("a", { delay: 0 });

    // The proof the resync ran on the SCOPED path: resyncFullRemount rebuilds
    // the ENTIRE tree from the root, which recreates the <dialog> element — and
    // a freshly-created native <dialog> loses the top-layer/`open` state that
    // only showModal() sets. A NORMAL scoped re-render would leave the dialog
    // untouched (open intact); a STUCK UI would leave it open AND frozen. Only
    // a genuine full-tree resync drops `open` here.
    await expect(dialog).not.toHaveAttribute("open", "");

    // …and the rebuilt tree is fully interactive: the root Counter still counts.
    // (SignIn's own field state is sacrificed by the coarse resync — by design;
    // the root's @State survives because the fresh diff reuses its instance.)
    await page.getByRole("button", { name: "Increment" }).click();
    await expect(page.getByText("Count: 1")).toBeVisible();

    const texts = errors.map((e) => e.text());
    expect(texts.some((t) => t.includes("patch failed")),
      "the injection must cause a real, caught patch failure").toBe(true);
    const unexpected = texts.filter((t) => !t.includes("patch failed"));
    expect(unexpected, "no console errors beyond the expected patch-failed log").toHaveLength(0);
  });
});
