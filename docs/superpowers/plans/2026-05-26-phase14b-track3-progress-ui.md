# Phase 14b Track 3 — Progress UI: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First-visit users see a real WASM download percentage in `[data-swiflow-progress]` instead of a blank screen. Repeat visits (SW cache hit) finish the stream so fast the attribute jumps to 100 within ~100ms — no flash, no spinner.

**Architecture:** The driver pre-fetches `App.wasm` with `fetch(url)` then streams the response body via a `ReadableStream` reader, summing bytes received against `Content-Length` and writing the percent to `document.documentElement.dataset.swiflowProgress`. The accumulated bytes are returned as a `Response` and handed to PackageToJS's `init({ module: response })` — which already accepts that shape. No service-worker changes; the SW continues to cache transparently and the driver's stream just completes quickly on cache hits.

**Tech Stack:** Vanilla JS, `ReadableStream.getReader()`, `Response` constructor. No new dependencies.

**Three design decisions locked in (from brainstorming):**
1. **No SW progress postMessage.** Driver-side fetch is the single source — SW timing means cross-process reporting buys nothing.
2. **Missing `Content-Length` → leave attribute unset.** The user's CSS rule simply doesn't fire. On completion the attribute jumps to `"100"` once so a "loaded" transition still works.
3. **Write target is `document.documentElement` only.** Predictable, one site, no querySelector at boot.

---

## File structure

| Path | Action | Responsibility |
|---|---|---|
| `js-driver/swiflow-driver.js` | modify | Add `fetchWithProgress(url)` helper. Replace bare `await init()` with `await init({ module: await fetchWithProgress(WASM_URL) })`. On any failure during fetch, fall back to letting PackageToJS do its own internal `fetch` so the user still gets a working app even if the streaming reader breaks. |
| `js-driver/test/progress.test.js` | **create** | node:test coverage: chunked stream → attribute progresses; missing Content-Length → attribute stays unset until 100; fetch rejection → graceful fallback (no progress, no thrown promise). |
| `js-driver/test/sw-helpers.js` | possibly modify | If the test needs a shared `mockReadableStream(chunks, contentLength)` helper, add it here next to the existing mock infra. Otherwise inline in the test. |
| `Sources/SwiflowCLI/Templates/Templates.swift` | modify | Add a `<style>` block to the default `index.html` template providing the documented `[data-swiflow-progress]::before` rule so new scaffolds get a working out-of-the-box loading UI. |
| `examples/HelloWorld/index.html` | modify | Mirror the template change (the existing template/example sync invariant). |
| `Tests/SwiflowCLITests/TemplatesTests.swift` | modify | The byte-equality test for `examples/HelloWorld/index.html` will need to be updated to reflect the new template content. Also add an assertion that the template contains the `[data-swiflow-progress]` CSS hook so a refactor doesn't silently delete it. |
| `Tests/playwright/progress.spec.ts` | **create** | E2E: against the release static server (port 3002), reload the page and watch `documentElement.dataset.swiflowProgress` — it should pass through at least one intermediate value (or, on a cache hit, jump straight to 100 within 100ms). |
| `Tests/playwright/playwright.config.ts` + `playwright.sw.config.ts` | possibly modify | If `progress.spec.ts` needs the SW config's static server, add a `testMatch` entry. Try to share the existing :3002 server. |
| `CHANGELOG.md` | modify | Phase 14b Track 3 entry above Track 2. |
| `README.md` | modify | Status line + a one-paragraph addition under "What works today" mentioning the progress hook. |

**Cross-task invariant:** `examples/HelloWorld/index.html` must remain byte-equal to whatever Templates.swift emits. If you change one, change the other in the same task.

---

## Task 1: Driver — `fetchWithProgress` helper

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Create: `js-driver/test/progress.test.js`

The helper is a pure function (no global state mutation) except for the one DOM write (`documentElement.dataset.swiflowProgress`). Its contract:

```
fetchWithProgress(url: string) -> Promise<Response>
  - calls fetch(url)
  - if response.body is null OR Content-Length absent → reads body normally,
    does NOT touch the dataset attribute; returns a Response over the
    accumulated bytes. (Cache hits without Content-Length still finish.)
  - if Content-Length present → streams chunks via getReader(),
    writes Math.floor((bytesRead / total) * 100) to
    documentElement.dataset.swiflowProgress after each chunk
  - on stream completion (or non-streaming path), writes "100" once
  - on fetch rejection → re-throws (caller decides fallback)
```

- [ ] **Step 1: Write the failing tests**

Create `js-driver/test/progress.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import vm from "node:vm";
import fs from "node:fs";

// Build a Response whose body is a ReadableStream emitting the given
// chunks (Uint8Arrays). `contentLength` is the Content-Length header
// to advertise; pass null to omit the header.
function streamedResponse(chunks, contentLength) {
  const stream = new ReadableStream({
    async start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(chunk);
        // Tiny yield so progress writes between chunks are observable.
        await new Promise((r) => setImmediate(r));
      }
      controller.close();
    },
  });
  const headers = contentLength != null
    ? { "Content-Length": String(contentLength) }
    : {};
  return new Response(stream, { headers });
}

function setupDriver() {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    runScripts: "outside-only",
  });
  const window = dom.window;
  // Expose the helper. The driver source is an IIFE that attaches to
  // window.swiflow; for testing, we expose fetchWithProgress on
  // window.swiflow.__test_fetchWithProgress (production code path can
  // keep it private — see Step 3).
  const driverSrc = fs.readFileSync("js-driver/swiflow-driver.js", "utf8");
  const ctx = vm.createContext({
    window,
    document: window.document,
    fetch: window.fetch,
    Response,
    ReadableStream,
    Uint8Array,
    setImmediate,
    // Block production IIFE from booting WASM during the test.
    __SWIFLOW_SKIP_BOOT: true,
  });
  // Make window.* global so the IIFE's references resolve.
  vm.runInContext(`
    Object.assign(globalThis, window);
    window.__SWIFLOW_SKIP_BOOT = true;
  `, ctx);
  vm.runInContext(driverSrc, ctx);
  return { window, ctx };
}

test("fetchWithProgress writes increasing percent when Content-Length known", async () => {
  const { window, ctx } = setupDriver();
  const fetchWithProgress = vm.runInContext(
    "window.swiflow.__test_fetchWithProgress",
    ctx
  );
  assert.ok(typeof fetchWithProgress === "function",
    "expected window.swiflow.__test_fetchWithProgress to be exposed");

  const chunks = [
    new Uint8Array(250),
    new Uint8Array(250),
    new Uint8Array(500),
  ]; // total 1000 bytes
  const totalLen = 1000;

  // Override fetch to return our streamed response.
  vm.runInContext(`
    fetch = (url) => Promise.resolve(global.__nextResponse);
  `, ctx);
  ctx.__nextResponse = streamedResponse(chunks, totalLen);

  const seenPercents = [];
  const obs = new window.MutationObserver(() => {
    seenPercents.push(window.document.documentElement.dataset.swiflowProgress);
  });
  obs.observe(window.document.documentElement, { attributes: true });

  const res = await fetchWithProgress("any://url");
  obs.disconnect();

  // Body should be readable.
  const bytes = new Uint8Array(await res.arrayBuffer());
  assert.equal(bytes.length, 1000);

  // Final value is "100"; we should have seen at least one intermediate
  // value (25 or 50) between 0 and 100.
  const final = window.document.documentElement.dataset.swiflowProgress;
  assert.equal(final, "100");
  const intermediates = seenPercents.filter(v => v !== "100");
  assert.ok(intermediates.length >= 1,
    `expected at least one intermediate percent, saw: ${JSON.stringify(seenPercents)}`);
});

test("fetchWithProgress leaves attribute unset when Content-Length absent until completion", async () => {
  const { window, ctx } = setupDriver();
  const fetchWithProgress = vm.runInContext(
    "window.swiflow.__test_fetchWithProgress", ctx);

  vm.runInContext(`fetch = (u) => Promise.resolve(global.__nextResponse);`, ctx);
  ctx.__nextResponse = streamedResponse([new Uint8Array(500), new Uint8Array(500)], null);

  const seen = [];
  const obs = new window.MutationObserver(() => {
    seen.push(window.document.documentElement.dataset.swiflowProgress);
  });
  obs.observe(window.document.documentElement, { attributes: true });

  await fetchWithProgress("any://url");
  obs.disconnect();

  // Only write should be the final "100" (no intermediates).
  assert.deepEqual(seen, ["100"]);
});

test("fetchWithProgress re-throws on fetch failure without touching the attribute", async () => {
  const { window, ctx } = setupDriver();
  const fetchWithProgress = vm.runInContext(
    "window.swiflow.__test_fetchWithProgress", ctx);

  vm.runInContext(`fetch = () => Promise.reject(new Error("network down"));`, ctx);

  await assert.rejects(
    () => fetchWithProgress("any://url"),
    /network down/
  );
  assert.equal(
    window.document.documentElement.dataset.swiflowProgress,
    undefined
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd js-driver
npm test 2>&1 | tail -30
```

Expected: 3 new tests fail (helper undefined).

- [ ] **Step 3: Implement `fetchWithProgress` in `swiflow-driver.js`**

Inside the existing IIFE in `js-driver/swiflow-driver.js`, add (above the production boot IIFE):

```js
/**
 * Pre-fetch `url` and stream the body, reporting download progress to
 * `document.documentElement.dataset.swiflowProgress` (a string "0".."100").
 *
 * When Content-Length is missing, no intermediate writes happen — only
 * a final "100" once the stream completes — because the percent can't
 * be computed without the total. The user's CSS rule
 * `[data-swiflow-progress]:not([=\"100\"])::before` therefore stays
 * dormant in that case.
 *
 * Returns a Response over the accumulated bytes so the caller can hand
 * it to PackageToJS's init({ module }) without re-fetching.
 */
async function fetchWithProgress(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`swiflow: fetch ${url} failed (${res.status})`);
  }
  const total = parseInt(res.headers.get("Content-Length") || "", 10);
  const reader = res.body && res.body.getReader ? res.body.getReader() : null;
  if (!reader) {
    // Response has no streamable body (some test environments). Just
    // pass through; PackageToJS will accept the original Response.
    document.documentElement.dataset.swiflowProgress = "100";
    return res;
  }

  const chunks = [];
  let received = 0;
  // Only write percent when we have a total.
  const canReport = Number.isFinite(total) && total > 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.byteLength;
    if (canReport) {
      const pct = Math.floor((received / total) * 100);
      // Clamp at 99 until the stream is actually done, so the user can
      // tell "downloading" from "done".
      document.documentElement.dataset.swiflowProgress =
        String(Math.min(pct, 99));
    }
  }
  document.documentElement.dataset.swiflowProgress = "100";

  // Reassemble as a single Response so PackageToJS can compile it.
  const body = new Blob(chunks, { type: res.headers.get("Content-Type") || "application/wasm" });
  return new Response(body, { headers: res.headers, status: res.status });
}

// Expose for tests only — production code paths reference the local
// `fetchWithProgress` directly.
window.swiflow.__test_fetchWithProgress = fetchWithProgress;
```

**Where to place it:** inside the existing top-level IIFE in `swiflow-driver.js`, near the `__boot` definition. Keep `window.swiflow.__test_fetchWithProgress` opt-in — production users don't reference it, but the test harness does.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd js-driver
npm test 2>&1 | tail -30
```

Expected: all driver tests pass, including the 3 new progress tests. If a test fails because of a JSDOM/Node version quirk around `MutationObserver` timing, simplify the assertion (e.g., poll `dataset.swiflowProgress` at intervals instead of using the observer) — describe the workaround in the commit message if you take one.

- [ ] **Step 5: Commit**

```bash
git add js-driver/swiflow-driver.js js-driver/test/progress.test.js
git commit -m "$(cat <<'EOF'
feat(driver): fetchWithProgress helper for WASM download UI

Streams the fetch body via getReader(), summing bytes and writing
percent to documentElement.dataset.swiflowProgress when
Content-Length is known. Final "100" write happens unconditionally
on completion. Returns a Response over the accumulated bytes so
PackageToJS's init({ module }) can compile without re-fetching.
EOF
)"
```

---

## Task 2: Wire `fetchWithProgress` into the driver boot

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Modify: `js-driver/test/dev-reload.test.js` (or wherever the existing boot path is tested)

The current driver boot path:

```js
(async () => {
  if (window.__SWIFLOW_SKIP_BOOT) return;
  await window.swiflow.__boot({ swiflowDev: !!window.SWIFLOW_DEV });
  if (window.swiflow.__inited) return;
  window.swiflow.__inited = true;
  try {
    const { init } = await import("./.build/plugins/PackageToJS/outputs/Package/index.js");
    await init();
  } catch (e) {
    console.warn("swiflow: WASM init failed", e);
  }
})();
```

Replace `await init();` with the progress-streaming pre-fetch:

- [ ] **Step 1: Add a constant for the WASM URL**

At the top of the driver IIFE alongside other module-level constants:

```js
const WASM_URL = "./.build/plugins/PackageToJS/outputs/Package/App.wasm";
```

Path matches PackageToJS's `import.meta.url` resolution for the default case.

- [ ] **Step 2: Update the boot IIFE to pre-fetch**

```js
try {
  const { init } = await import("./.build/plugins/PackageToJS/outputs/Package/index.js");
  // Pre-fetch with progress so users see a percent. On any failure here,
  // let PackageToJS run its own fetch — better degraded UX than no app.
  let modulePromise;
  try {
    modulePromise = fetchWithProgress(WASM_URL);
  } catch (e) {
    console.warn("swiflow: progress fetch failed, falling back to default init", e);
    modulePromise = undefined;
  }
  await init({ module: modulePromise });
} catch (e) {
  console.warn("swiflow: WASM init failed", e);
}
```

**Important:** `init({ module: <Promise<Response>> })` accepts a promise of a Response. Don't `await` the promise before passing it — PackageToJS does its own `await` inside.

- [ ] **Step 3: Update / add a boot-path test**

The existing test that covers the production IIFE already gates on `__SWIFLOW_SKIP_BOOT`. We don't need to test the actual init call (that's PackageToJS's job). What we DO need: a test asserting that if the boot path runs, `fetchWithProgress` is called with the correct URL.

In `js-driver/test/progress.test.js` (extending Task 1's file):

```js
test("driver boot calls fetchWithProgress with the PackageToJS WASM URL", async () => {
  // Set up driver WITHOUT __SWIFLOW_SKIP_BOOT so the IIFE runs.
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { runScripts: "outside-only" });
  const window = dom.window;
  // Capture the URL the driver fetches.
  let fetchedURL = null;
  const ctx = vm.createContext({
    window, document: window.document,
    fetch: (u) => {
      fetchedURL = u;
      // Return a tiny stream so init resolves; we don't actually run WASM.
      return Promise.resolve(streamedResponse([new Uint8Array(4)], 4));
    },
    Response, ReadableStream, Uint8Array, setImmediate,
    Blob: window.Blob,
    MutationObserver: window.MutationObserver,
  });
  vm.runInContext(`Object.assign(globalThis, window);`, ctx);
  // Stub the dynamic import so the test doesn't try to load real PackageToJS.
  vm.runInContext(`
    globalThis.__importStub = (url) => Promise.resolve({
      init: async ({ module } = {}) => {
        globalThis.__initSawModule = module;
      },
    });
  `, ctx);
  // Patch import() — easiest path is to substitute the literal import call
  // in the source under test. Instead, add a __SWIFLOW_TEST_IMPORT hook
  // in the production code (Step 4 below) so the test can override it.

  // ... drive the IIFE via a `setTimeout(0)` await ...
  await new Promise((r) => setTimeout(r, 50));

  assert.equal(fetchedURL, "./.build/plugins/PackageToJS/outputs/Package/App.wasm");
  assert.ok(vm.runInContext("globalThis.__initSawModule", ctx),
    "expected init() to be called with a module argument");
});
```

The dynamic-import stubbing is awkward to test cleanly. **Acceptable alternatives:**

1. Skip this test entirely and rely on the Playwright e2e (Task 4) for boot coverage.
2. Refactor the boot IIFE so the dynamic import target is a parameter (`window.swiflow.__bootImport = (url) => import(url)`) that the test can override.

**Recommendation:** option 1. Keep the unit tests scoped to `fetchWithProgress` alone; let Playwright cover the integrated boot path. If you go with option 1, delete the test stub above before committing.

- [ ] **Step 4: Run all driver tests**

```bash
cd js-driver
npm test 2>&1 | tail -30
```

Expected: all tests still pass.

- [ ] **Step 5: Regenerate the embedded driver**

The driver is embedded into the CLI binary as a Swift constant. Re-emit:

```bash
swift scripts/embed-driver.swift
```

Verify by:

```bash
grep -c "fetchWithProgress" Sources/SwiflowCLI/EmbeddedDriver.swift
# Expected: at least 1 (the function name appears in the embedded source).
```

- [ ] **Step 6: Commit**

```bash
git add js-driver/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "$(cat <<'EOF'
feat(driver): pre-fetch App.wasm with progress reporting

The boot IIFE now pre-fetches the WASM via fetchWithProgress and
hands the resulting Response to PackageToJS init({ module }), so
documentElement.dataset.swiflowProgress carries 0..100 during
download. Cache-hit visits (Track 1 service worker) complete the
stream within a tick so the attribute jumps straight to 100 and
no flash shows. On any progress-fetch failure the driver falls
back to PackageToJS's default fetch so the app still boots.
EOF
)"
```

---

## Task 3: Default loading CSS in template + HelloWorld

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- Modify: `examples/HelloWorld/index.html`
- Modify: `Tests/SwiflowCLITests/TemplatesTests.swift`

The driver writes the attribute, but users need a default visual so `swiflow init` produces something that "works on first visit." The CSS rule is the minimum that shows a percent overlay without requiring any user authoring.

- [ ] **Step 1: Read the current template body**

```bash
grep -A 5 "<body" Sources/SwiflowCLI/Templates/Templates.swift | head -20
```

Find the `<head>` section. The CSS hook goes inside `<head>`.

- [ ] **Step 2: Add the default CSS rule**

In `Sources/SwiflowCLI/Templates/Templates.swift`, inside the `<head>` block of the index.html template, add:

```html
<style>
  /* Swiflow loading indicator. The driver writes
     documentElement.dataset.swiflowProgress = "0".."100"
     during WASM fetch. Customize freely. */
  html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
    content: "Loading " attr(data-swiflow-progress) "%";
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #f8f8f8;
    color: #333;
    font: 16px/1.4 system-ui, sans-serif;
    z-index: 9999;
  }
</style>
```

Match the existing template indentation. Don't change anything else in the template.

- [ ] **Step 3: Mirror the change in `examples/HelloWorld/index.html`**

The example file must be byte-equal to whatever Templates.swift emits (this is the pre-existing template/example sync invariant — see `TemplatesTests.swift`). Copy the same CSS into HelloWorld's `<head>`.

- [ ] **Step 4: Update the template byte-equality test**

In `Tests/SwiflowCLITests/TemplatesTests.swift`, the test `examples/HelloWorld/index.html byte-equals template output` (or similarly named — check exact name) will fail because the template now contains the new CSS. The fix is to confirm both files are updated consistently — the byte-equality test should already pass once both files have the new CSS.

Add one new test asserting the CSS hook is in the template:

```swift
@Test("Default template includes [data-swiflow-progress] loading hook")
func templateHasProgressHook() throws {
    let html = Templates.indexHTML(projectName: "demo")
    #expect(html.contains("[data-swiflow-progress]"))
    #expect(html.contains("html[data-swiflow-progress]:not([data-swiflow-progress=\"100\"])"))
}
```

(Adjust the API call to match `Templates`'s actual surface — read the file first.)

- [ ] **Step 5: Run tests**

```bash
swift test --filter TemplatesTests 2>&1 | tail -20
swift test 2>&1 | tail -5
```

Expected: all tests pass. If byte-equality fails, one of the two files is stale.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift \
        examples/HelloWorld/index.html \
        Tests/SwiflowCLITests/TemplatesTests.swift
git commit -m "$(cat <<'EOF'
feat(templates): default [data-swiflow-progress] loading CSS

swiflow init now scaffolds an index.html that shows the WASM
download percent on first visit. The CSS targets the html element
attribute the driver writes during fetchWithProgress; users can
override or remove the rule entirely. examples/HelloWorld is
updated to match (existing template/example byte-equality invariant).
EOF
)"
```

---

## Task 4: Playwright e2e for progress UI

**Files:**
- Create: `Tests/playwright/progress.spec.ts`
- Modify: `Tests/playwright/playwright.sw.config.ts` (add `progress.spec.ts` to testMatch — both specs share the :3002 static server)

The unit tests prove `fetchWithProgress` mechanically. The Playwright spec proves the full boot path works in a real browser.

- [ ] **Step 1: Read the existing SW spec for shape**

```bash
cat Tests/playwright/sw-cache.spec.ts
```

We want a similar shape: stand up the static server, open the page, observe `documentElement.dataset.swiflowProgress`.

- [ ] **Step 2: Write the spec**

Create `Tests/playwright/progress.spec.ts`:

```ts
import { test, expect } from "@playwright/test";

test.describe("progress attribute during WASM load", () => {
  test("transitions from undefined → numeric → 100 on first visit", async ({ page }) => {
    // Capture every value the attribute takes on, in order.
    const seen: string[] = [];
    await page.exposeFunction("__recordProgress", (v: string) => {
      seen.push(v);
    });
    await page.addInitScript(() => {
      const html = document.documentElement;
      const obs = new MutationObserver(() => {
        const v = html.dataset.swiflowProgress;
        if (v != null) {
          (window as any).__recordProgress(v);
        }
      });
      obs.observe(html, { attributes: true, attributeFilter: ["data-swiflow-progress"] });
    });

    await page.goto("/");

    // Wait for "100" — the final write.
    await expect.poll(
      () => page.evaluate(() => document.documentElement.dataset.swiflowProgress),
      { timeout: 30_000 }
    ).toBe("100");

    // We should have seen at least one value (could be just "100" on a
    // hot cache, or several percentages on a cold load).
    expect(seen.length).toBeGreaterThanOrEqual(1);
    expect(seen.at(-1)).toBe("100");
  });
});
```

- [ ] **Step 3: Wire it into the SW config's testMatch**

In `Tests/playwright/playwright.sw.config.ts`:

```ts
testMatch: ["sw-cache.spec.ts", "progress.spec.ts"],
```

Also add to the main `playwright.config.ts` if it has an explicit testMatch (most likely it doesn't — it includes everything by default).

- [ ] **Step 4: Build CLI fresh and rerun the SW demo**

```bash
swift build -c release --product swiflow
```

(playwright.sw.config.ts re-scaffolds the demo and runs `swiflow build` at config-load time, so no extra steps needed.)

- [ ] **Step 5: Run the SW spec config**

```bash
cd Tests/playwright
npx playwright test --config=playwright.sw.config.ts 2>&1 | tail -40
```

Expected: both `sw-cache.spec.ts` and `progress.spec.ts` pass.

If `progress.spec.ts` flakes, common causes:
- The attribute observer setup runs AFTER the driver has already started fetching → adjust by setting up the observer in `addInitScript` (already done) which runs before any page script.
- On a SW cache hit, the stream completes within microseconds and the observer never fires intermediate values — that's fine, the spec only requires at least one value and final "100".

- [ ] **Step 6: Commit**

```bash
git add Tests/playwright/progress.spec.ts \
        Tests/playwright/playwright.sw.config.ts
git commit -m "$(cat <<'EOF'
test(playwright): assert WASM-load progress reaches 100

Watches documentElement.dataset.swiflowProgress via MutationObserver
installed at page-init time. First load goes through intermediate
percents; cache hits jump to 100. Shares the SW-spec's static server
on :3002 to keep the local fast-iteration path single-config.
EOF
)"
```

---

## Task 5: CHANGELOG + README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Add CHANGELOG entry**

In `CHANGELOG.md`, above the existing `[Phase 14b — Track 2]` entry:

```markdown
## [Phase 14b — Track 3] — 2026-05-26

**Stability:** Driver-side enhancement. No Swift API moves, no new
prereqs, no breaking change.

### Added
- `fetchWithProgress` helper in `swiflow-driver.js`: streams the WASM
  fetch and writes the percent to
  `document.documentElement.dataset.swiflowProgress`.
- Default `[data-swiflow-progress]` CSS rule in `swiflow init`
  scaffold so new projects show a "Loading N%" overlay out of the
  box. Users style or remove freely.
- Playwright `progress.spec.ts` covering the attribute path.

### Changed
- Driver boot pre-fetches `App.wasm` and hands the `Response` to
  PackageToJS `init({ module })` instead of letting PackageToJS run
  its own fetch internally. On cache hits (Track 1 service worker)
  the stream completes within a tick and the attribute jumps to
  "100" without an intermediate flash.

### Constraints
- When `Content-Length` is absent (some CDN configurations) the
  driver does not write intermediate percents — only the final
  `"100"`. The user's CSS rule
  `[data-swiflow-progress]:not([="100"])::before` stays dormant in
  that case rather than showing a misleading "0%" indefinitely.
```

- [ ] **Step 2: Update README status line**

In `README.md`, near line 16:

```markdown
**Status:** Phase 14b Track 3 (Progress UI) — first-visit users now see
a real WASM download percent in `[data-swiflow-progress]` during the
~18 MB transfer. Repeat visits (Track 1 service-worker cache) jump to
100 instantly. Combined with Track 1, the cold-vs-warm UX gap is now
"watch a percent on visit #1, transparent visit #2+."
```

- [ ] **Step 3: Update the cost-table prose**

The existing first-visit row says "30s on 4G with a blank page" in spirit. Update to mention the progress overlay:

```markdown
- **WASM bundle (HelloWorld example, release):** ~46 MB raw / ~18 MB
  gzipped on the wire on the first visit. Users see a "Loading N%"
  overlay during the download (Phase 14b Track 3); a Vite-built JS
  app this is not. ...
```

(Adjust the surrounding sentence to match — read the existing line first.)

- [ ] **Step 4: Update test counts**

If Task 1 and Task 4 added tests, refresh the line that mentions "545 Swift tests / 26 JS driver tests." Get fresh counts with:

```bash
swift test 2>&1 | grep "Suite.*passed"
cd js-driver && npm test 2>&1 | grep -E "tests passed|tests run"
```

- [ ] **Step 5: Prepend Track 3 to the historical "Status" paragraph**

Below the cost table, the historical status paragraph already lists Tracks 1 and 2. Prepend a one-sentence Track 3 summary in the same pattern.

- [ ] **Step 6: Commit and push**

```bash
git add CHANGELOG.md README.md
git commit -m "$(cat <<'EOF'
docs: Phase 14b Track 3 — Progress UI

CHANGELOG entry above Track 2 documents the new fetchWithProgress
path and the data-swiflow-progress attribute contract. README status
line and cost prose reflect the new first-visit UX (percent overlay
during download, instant on repeat visits via Track 1 SW cache).
EOF
)"
git push origin main
```

---

## Final verification

After Task 5 lands:

```bash
# JS driver suite
cd js-driver
npm test                                 # all PASS including 3 progress tests

# Swift suite
cd ..
swift test                               # all green; new TemplatesTests row passes

# Playwright SW + progress
cd Tests/playwright
npx playwright test --config=playwright.sw.config.ts  # 2 PASS

# CLI doctor still works
cd ../..
./.build/release/swiflow doctor          # exit 0

# Hand-eyeball
cd examples/HelloWorld
swift package clean
../../.build/release/swiflow build
python3 -m http.server 3030 &
open http://localhost:3030               # see "Loading N%" briefly, then app renders
kill %1
```

**Success criterion from the spec:** First-visit users see a continuously-updating progress percentage from 0 → 100 during the WASM fetch. Repeat visits jump to 100 within ~100ms.
