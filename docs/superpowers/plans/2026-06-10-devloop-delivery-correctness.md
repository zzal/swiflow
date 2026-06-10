# Dev-Loop & Delivery Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the audit's one CRITICAL (service worker never updates production deploys) plus 5 dev-loop/delivery HIGHs from `docs/reviews/2026-06-10-quality-audit.md`.

**Architecture:** Three js-driver changes (SW build-tag stamping so the browser's byte-compare update check fires per build; per-patch error isolation with production-visible errors; hmrSwap reentrancy guard + stale-CSS removal) and two CLI changes (reload-vs-hmr-swap dispatch by changed file type; doctor probes for what build actually requires). Every js-driver edit re-runs the embed codegen and refreshes the example copies, guarded by existing freshness tests.

**Tech Stack:** Vanilla JS driver + jsdom tests (`cd js-driver && npm test`), Swift 6 / Swift Testing for CLI, codegen via `swift scripts/embed-driver.swift` + `swift scripts/embed-templates.swift`.

**Audit findings cleared:** Unit 11 CRITICAL (SW pinned-forever), Unit 11 HIGH ×2 (mixed crash/silent patches; dev-gated error signal), Unit 4 HIGH (HMR serves stale CSS), Unit 3/SwiflowCLI HIGH ×2 (HTML edits never reach the browser; doctor passes where build fails). Also Unit 11 MEDIUMs: hmrSwap reentrancy, dead `fetchWithProgress` catch.

---

## Environment notes (read first)

- Swift tests: ALWAYS `env -u SWIFLOW_SOURCE swift test` (shell env leak breaks one unrelated test). Suite is currently **773 tests / 175 suites green** on `main` @ `6dd9e14`.
- JS tests: `cd js-driver && npm test` (33 cases green currently; node_modules present).
- **Codegen discipline (applies to Tasks 1-3):** any edit to `js-driver/swiflow-driver.js` or `js-driver/swiflow-sw.js` requires, before commit:
  1. `swift scripts/embed-driver.swift` (regenerates `Sources/SwiflowCLI/EmbeddedDriver.swift`)
  2. Refresh example copies: `for d in examples/*/; do cp js-driver/swiflow-driver.js "$d"; cp js-driver/swiflow-sw.js "$d"; done`
  3. `swift scripts/embed-templates.swift` (examples are embedded as templates)
  4. `env -u SWIFLOW_SOURCE swift test --filter "DriverEmbedderTests|TemplateEmbedderTests"` — the freshness guards
- Branch: `git checkout -b feat/devloop-delivery-correctness` from `main`.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `js-driver/swiflow-sw.js` | modify | `BUILD_TAG` placeholder so emitted bytes change per build |
| `js-driver/swiflow-driver.js` | modify | per-patch isolation; prod `console.error`; hmrSwap guard + CSS cleanup; dead-catch removal |
| `Sources/SwiflowCLI/DriverInstaller.swift` | modify | new `stampServiceWorker(into:buildTag:)` |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | modify | `writeManifest` returns the manifest; stamp call after it |
| `Sources/SwiflowCLI/Commands/DevCommand.swift` | modify | dispatch reload vs hmr-swap per changed file types |
| `Sources/SwiflowCLI/Commands/DoctorCommand.swift` | modify | macOS-toolchain + wasm-opt probes |
| `js-driver/test/sw.test.js`, `test/opcodes.test.js`, `test/hmr-swap.test.js` | modify | new jsdom cases |
| `Tests/SwiflowCLITests/DriverInstallerTests.swift` | create | stamping behavior |
| `Tests/SwiflowCLITests/DevCommandTests.swift`, `DoctorCommandTests.swift` | modify/create | dispatch decision + doctor report |
| `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md` | modify | bookkeeping |

---

### Task 1: Service-worker build-tag stamping (the CRITICAL)

The SW file (`swiflow-sw.js`) is emitted verbatim by `DriverInstaller` and is byte-identical across builds, so the browser's update check never re-fires `install`, the new manifest is never fetched, and caches-first serves the first deploy forever. Fix: a `__SWIFLOW_BUILD_TAG__` placeholder in the SW source, stamped with a manifest-derived hash by `swiflow build` — new bytes per build → standard SW update lifecycle (install new caches → activate on next visit after tabs close → `cleanupStale`).

**Files:**
- Modify: `js-driver/swiflow-sw.js` (placeholder + doc), `Sources/SwiflowCLI/DriverInstaller.swift`, `Sources/SwiflowCLI/Commands/BuildCommand.swift` (writeManifest return + stamp call)
- Test: `Tests/SwiflowCLITests/DriverInstallerTests.swift` (create), `js-driver/test/sw.test.js` (one case)

- [ ] **Step 1: Write the failing Swift test**

```swift
// Tests/SwiflowCLITests/DriverInstallerTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite struct DriverInstallerTests {

    @Test func stampReplacesBuildTagPlaceholder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try DriverInstaller.install(into: dir)
        try DriverInstaller.stampServiceWorker(into: dir, buildTag: "deadbeefcafe")

        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-sw.js"), encoding: .utf8)
        #expect(sw.contains("deadbeefcafe"))
        #expect(!sw.contains("__SWIFLOW_BUILD_TAG__"),
                "the placeholder must be fully replaced in the emitted file")
    }

    @Test func embeddedServiceWorkerCarriesThePlaceholder() {
        #expect(EmbeddedDriver.serviceWorkerSource.contains("__SWIFLOW_BUILD_TAG__"),
                "the repo/template copy must keep the placeholder for stamping")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter DriverInstallerTests`
Expected: compile failure (`stampServiceWorker` doesn't exist); the placeholder test would also fail (not yet in the SW source).

- [ ] **Step 3: Add the placeholder to the SW source**

In `js-driver/swiflow-sw.js`, after the `MANIFEST_URL` const (line ~19), insert:

```js
// Build tag — the Swiflow CLI replaces the placeholder below on every
// `swiflow build` (DriverInstaller.stampServiceWorker), so this file's bytes
// change whenever the app changes. That is what makes the browser's
// byte-compare SW update check re-fire `install` (which precaches the new
// manifest) — without it, returning visitors would be pinned to the first
// deploy forever. Activation still follows the standard SW lifecycle: the
// new worker takes over on the next visit after all tabs close (we
// deliberately don't skipWaiting; see the install handler).
const BUILD_TAG = "__SWIFLOW_BUILD_TAG__";
```

And in the `install` listener, first line inside the `waitUntil` async block, add:

```js
    self.__swiflowBuildTag = BUILD_TAG; // exposed for debugging/tests
```

- [ ] **Step 4: Implement `stampServiceWorker` and the build-side call**

`Sources/SwiflowCLI/DriverInstaller.swift` — add below `install(into:)`:

```swift
    /// Re-emits `swiflow-sw.js` with the build tag stamped in. Called by
    /// `swiflow build` AFTER the manifest is written, so the tag reflects the
    /// artifacts actually being served. A changed tag changes the SW file's
    /// bytes, which is what makes the browser's update check re-fire
    /// `install` and precache the new manifest — without this, returning
    /// visitors stay pinned to the first-ever-cached bundle.
    static func stampServiceWorker(into projectDir: URL, buildTag: String) throws {
        let stamped = EmbeddedDriver.serviceWorkerSource.replacingOccurrences(
            of: "__SWIFLOW_BUILD_TAG__",
            with: buildTag
        )
        try stamped.write(
            to: projectDir.appendingPathComponent("swiflow-sw.js"),
            atomically: true,
            encoding: .utf8
        )
    }
```

`Sources/SwiflowCLI/Commands/BuildCommand.swift` — change `writeManifest` to return the manifest (it currently ends with `try manifest.encoded().write(...)`):

```swift
    @discardableResult
    package static func writeManifest(projectDir: URL) throws -> BundleManifest {
        // … existing body unchanged …
        let manifest = BundleManifest(version: "1", wasm: wasmEntry, runtime: runtimeEntries)
        try manifest.encoded().write(
            to: projectDir.appendingPathComponent("swiflow-manifest.json"),
            options: .atomic
        )
        return manifest
    }
```

At the `run()` call site where `writeManifest(projectDir:)` is invoked, replace with:

```swift
        let manifest = try Self.writeManifest(projectDir: projectURL)
        // Stamp the SW with a manifest-derived tag so its bytes change per
        // build (SW update lifecycle — see DriverInstaller.stampServiceWorker).
        let tag = (manifest.wasm.sha256.prefix(12)
            + "-"
            + manifest.runtime.map(\.sha256.prefix(4)).joined()).description
        try DriverInstaller.stampServiceWorker(into: projectURL, buildTag: tag)
```

(Adapt the exact call-site variable names — `projectURL` vs `projectDir` — to what `run()` uses; verify `BundleManifest`/`Entry` expose `sha256` as `String`, which `Entry.computing` implies. If `manifest.runtime.map(\.sha256.prefix(4))` displeases the type-checker, spell it `manifest.runtime.map { String($0.sha256.prefix(4)) }.joined()`.)

- [ ] **Step 5: Add the jsdom case**

In `js-driver/test/sw.test.js`, append (match the file's existing test style — read its imports/setup first):

```js
test("sw source carries the build-tag placeholder for CLI stamping", () => {
  const src = fs.readFileSync(new URL("../swiflow-sw.js", import.meta.url), "utf8");
  assert.ok(src.includes('const BUILD_TAG = "__SWIFLOW_BUILD_TAG__";'));
});
```

(If sw.test.js doesn't already import `fs`/`assert`, add the imports in the file's established style; the other SW tests in this file show the pattern.)

- [ ] **Step 6: Codegen + run everything**

```bash
swift scripts/embed-driver.swift
for d in examples/*/; do cp js-driver/swiflow-sw.js "$d"; done
swift scripts/embed-templates.swift
```

Run: `cd js-driver && npm test` → all green (34 cases).
Run: `env -u SWIFLOW_SOURCE swift test --filter "DriverInstallerTests|DriverEmbedderTests|TemplateEmbedderTests|BuildCommand"` → green.
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "fix(sw): stamp a per-build tag into swiflow-sw.js so deploys actually update

The SW was byte-identical across builds: the browser update check never
re-fired install, the new manifest was never fetched, and caches-first
served the first deploy forever. Clears audit CRITICAL: 'SW has no
update trigger'."
```

---

### Task 2: Per-patch isolation + production-visible errors (driver)

`applyPatches` has no per-patch try/catch: one stale handle TypeError aborts the rest of the batch mid-frame (half-patched DOM), and in production nothing surfaces it (the overlay + RAF shim are dev-gated; boot failure is a `console.warn`).

**Files:**
- Modify: `js-driver/swiflow-driver.js` (`applyPatches`, boot IIFE)
- Test: `js-driver/test/opcodes.test.js`

- [ ] **Step 1: Write the failing jsdom test**

In `js-driver/test/opcodes.test.js`, append (using the file's existing harness helpers for loading the driver and building patches — read the top of the file and mirror an existing opcode test's setup):

```js
test("a failing patch does not abort the rest of the batch and logs an error", () => {
  const errors = [];
  const origError = console.error;
  console.error = (...args) => { errors.push(args); };
  try {
    window.swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      // Bad: parent handle 999 was never created — this used to throw and
      // abort the remaining patches.
      { op: "appendChild", parent: 999, child: 1 },
      { op: "createElement", handle: 2, tag: "span" },
    ]);
  } finally {
    console.error = origError;
  }
  // The batch continued: handle 2 exists and is usable.
  assert.ok(window.swiflow.nodeForHandle(2));
  // And the failure was loudly reported.
  assert.ok(errors.some(a => String(a[0]).includes("patch failed")));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd js-driver && npm test`
Expected: the new test FAILS (TypeError propagates out of `applyPatches`, handle 2 never created).

- [ ] **Step 3: Implement per-patch isolation**

In `js-driver/swiflow-driver.js`, replace `applyPatches` (currently a bare for-loop):

```js
    /** Called by Swift each frame with a JSArray of patch objects.
     *  Each patch is applied in its own try/catch: one bad handle must not
     *  abort the rest of the frame (a half-applied batch is strictly worse
     *  than a batch with one skipped op). Failures are console.error'd in
     *  ALL builds — production included — and additionally routed to the
     *  dev overlay when the dev server installed it. */
    applyPatches: function (patches) {
      for (let i = 0; i < patches.length; i++) {
        try {
          applyOne(patches[i]);
        } catch (e) {
          console.error(
            "swiflow-driver: patch failed (op " +
              (patches[i] && patches[i].op) + ", index " + i + " of " +
              patches.length + ")", patches[i], e
          );
          if (typeof window.__swiflowDevError === "function") {
            window.__swiflowDevError(e);
          }
        }
      }
    },
```

- [ ] **Step 4: Make production boot failures loud and remove the dead catch**

In the boot IIFE at the bottom of the file:

1. Replace the unreachable progress-fallback block:
```js
      let modulePromise;
      try {
        modulePromise = fetchWithProgress(WASM_URL);
      } catch (e) {
        console.warn("swiflow: progress fetch failed, falling back to default init", e);
        modulePromise = undefined;
      }
      await init({ module: modulePromise });
```
with:
```js
      // fetchWithProgress is async — it cannot throw synchronously, so the
      // old try/catch "fallback" here was dead code. Rejections surface in
      // the outer catch below via `await init(...)`.
      await init({ module: fetchWithProgress(WASM_URL) });
```

2. In the outer catch, change `console.warn("swiflow: WASM init failed", e);` to `console.error("swiflow: WASM init failed", e);` and update the preceding comment's last sentence from "leaves the page silently dead." to "leaves the page silently dead — error level so production consoles surface it."

- [ ] **Step 5: Codegen + run everything**

```bash
swift scripts/embed-driver.swift
for d in examples/*/; do cp js-driver/swiflow-driver.js "$d"; done
swift scripts/embed-templates.swift
cd js-driver && npm test && cd ..
env -u SWIFLOW_SOURCE swift test
```
Expected: jsdom suite green (35 cases), full Swift suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(driver): per-patch error isolation + production-visible errors

One bad handle no longer aborts the rest of a patch batch; failures are
console.error'd in all builds (overlay still dev-only). Boot failure is
error-level; removed the unreachable fetchWithProgress fallback catch.
Clears audit HIGHs: 'mixed crash/silent missing-node handling' and
'error overlay exists only behind SWIFLOW_DEV'."
```

---

### Task 3: hmrSwap — reentrancy guard + stale-CSS removal (driver)

A second `hmr-swap` arriving mid-swap runs concurrently (interleaved `nodes.clear()` against a still-mounting module), and injected `<style id="swiflow-*">` elements are never removed, so `scopedStyles` edits show stale CSS until manual reload (audit Unit 4 HIGH).

**Files:**
- Modify: `js-driver/swiflow-driver.js` (`hmrSwap`)
- Test: `js-driver/test/hmr-swap.test.js`

- [ ] **Step 1: Write the failing jsdom tests**

In `js-driver/test/hmr-swap.test.js`, append two cases (mirror the existing happy-path test's setup — it already uses `window.swiflow.__importOverride` and a fake `init`):

```js
test("hmr-swap removes previously injected swiflow style tags", async () => {
  const style = document.createElement("style");
  style.id = "swiflow-DemoComponent";
  document.head.appendChild(style);
  const userStyle = document.createElement("style");
  userStyle.id = "user-styles";
  document.head.appendChild(userStyle);

  await triggerHmrSwap(); // use the file's existing helper/pattern for firing one swap

  assert.equal(document.getElementById("swiflow-DemoComponent"), null,
    "swiflow-injected styles must be cleared so the new module re-injects fresh CSS");
  assert.ok(document.getElementById("user-styles"),
    "non-swiflow styles must be left alone");
});

test("a second hmr-swap during an in-flight swap is coalesced, not interleaved", async () => {
  let resolveFirstImport;
  let importCalls = 0;
  window.swiflow.__importOverride = () => {
    importCalls++;
    if (importCalls === 1) {
      return new Promise((resolve) => {
        resolveFirstImport = () => resolve({ init: async () => {} });
      });
    }
    return Promise.resolve({ init: async () => {} });
  };

  const first = fireHmrSwapMessage();   // however the file dispatches the ws message / calls hmrSwap
  const second = fireHmrSwapMessage();  // arrives while first awaits import
  resolveFirstImport();
  await first; await second;
  await new Promise((r) => setTimeout(r, 0)); // let the queued swap drain

  assert.equal(importCalls, 2, "second swap runs after the first, not concurrently");
});
```

**Adaptation note:** the exact helper names (`triggerHmrSwap`, `fireHmrSwapMessage`) must match how hmr-swap.test.js already invokes a swap (it may post a fake ws message or call an exported hook). Read the existing test and reuse its mechanism; the assertions above are the contract. If `hmrSwap` isn't directly awaitable from the test, assert on observable state (importCalls ordering) after draining timers/microtasks the way the existing test does.

- [ ] **Step 2: Run to verify failure**

Run: `cd js-driver && npm test`
Expected: style-removal test FAILS (`swiflow-DemoComponent` still present); the coalescing test FAILS (both imports start before the first resolves) or flakes — either failure mode is the bug.

- [ ] **Step 3: Implement guard + CSS cleanup**

In `js-driver/swiflow-driver.js`, above `async function hmrSwap(payload)` add module-level state, and rework the function:

```js
    let hmrInFlight = false;
    let hmrQueuedPayload = null;

    async function hmrSwap(payload) {
      // Reentrancy guard: rapid saves can broadcast a second swap while the
      // first is still awaiting import/init. Running them concurrently
      // interleaves nodes.clear() with a module that is still mounting —
      // coalesce instead: remember the LATEST payload and run it after the
      // in-flight swap finishes (intermediate payloads are superseded).
      if (hmrInFlight) {
        hmrQueuedPayload = payload;
        return;
      }
      hmrInFlight = true;
      const t0 = performance.now();
      try {
        const snapshot =
          window.__swiflow && window.__swiflow.hmrSnapshot
            ? window.__swiflow.hmrSnapshot()
            : null;
        window.__swiflowPendingSnapshot = snapshot;

        // Drop maps + clear DOM mount target via replaceChildren()
        // (no HTML-property writes — matches the driver's XSS-safe
        // contract: setRawHTML is the only intentional HTML-writing
        // site).
        nodes.clear();
        listeners.clear();
        if (mountSelector) {
          const t = document.querySelector(mountSelector);
          if (t) t.replaceChildren();
        }

        // Remove Swiflow-injected <style> tags so the new module's
        // CSSInjector re-injects fresh CSS. Without this, the id-based
        // inject-once skip keeps serving the OLD styles after a
        // scopedStyles edit — the exact workflow HMR exists for. The
        // "swiflow-" id prefix covers component scoped sheets and
        // SwiflowUI's base token sheet; user styles are untouched.
        document.querySelectorAll('style[id^="swiflow-"]').forEach(function (s) {
          s.remove();
        });

        // … keep the existing import/init block byte-identical
        // (importEntry/__importOverride, await init({ module: … }),
        // heap-GC NOTE comment) …

        const dt = (performance.now() - t0).toFixed(1);
        console.log("[swiflow] hmr-swap took " + dt + "ms");
      } catch (e) {
        console.warn(
          "[swiflow] HMR swap failed, falling back to full reload:",
          e
        );
        location.reload();
        return; // reload is in flight; don't drain the queue
      } finally {
        hmrInFlight = false;
      }
      if (hmrQueuedPayload !== null) {
        const next = hmrQueuedPayload;
        hmrQueuedPayload = null;
        hmrSwap(next);
      }
    }
```

(The `// … keep the existing import/init block …` marker means: leave those lines exactly as they are in the file today — they are between the maps-clear and the timing log. Everything else shown is the new shape.)

- [ ] **Step 4: Codegen + run everything**

```bash
swift scripts/embed-driver.swift
for d in examples/*/; do cp js-driver/swiflow-driver.js "$d"; done
swift scripts/embed-templates.swift
cd js-driver && npm test && cd ..
env -u SWIFLOW_SOURCE swift test
```
Expected: jsdom 37 green; Swift suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(driver): hmr-swap reentrancy guard + stale style cleanup

Concurrent swaps are coalesced (latest payload wins after the in-flight
swap completes); swiflow-injected <style> tags are removed on swap so
scopedStyles edits actually show. Clears audit HIGH: 'HMR serves stale
CSS' and MEDIUM: 'hmrSwap has no reentrancy guard'."
```

---

### Task 4: DevCommand — dispatch reload vs hmr-swap by file type

The watcher tracks `["swift", "html", "js"]` but the loop unconditionally rebuilds + broadcasts `hmr-swap`, which never refetches HTML — saving `index.html` does nothing visible. `broadcastReload()` exists with zero production callers.

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/DevCommand.swift` (decision function + loop), `Sources/SwiflowCLI/DevServer/WebSocketHub.swift:4` + `Sources/SwiflowCLI/DevServer/DevServer.swift:6` (stale comments saying DevCommand "calls broadcastReload()" — make them accurate)
- Test: `Tests/SwiflowCLITests/DevCommandTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/SwiflowCLITests/DevCommandTests.swift` (match its existing imports/`@testable import SwiflowCLI`):

```swift
@Suite struct DevChangeDispatchTests {

    private func urls(_ paths: [String]) -> Set<URL> {
        Set(paths.map { URL(fileURLWithPath: $0) })
    }

    @Test func swiftOnlyChangesRebuildAndHMRSwap() {
        let d = DevCommand.changeDispatch(for: urls(["/p/Sources/App/Main.swift"]))
        #expect(d == .init(rebuild: true, broadcast: .hmrSwap))
    }

    @Test func webOnlyChangesReloadWithoutRebuild() {
        let d = DevCommand.changeDispatch(for: urls(["/p/index.html"]))
        #expect(d == .init(rebuild: false, broadcast: .reload))
        let js = DevCommand.changeDispatch(for: urls(["/p/styles.js"]))
        #expect(js == .init(rebuild: false, broadcast: .reload))
    }

    @Test func mixedChangesRebuildAndReload() {
        let d = DevCommand.changeDispatch(
            for: urls(["/p/Sources/App/Main.swift", "/p/index.html"]))
        #expect(d == .init(rebuild: true, broadcast: .reload))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter DevChangeDispatchTests`
Expected: compile failure — `changeDispatch` doesn't exist.

- [ ] **Step 3: Implement the decision + wire the loop**

In `Sources/SwiflowCLI/Commands/DevCommand.swift` add (file scope or inside DevCommand, matching the file's organization):

```swift
    /// What to do for a batch of changed files. Pure — unit-tested directly.
    struct ChangeDispatch: Equatable {
        enum Broadcast: Equatable { case hmrSwap, reload }
        let rebuild: Bool
        let broadcast: Broadcast

        init(rebuild: Bool, broadcast: Broadcast) {
            self.rebuild = rebuild
            self.broadcast = broadcast
        }
    }

    /// Swift edits need a rebuild and can hot-swap the wasm in place.
    /// HTML/JS edits are static-asset changes: the page itself must reload
    /// to refetch them (hmr-swap only re-imports the wasm bundle — it never
    /// refetches index.html). Mixed batches rebuild AND reload, which picks
    /// up both.
    static func changeDispatch(for changed: Set<URL>) -> ChangeDispatch {
        let swiftChanged = changed.contains { $0.pathExtension == "swift" }
        let webChanged = changed.contains { $0.pathExtension != "swift" }
        switch (swiftChanged, webChanged) {
        case (true, false): return .init(rebuild: true, broadcast: .hmrSwap)
        case (true, true):  return .init(rebuild: true, broadcast: .reload)
        default:            return .init(rebuild: false, broadcast: .reload)
        }
    }
```

Rework the watcher loop body (currently: print → rebuild → `broadcastHMRSwap` → print). New shape, preserving the existing rebuild code and the "don't broadcast on failed rebuilds" decision:

```swift
                for await changed in watcher.changes() {
                    let dispatch = Self.changeDispatch(for: changed)
                    print("swiflow: \(dispatch.rebuild ? "rebuilding" : "reloading") (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                    do {
                        if dispatch.rebuild {
                            if let bypassRebuilder {
                                try bypassRebuilder.rebuild(using: rebuildRunner, state: &state)
                            } else {
                                _ = try invocation.run(using: rebuildRunner)
                            }
                        }
                        switch dispatch.broadcast {
                        case .hmrSwap:
                            let bust = Self.wasmCacheBusterSuffix(projectURL: projectURL)
                            await server.hub.broadcastHMRSwap(
                                wasmURL: "/\(Self.packageToJSOutputRelativePath)/App.wasm?h=\(bust)",
                                jsURL: "/\(Self.packageToJSOutputRelativePath)/index.js?h=\(bust)"
                            )
                            print("swiflow: HMR broadcast")
                        case .reload:
                            await server.hub.broadcastReload()
                            print("swiflow: reload broadcast")
                        }
                    } catch {
                        // … keep the existing catch body unchanged …
                    }
                }
```

Also update the lead comment above the watcher setup (currently "On each change, rebuild and broadcast reload (decision §2…)") to describe the per-file-type dispatch, and fix the two stale comments: `WebSocketHub.swift:4` and `DevServer.swift:6` both still claim "DevCommand calls broadcastReload() after each rebuild" — make them say DevCommand dispatches `broadcastHMRSwap()` for Swift-only changes and `broadcastReload()` for HTML/JS changes.

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter "DevChangeDispatchTests|DevCommandTests|WebSocketHub"` → green.
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(dev): dispatch reload vs hmr-swap by changed file type

Saving index.html/JS now broadcasts a page reload (no pointless Swift
rebuild); Swift-only saves keep the hot swap; mixed batches rebuild and
reload. Clears audit HIGH: 'HTML/JS edits trigger a rebuild but never
update the page'."
```

---

### Task 5: Doctor probes what build actually requires

`swiflow doctor` prints "All checks passed." on machines where `swiflow build` immediately fails: it never probes the macOS swift.org toolchain (`MacToolchainProbe` documents the failure mode) nor binaryen's `wasm-opt` (invoked by the PackageToJS plugin for release output).

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/DoctorCommand.swift`
- Test: `Tests/SwiflowCLITests/DoctorReportTests.swift` (create; if a doctor test file already exists, extend it instead)

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowCLITests/DoctorReportTests.swift
import Testing
@testable import SwiflowCLI

@Suite struct DoctorReportTests {

    @Test func failsWhenWasmOptMissing() {
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: .found("org.swift.630"),
            wasmOpt: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("wasm-opt"))
        #expect(report.summary.contains("binaryen"))
    }

    @Test func failsWhenMacToolchainMissing() {
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: .missing,
            wasmOpt: .found("version 118")
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("swift.org toolchain"))
    }

    @Test func macToolchainNotApplicableDoesNotFail() {
        // Linux: the macOS toolchain row is nil — absent from the report
        // and excluded from the exit code.
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: nil,
            wasmOpt: .found("version 118")
        )
        #expect(report.exitCode == 0)
        #expect(!report.summary.contains("mac-toolchain"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter DoctorReportTests`
Expected: compile failure — `DoctorReport` has no `macToolchain`/`wasmOpt`.

- [ ] **Step 3: Extend DoctorReport + probes**

In `Sources/SwiflowCLI/Commands/DoctorCommand.swift`, replace `DoctorReport`:

```swift
struct DoctorReport {
    let swift: ToolStatus
    let wasmSDK: ToolStatus
    /// nil = not applicable on this OS (Linux builds don't need the
    /// swift.org macOS toolchain workaround).
    let macToolchain: ToolStatus?
    let wasmOpt: ToolStatus

    private var applicable: [ToolStatus] {
        [swift, wasmSDK, wasmOpt] + (macToolchain.map { [$0] } ?? [])
    }

    var exitCode: Int32 {
        let allPresent = applicable.allSatisfy {
            if case .missing = $0 { return false }
            return true
        }
        return allPresent ? 0 : 1
    }

    var summary: String {
        var lines: [String] = ["swiflow doctor", ""]
        lines.append(row(name: "swift", status: swift,
                         hint: "Install Swift 6.3 from https://swift.org/install/"))
        lines.append(row(name: "wasm-sdk", status: wasmSDK,
                         hint: "Install the WebAssembly Swift SDK 6.3. See README.md → Prerequisites for the current `swift sdk install …` command (the checksum changes per release)."))
        if let macToolchain {
            lines.append(row(name: "mac-toolchain", status: macToolchain,
                             hint: "Install the swift.org toolchain (https://swift.org/install/) — Xcode's default clang has no WASM backend, so `swiflow build` fails with \"No available targets are compatible with triple 'wasm32-unknown-wasip1'\" without it."))
        }
        lines.append(row(name: "wasm-opt", status: wasmOpt,
                         hint: "Install binaryen (`brew install binaryen`) — the PackageToJS plugin invokes wasm-opt for release builds."))
        lines.append("")
        if exitCode == 0 {
            lines.append("All checks passed.")
        } else {
            lines.append("Some checks failed. Install the missing tools above and run `swiflow doctor` again.")
        }
        return lines.joined(separator: "\n")
    }

    private func row(name: String, status: ToolStatus, hint: String) -> String {
        switch status {
        case .found(let detail):
            return "  ✓ \(name)  (\(detail))"
        case .missing:
            return "  ✗ \(name)\n      \(hint)"
        }
    }
}
```

In `DoctorCommand.run()`, build the report with the two new probes:

```swift
    func run() async throws {
        let report = DoctorReport(
            swift: probeSwift(),
            wasmSDK: probeWasmSDK(),
            macToolchain: probeMacToolchain(),
            wasmOpt: probeWasmOpt()
        )
        print(report.summary)
        if report.exitCode != 0 {
            throw ExitCode(report.exitCode)
        }
    }

    /// macOS only: `swiflow build` needs the swift.org toolchain's clang for
    /// the wasm triple (see MacToolchainProbe's header comment). On Linux
    /// the row is not applicable.
    private func probeMacToolchain() -> ToolStatus? {
        #if os(macOS)
        if let bundleID = MacToolchainProbe.swiftLatestBundleIdentifier() {
            return .found(bundleID)
        }
        return .missing
        #else
        return nil
        #endif
    }

    private func probeWasmOpt() -> ToolStatus {
        guard let out = try? captureOutput("wasm-opt", ["--version"]) else { return .missing }
        let firstLine = out.split(separator: "\n").first.map(String.init) ?? ""
        return .found(firstLine)
    }
```

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter "DoctorReportTests|Doctor"` → green (extend any existing doctor tests that construct `DoctorReport` with the old 2-field initializer — give them `macToolchain: nil, wasmOpt: .found("test")` or whatever keeps their original intent).
Run: `swift run swiflow doctor` (manual sanity, this machine has everything) → 4 rows, "All checks passed."
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(doctor): probe the macOS swift.org toolchain and wasm-opt

doctor now checks what build actually requires instead of passing on
machines where swiflow build immediately fails. Clears audit HIGH:
'doctor doesn't check what build/dev actually require'."
```

---

### Task 6: CHANGELOG + audit bookkeeping

**Files:**
- Modify: `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md`

- [ ] **Step 1: CHANGELOG entries**

Under `## [Unreleased]` (exists; merge into its sections, matching style):

```markdown
### Fixed

- **Service worker updates.** `swiflow build` now stamps a per-build tag into
  `swiflow-sw.js`, so browsers detect new deploys and refresh the offline
  cache (previously returning visitors were pinned to the first deploy).
- **Dev loop:** editing HTML/JS now reloads the page (previously only a wasm
  hot-swap was broadcast and HTML edits never appeared); rapid saves no
  longer race the hot-swap; editing `scopedStyles` no longer shows stale CSS
  after a hot-swap.
- **Driver resilience:** a single failing patch no longer aborts the rest of
  the frame, and driver/boot errors are `console.error`'d in production
  builds (previously dev-only).
- **`swiflow doctor`** now probes the macOS swift.org toolchain and
  binaryen's `wasm-opt` — the two missing pieces that made builds fail on
  machines where doctor passed.
```

- [ ] **Step 2: Audit annotations**

In `docs/reviews/2026-06-10-quality-audit.md`, append ` **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**` to:
- Unit 11 CRITICAL "Service worker has no update trigger…"
- Unit 11 HIGH "Missing-node handling is mixed crash/silent…"
- Unit 11 HIGH "Error overlay + RAF try/catch exist only behind `SWIFLOW_DEV`…"
- Unit 4 HIGH "HMR serves stale CSS…"
- Unit 3 (SwiflowCLI) HIGH "HTML/JS edits trigger a rebuild but never update the page…"
- Unit 3 (SwiflowCLI) HIGH "`swiflow doctor` doesn't check what `build`/`dev` actually require…"
- Unit 11 MEDIUM "`hmrSwap` has no reentrancy guard" and MEDIUM "Dead catch around `fetchWithProgress`" (same annotation).

Update the tally table: js-driver Critical 1→0 and High 2→0 and Medium 4→2; SwiflowDOM High 4→3; SwiflowCLI High 2→0; Total row Critical 1→0, High 14→9, Medium 40→38.

- [ ] **Step 3: Final verification + commit**

```bash
env -u SWIFLOW_SOURCE swift test          # full suite green
cd js-driver && npm test && cd ..         # jsdom suite green
git add CHANGELOG.md docs/reviews/2026-06-10-quality-audit.md
git commit -m "docs: changelog + audit bookkeeping for dev-loop/delivery round"
```

---

## Verification (end-to-end)

1. `env -u SWIFLOW_SOURCE swift test` — full host suite green.
2. `cd js-driver && npm test` — jsdom suite green (37 cases).
3. Freshness: `env -u SWIFLOW_SOURCE swift test --filter "DriverEmbedderTests|TemplateEmbedderTests"` — embedded copies match `js-driver/` byte-for-byte; `git diff --stat examples/` shows all 6 examples' driver+sw refreshed.
4. Manual (requires wasm toolchain): `cd examples/TodoCRUD && swiflow build` twice with a Swift edit between — `swiflow-sw.js` bytes differ between the two builds (the stamped tag changed); `grep BUILD_TAG examples/TodoCRUD/swiflow-sw.js` shows a hash, not the placeholder.
5. Manual dev-loop (optional): `swiflow dev` in an example; edit `index.html` → page reloads; edit a `.swift` file → hot-swap; edit `scopedStyles` → new styles appear after swap.

## Out of scope (deliberately)

- Multi-root HMR state loss + dev surfaces in release wasm (SwiflowDOM Highs — next round; need a `-D` flag design).
- Doctor's duplicated process-spawning/SDK-match semantics (Mediums) — only the missing probes are added here.
- `animateExit` JS-side test, SW `message` handler/skipWaiting UX, URLSanitizer/Query/Router/Macro/UI Highs — separate rounds.
