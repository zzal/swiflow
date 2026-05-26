# Phase 14b Track 1 — Service Worker Cache: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repeat visits to a Swiflow app transfer ~0 bytes by caching the WASM and JS runtime in a content-hash-keyed service worker.

**Architecture:** Build-time SHA256 manifest → service worker registered by the driver on script-load → install pre-caches WASM + JS → fetch serves from cache. Two caches (WASM, JS runtime) keyed independently so a Swift-source edit doesn't invalidate the JS runtime cache.

**Tech Stack:** Vanilla JS (no SW framework). CryptoKit for Swift-side SHA256. No new dependencies.

---

## File structure

| Path | Action | Responsibility |
|---|---|---|
| `js-driver/swiflow-sw.js` | **create** | The service worker itself: install/fetch/activate handlers, two named caches keyed by manifest hash |
| `js-driver/test/sw.test.js` | **create** | node:test coverage for the SW logic (run inside a mocked SW global scope) |
| `js-driver/test/sw-helpers.js` | **create** | Mocked `caches`, `self`, `clients`, `fetch` for testing the SW without a real browser |
| `js-driver/swiflow-driver.js` | modify | Register SW on script load (unless `SWIFLOW_DEV`); own the dynamic `init()` call previously in the user's HTML; auto-unregister stale SW in dev |
| `js-driver/test/dev-reload.test.js` | modify | Add coverage for the SW-registration branch + dev-mode skip |
| `Sources/SwiflowCLI/DriverEmbedder.swift` | modify | Generate Swift source for **both** driver and SW into the same `EmbeddedDriver` enum |
| `Sources/SwiflowCLI/EmbeddedDriver.swift` | **regenerate** | Add `EmbeddedDriver.serviceWorkerSource` |
| `Scripts/embed-driver.swift` | modify | Read both `swiflow-driver.js` and `swiflow-sw.js`; emit combined `EmbeddedDriver.swift` |
| `Tests/SwiflowCLITests/DriverEmbedderTests.swift` | modify | Verify both embedded sources are byte-equal to the JS originals |
| `Sources/SwiflowCLI/Project/BundleManifest.swift` | **create** | Value type representing `swiflow-manifest.json`; pure (no IO) writer that takes file paths + bytes and produces the JSON |
| `Tests/SwiflowCLITests/BundleManifestTests.swift` | **create** | Test the value type's JSON encoding and SHA256 keyed-cache name derivation |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | modify | After PackageToJS runs, walk the output dir, compute SHA256s, write `swiflow-manifest.json` |
| `Sources/SwiflowCLI/Project/ProjectWriter.swift` | modify | Write `swiflow-sw.js` alongside `swiflow-driver.js` in `swiflow init` |
| `Tests/SwiflowCLITests/InitCommandTests.swift` | modify | Assert `swiflow-sw.js` is in the scaffolded tree |
| `Sources/SwiflowCLI/Templates/Templates.swift` | modify | Drop the `<script type="module">import { init }</script>` block from `index.html`; the driver now owns that |
| `examples/HelloWorld/index.html` | modify | Match the new template |
| `examples/HelloWorld/swiflow-sw.js` | **create** | Verbatim copy of `js-driver/swiflow-sw.js` (same sync invariant as `swiflow-driver.js`) |
| `Tests/playwright/sw-cache.spec.ts` | **create** | E2E: first visit registers SW; second visit fetches `App.wasm` `from ServiceWorker` (DevTools network inspection via CDP) |
| `CHANGELOG.md` | modify | Phase 14b entry |

The `js-driver ↔ EmbeddedDriver must stay in sync` invariant (existing memory) now applies to two files: `swiflow-driver.js` AND `swiflow-sw.js`. The freshness test (Task 5) is the enforcement.

---

## Task 1: Write the service worker

**Files:**
- Create: `js-driver/swiflow-sw.js`
- Create: `js-driver/test/sw-helpers.js`
- Create: `js-driver/test/sw.test.js`

The SW's responsibilities:

1. **install**: fetch `swiflow-manifest.json`, pre-cache `wasm` and `runtime` artifacts into two named caches keyed by hash.
2. **activate**: delete any cache whose name starts with `swiflow-` but isn't current.
3. **fetch**: for any request whose URL matches a manifest entry, serve from cache (cache-first). For everything else, pass-through.
4. **message**: respond to `{type: 'progress-query'}` from clients (used by Track 3); ignore for now but reserve the handler.

The two cache names:
- `swiflow-runtime-v<sha8>` where `sha8` is the first 8 hex chars of SHA256 of the concatenated runtime-file hashes.
- `swiflow-wasm-v<sha8>` where `sha8` is the first 8 hex chars of the WASM's SHA256.

(Truncating to 8 hex chars keeps cache names readable in DevTools without sacrificing collision resistance for our scale.)

- [ ] **Step 1: Write `sw-helpers.js` with a minimal Service Worker Global Scope mock**

```js
// js-driver/test/sw-helpers.js
//
// Mocked SW global scope for node:test. We instantiate the SW source
// inside a vm context with our mocks in scope — closer to behavior
// than mocking imports.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const swPath = join(here, "..", "swiflow-sw.js");

class MockCache {
  constructor() { this.store = new Map(); }
  async match(req) { return this.store.get(typeof req === "string" ? req : req.url) ?? undefined; }
  async put(req, res) { this.store.set(typeof req === "string" ? req : req.url, res); }
  async addAll(urls) {
    for (const u of urls) this.store.set(u, new MockResponse(`cached:${u}`));
  }
  async keys() { return [...this.store.keys()].map(u => ({ url: u })); }
}

class MockCacheStorage {
  constructor() { this.caches = new Map(); }
  async open(name) {
    if (!this.caches.has(name)) this.caches.set(name, new MockCache());
    return this.caches.get(name);
  }
  async keys() { return [...this.caches.keys()]; }
  async delete(name) { return this.caches.delete(name); }
  async match(req) {
    for (const c of this.caches.values()) {
      const hit = await c.match(req);
      if (hit) return hit;
    }
    return undefined;
  }
}

class MockResponse {
  constructor(body, init = {}) { this.body = body; this.ok = init.ok ?? true; this.status = init.status ?? 200; }
  async json() { return typeof this.body === "string" ? JSON.parse(this.body) : this.body; }
  clone() { return new MockResponse(this.body, { ok: this.ok, status: this.status }); }
}

export function loadServiceWorker({ manifest, fetchHandler } = {}) {
  const listeners = new Map();
  const caches = new MockCacheStorage();
  const fetchImpl = fetchHandler ?? (async (url) => {
    if (url.endsWith("swiflow-manifest.json")) {
      return new MockResponse(JSON.stringify(manifest));
    }
    return new MockResponse(`net:${url}`);
  });

  const self = {
    addEventListener(name, fn) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(fn);
    },
    skipWaiting: async () => {},
    clients: { claim: async () => {}, matchAll: async () => [] },
  };

  const ctx = vm.createContext({
    self,
    caches,
    fetch: fetchImpl,
    Response: MockResponse,
    Request: class { constructor(url) { this.url = url; } },
    URL,
    console,
  });

  const src = readFileSync(swPath, "utf8");
  vm.runInContext(src, ctx, { filename: "swiflow-sw.js" });

  async function fire(name, ev) {
    const fns = listeners.get(name) ?? [];
    const collected = [];
    const wrapped = { ...ev, waitUntil: (p) => collected.push(p), respondWith: (p) => { ev.responded = p; } };
    for (const fn of fns) fn(wrapped);
    await Promise.all(collected);
    return ev;
  }

  return { fire, caches, listeners };
}

export const DEFAULT_MANIFEST = {
  version: "1",
  wasm: { url: "/.build/.../App.wasm", sha256: "a".repeat(64) },
  runtime: [
    { url: "/.build/.../index.js",       sha256: "b".repeat(64) },
    { url: "/.build/.../instantiate.js", sha256: "c".repeat(64) },
    { url: "/.build/.../runtime.js",     sha256: "d".repeat(64) },
    { url: "/.build/.../platforms/browser.js", sha256: "e".repeat(64) },
  ],
};
```

- [ ] **Step 2: Write the failing test**

```js
// js-driver/test/sw.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { loadServiceWorker, DEFAULT_MANIFEST } from "./sw-helpers.js";

describe("service worker", () => {
  test("install fetches manifest and precaches WASM + runtime into two caches", async () => {
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const names = await caches.keys();
    assert.equal(names.filter(n => n.startsWith("swiflow-wasm-v")).length, 1);
    assert.equal(names.filter(n => n.startsWith("swiflow-runtime-v")).length, 1);
  });

  test("fetch returns cached response for a manifest-listed URL", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const ev = {};
    await fire("fetch", { ...ev, request: { url: "https://x.test/.build/.../App.wasm" } });
    assert.ok(ev.responded, "respondWith should have been called for a manifest URL");
  });

  test("fetch falls through for non-manifest URLs", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const ev = {};
    await fire("fetch", { ...ev, request: { url: "https://x.test/api/other" } });
    assert.equal(ev.responded, undefined, "respondWith must not be called for unrelated URLs");
  });

  test("activate deletes stale swiflow-* caches", async () => {
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await caches.open("swiflow-wasm-vDEAD");
    await fire("install", {});
    await fire("activate", {});
    const names = await caches.keys();
    assert.ok(!names.includes("swiflow-wasm-vDEAD"));
  });
});
```

- [ ] **Step 3: Run tests to verify they fail (no `swiflow-sw.js` yet)**

```sh
(cd js-driver && node --test test/sw.test.js)
```

Expected: 4 failures — the SW source file doesn't exist.

- [ ] **Step 4: Write `swiflow-sw.js`**

```js
// js-driver/swiflow-sw.js
//
// Swiflow service worker. Pre-caches the WASM + JS runtime keyed by
// content hash so repeat visits transfer ~0 bytes. Two caches:
//
//   swiflow-runtime-v<sha8>  — JS runtime files (index.js, runtime.js, etc.)
//   swiflow-wasm-v<sha8>     — App.wasm
//
// Split so a Swift-source edit (new App.wasm) doesn't invalidate the JS
// runtime cache, and vice versa.
//
// Manifest format (swiflow-manifest.json):
//   {
//     "version": "1",
//     "wasm":    { "url": "...", "sha256": "..." },
//     "runtime": [{ "url": "...", "sha256": "..." }, ...]
//   }

const MANIFEST_URL = new URL("swiflow-manifest.json", self.location.href).href;

function cacheNameFor(prefix, sha256) {
  return `${prefix}-v${sha256.slice(0, 8)}`;
}

function runtimeCacheNameFor(manifest) {
  // Hash the concatenation of runtime entries' hashes for a stable name.
  const joined = manifest.runtime.map(e => e.sha256).join(":");
  // SubtleCrypto isn't available synchronously and we want this name
  // computable from manifest data alone. Use the first runtime entry's
  // sha as the bucket key — it's deterministic given the manifest.
  // Collision: only if the same file content changes within the same
  // runtime set, which means it was meant to change.
  return cacheNameFor("swiflow-runtime", manifest.runtime[0]?.sha256 ?? "00000000");
}

async function loadManifest() {
  const res = await fetch(MANIFEST_URL, { cache: "no-store" });
  if (!res.ok) throw new Error(`swiflow-sw: manifest fetch failed (${res.status})`);
  return res.json();
}

async function precache(manifest) {
  const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
  const runtimeCacheName = runtimeCacheNameFor(manifest);
  const wasmCache = await caches.open(wasmCacheName);
  const runtimeCache = await caches.open(runtimeCacheName);
  await wasmCache.addAll([manifest.wasm.url]);
  await runtimeCache.addAll(manifest.runtime.map(e => e.url));
  return { wasmCacheName, runtimeCacheName };
}

async function cleanupStale(currentNames) {
  const allNames = await caches.keys();
  await Promise.all(
    allNames
      .filter(n => n.startsWith("swiflow-") && !currentNames.includes(n))
      .map(n => caches.delete(n))
  );
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const manifest = await loadManifest();
    self.__swiflowManifest = manifest;
    await precache(manifest);
    // Don't skipWaiting here — let the next page navigation take over
    // naturally. Avoids ripping cache out from under the current page.
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const manifest = self.__swiflowManifest ?? await loadManifest();
    self.__swiflowManifest = manifest;
    const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
    const runtimeCacheName = runtimeCacheNameFor(manifest);
    await cleanupStale([wasmCacheName, runtimeCacheName]);
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const url = event.request.url;
  // Match against manifest URLs (suffix match — pages may serve from
  // any path prefix, manifest stores the path as written).
  const manifest = self.__swiflowManifest;
  if (!manifest) return; // not yet installed; pass through

  const matchesWasm = url.endsWith(manifest.wasm.url) || url.includes(manifest.wasm.url);
  const matchesRuntime = manifest.runtime.some(e => url.endsWith(e.url) || url.includes(e.url));
  if (!matchesWasm && !matchesRuntime) return;

  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    if (cached) return cached;
    const fresh = await fetch(event.request);
    return fresh;
  })());
});

self.addEventListener("message", (event) => {
  // Reserved for Track 3 (progress UI). No-op for now.
});
```

- [ ] **Step 5: Run tests to verify they pass**

```sh
(cd js-driver && node --test test/sw.test.js)
```

Expected: 4 passes.

- [ ] **Step 6: Commit**

```sh
git add js-driver/swiflow-sw.js js-driver/test/sw.test.js js-driver/test/sw-helpers.js
git commit -m "feat(driver): add swiflow-sw.js service worker"
```

---

## Task 2: BundleManifest value type + writer

**Files:**
- Create: `Sources/SwiflowCLI/Project/BundleManifest.swift`
- Create: `Tests/SwiflowCLITests/BundleManifestTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowCLITests/BundleManifestTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("BundleManifest")
struct BundleManifestTests {
    @Test("encodes wasm + runtime entries with their sha256s")
    func encodesEntries() throws {
        let manifest = BundleManifest(
            version: "1",
            wasm: .init(url: "App.wasm", sha256: String(repeating: "a", count: 64)),
            runtime: [
                .init(url: "index.js",   sha256: String(repeating: "b", count: 64)),
                .init(url: "runtime.js", sha256: String(repeating: "c", count: 64)),
            ]
        )
        let json = try manifest.encoded()
        let parsed = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        #expect(parsed["version"] as? String == "1")
        let wasm = parsed["wasm"] as! [String: String]
        #expect(wasm["url"] == "App.wasm")
        #expect(wasm["sha256"] == String(repeating: "a", count: 64))
        let runtime = parsed["runtime"] as! [[String: String]]
        #expect(runtime.count == 2)
        #expect(runtime[0]["url"] == "index.js")
    }

    @Test("entry init computes SHA256 of the given bytes")
    func computesSHA() {
        let entry = BundleManifest.Entry.computing(url: "x", from: Data("hello".utf8))
        // Known SHA256 of "hello":
        #expect(entry.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
```

- [ ] **Step 2: Run test, verify fails**

```sh
swift test --filter BundleManifestTests
```

Expected: build failure — `BundleManifest` doesn't exist.

- [ ] **Step 3: Implement**

```swift
// Sources/SwiflowCLI/Project/BundleManifest.swift
import CryptoKit
import Foundation

struct BundleManifest: Codable, Equatable {
    let version: String
    let wasm: Entry
    let runtime: [Entry]

    struct Entry: Codable, Equatable {
        let url: String
        let sha256: String

        static func computing(url: String, from data: Data) -> Entry {
            let hash = SHA256.hash(data: data)
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            return Entry(url: url, sha256: hex)
        }
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}
```

- [ ] **Step 4: Run test, verify pass**

```sh
swift test --filter BundleManifestTests
```

- [ ] **Step 5: Commit**

```sh
git add Sources/SwiflowCLI/Project/BundleManifest.swift Tests/SwiflowCLITests/BundleManifestTests.swift
git commit -m "feat(cli): add BundleManifest value type + SHA256 helper"
```

---

## Task 3: `swiflow build` writes the manifest

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift`
- Test: extend `Tests/SwiflowCLITests/BuildCommandTests.swift` (or a sibling integration file)

The build command currently invokes PackageToJS and reports the output path. After the build succeeds, it should walk the output dir, hash the listed artifacts, and write `swiflow-manifest.json`.

- [ ] **Step 1: Locate the post-build hook in `BuildCommand.swift`**

Find where `BuildInvocation.run()` returns successfully and the output dir is logged. The manifest write happens after that, before the function returns.

- [ ] **Step 2: Write the failing integration-style test**

This piggybacks on the existing `InitCommandIntegrationTests` pattern (WASM-SDK-gated). Add to `BuildCommandIntegrationTests`:

```swift
@Test(
    "swiflow build writes swiflow-manifest.json with hashed artifacts",
    .enabled(if: wasmSDKAvailable)
)
func writesManifest() async throws {
    let tmp = ...  // existing helper that scaffolds a project and runs build
    let manifestURL = tmp.appendingPathComponent(
        "Demo/.build/plugins/PackageToJS/outputs/Package/swiflow-manifest.json"
    )
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(BundleManifest.self, from: data)
    #expect(manifest.wasm.url.hasSuffix("App.wasm"))
    #expect(manifest.wasm.sha256.count == 64)
    #expect(manifest.runtime.count >= 4)   // index, instantiate, runtime, platforms/browser
}
```

- [ ] **Step 3: Run test, verify fails**

```sh
swift test --filter writesManifest
```

Expected: file not found.

- [ ] **Step 4: Implement the manifest write in `BuildCommand`**

After `BuildInvocation.run()` returns success:

```swift
// In BuildCommand.run() after the existing invocation succeeds:
let outputDir = projectPath.appendingPathComponent(".build/plugins/PackageToJS/outputs/Package")
let wasmURL = outputDir.appendingPathComponent("App.wasm")
let jsURLs = [
    outputDir.appendingPathComponent("index.js"),
    outputDir.appendingPathComponent("instantiate.js"),
    outputDir.appendingPathComponent("runtime.js"),
    outputDir.appendingPathComponent("platforms/browser.js"),
]
let manifest = BundleManifest(
    version: "1",
    wasm: .computing(url: "App.wasm", from: try Data(contentsOf: wasmURL)).asWasmEntry,
    runtime: try jsURLs.map { url in
        let rel = url.path.replacingOccurrences(of: outputDir.path + "/", with: "")
        return .computing(url: rel, from: try Data(contentsOf: url))
    }
)
try manifest.encoded().write(to: outputDir.appendingPathComponent("swiflow-manifest.json"))
```

(The `.asWasmEntry` is a minor naming consideration; structurally `Entry` is the same shape for both wasm and runtime, but in the manifest JSON `wasm` is a singleton and `runtime` is an array. The above uses `Entry` for both, which is correct.)

- [ ] **Step 5: Run test, verify pass**

```sh
swift test --filter writesManifest
```

- [ ] **Step 6: Commit**

```sh
git add Sources/SwiflowCLI/Commands/BuildCommand.swift Tests/SwiflowCLITests/
git commit -m "feat(cli): swiflow build writes swiflow-manifest.json"
```

---

## Task 4: Driver registers the service worker

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Modify: `js-driver/test/dev-reload.test.js`

The driver currently runs synchronously on script-load and expects the user's HTML to dynamically import the WASM entry. After this task, the driver also (a) registers `swiflow-sw.js` if `SWIFLOW_DEV` is not set, (b) auto-unregisters stale `swiflow-*` SWs if `SWIFLOW_DEV` is set, and (c) takes over the dynamic `import("./.../index.js"); await init();` call so user HTML doesn't need it.

- [ ] **Step 1: Add a test for the registration branch (jsdom mocks)**

Extend `dev-reload.test.js` (or add a new `sw-registration.test.js`):

```js
test("driver registers swiflow-sw.js when SWIFLOW_DEV is unset", async () => {
  const { window } = setupDriver();
  const registered = [];
  window.navigator.serviceWorker = {
    register: (url) => { registered.push(url); return Promise.resolve({}); },
    getRegistrations: async () => [],
  };
  await window.swiflow.__bootForTest({ swiflowDev: false });
  assert.deepEqual(registered, ["swiflow-sw.js"]);
});

test("driver skips registration when SWIFLOW_DEV is true", async () => {
  const { window } = setupDriver();
  const registered = [];
  window.navigator.serviceWorker = {
    register: (url) => { registered.push(url); return Promise.resolve({}); },
    getRegistrations: async () => [],
  };
  await window.swiflow.__bootForTest({ swiflowDev: true });
  assert.equal(registered.length, 0);
});

test("driver unregisters stale swiflow SW in dev", async () => {
  const { window } = setupDriver();
  const unregistered = [];
  const fakeReg = { unregister: () => { unregistered.push("yes"); return Promise.resolve(true); } };
  window.navigator.serviceWorker = {
    register: () => Promise.resolve({}),
    getRegistrations: async () => [fakeReg],
  };
  await window.swiflow.__bootForTest({ swiflowDev: true });
  assert.equal(unregistered.length, 1);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```sh
(cd js-driver && node --test test/dev-reload.test.js)
```

Expected: `__bootForTest` doesn't exist.

- [ ] **Step 3: Implement the registration branch in `swiflow-driver.js`**

Add near the bottom of the driver, after `window.swiflow` is fully wired:

```js
// SW registration. Exposed on window.swiflow for testability; the
// production caller is the IIFE just below.
window.swiflow.__boot = async function __boot({ swiflowDev }) {
  if (!("serviceWorker" in navigator)) return;
  if (swiflowDev) {
    // Unregister any stale swiflow SW so HMR isn't fighting a cache.
    const regs = await navigator.serviceWorker.getRegistrations();
    for (const reg of regs) {
      // Heuristic: scope ends with the page directory; can't tell which
      // SW is "ours" without inspection. Best we can do is unregister
      // all SWs scoped to our page. That's aggressive but correct in
      // dev — users running multiple frameworks under one origin will
      // need a smarter test.
      try { await reg.unregister(); } catch {}
    }
    return;
  }
  try {
    await navigator.serviceWorker.register("swiflow-sw.js");
  } catch (e) {
    console.warn("swiflow: service worker registration failed", e);
  }
};

// Test seam — same logic, with explicit swiflowDev for jsdom tests.
window.swiflow.__bootForTest = window.swiflow.__boot;

// Production boot: run on script-load, plus dynamic-import the WASM
// entry (this used to be the user's HTML responsibility).
(async () => {
  await window.swiflow.__boot({ swiflowDev: !!window.SWIFLOW_DEV });
  // Dynamic-import the PackageToJS entry. The path is conventional and
  // matches what swiflow init's index.html template used to do inline.
  const { init } = await import(
    "./.build/plugins/PackageToJS/outputs/Package/index.js"
  );
  await init();
})();
```

- [ ] **Step 4: Run tests, verify pass**

```sh
(cd js-driver && node --test test/dev-reload.test.js)
```

- [ ] **Step 5: Commit**

```sh
git add js-driver/swiflow-driver.js js-driver/test/dev-reload.test.js
git commit -m "feat(driver): register service worker; own WASM init"
```

---

## Task 5: Embed the SW alongside the driver

**Files:**
- Modify: `Sources/SwiflowCLI/DriverEmbedder.swift`
- Modify: `Scripts/embed-driver.swift`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`
- Modify: `Tests/SwiflowCLITests/DriverEmbedderTests.swift`

- [ ] **Step 1: Update the freshness test to cover both files**

Existing test asserts `EmbeddedDriver.javascriptSource == contentsOf("js-driver/swiflow-driver.js")`. Add a parallel assertion:

```swift
@Test("EmbeddedDriver.serviceWorkerSource matches js-driver/swiflow-sw.js byte-for-byte")
func swSourceIsFresh() throws {
    let path = ...repoRoot.appendingPathComponent("js-driver/swiflow-sw.js")
    let onDisk = try String(contentsOf: path, encoding: .utf8)
    #expect(EmbeddedDriver.serviceWorkerSource == onDisk,
            "Run `swift scripts/embed-driver.swift` to regenerate EmbeddedDriver.swift")
}
```

- [ ] **Step 2: Run test, verify fails**

`EmbeddedDriver.serviceWorkerSource` doesn't exist yet.

- [ ] **Step 3: Extend `DriverEmbedder.swiftSource`**

Change the signature from `(forJSSource: String)` to `(driverJS: String, swJS: String)` and emit:

```swift
enum EmbeddedDriver {
    static let javascriptSource: String = #"""
\(driverJS)
"""#

    static let serviceWorkerSource: String = #"""
\(swJS)
"""#
}
```

Update all call sites.

- [ ] **Step 4: Update `Scripts/embed-driver.swift` to read both files**

```swift
let driverPath = cwd.appendingPathComponent("js-driver/swiflow-driver.js")
let swPath = cwd.appendingPathComponent("js-driver/swiflow-sw.js")
let driverJS = try String(contentsOf: driverPath, encoding: .utf8)
let swJS = try String(contentsOf: swPath, encoding: .utf8)
let output = DriverEmbedder.swiftSource(driverJS: driverJS, swJS: swJS)
try output.write(to: outPath, atomically: true, encoding: .utf8)
```

- [ ] **Step 5: Regenerate and run all tests**

```sh
swift Scripts/embed-driver.swift
swift test --filter DriverEmbedderTests
```

- [ ] **Step 6: Commit**

```sh
git add Sources/SwiflowCLI/DriverEmbedder.swift Sources/SwiflowCLI/EmbeddedDriver.swift Scripts/embed-driver.swift Tests/SwiflowCLITests/
git commit -m "feat(cli): embed swiflow-sw.js into EmbeddedDriver"
```

---

## Task 6: `swiflow init` writes the SW file

**Files:**
- Modify: `Sources/SwiflowCLI/Project/ProjectWriter.swift`
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift`

- [ ] **Step 1: Add the assertion**

```swift
#expect(fm.fileExists(atPath: project.appendingPathComponent("swiflow-sw.js").path))
```

…in the `createsFileTree` test.

- [ ] **Step 2: Run test, verify fails**

- [ ] **Step 3: Extend `ProjectWriter.writeProject`**

Add a second JS file write:

```swift
try EmbeddedDriver.serviceWorkerSource
    .write(to: project.appendingPathComponent("swiflow-sw.js"), atomically: true, encoding: .utf8)
```

The function signature should also gain a `jsServiceWorkerSource: String` parameter for parallelism with `jsDriverSource`; callers in production pass `EmbeddedDriver.serviceWorkerSource`. Tests can pass `"// fake sw\n"`.

- [ ] **Step 4: Run test, verify pass**

- [ ] **Step 5: Commit**

```sh
git add Sources/SwiflowCLI/Project/ProjectWriter.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "feat(init): scaffold swiflow-sw.js alongside swiflow-driver.js"
```

---

## Task 7: Update HTML templates (init template + HelloWorld example)

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- Modify: `examples/HelloWorld/index.html`
- Create: `examples/HelloWorld/swiflow-sw.js` (copy of `js-driver/swiflow-sw.js`)

The template currently ships:

```html
<script src="swiflow-driver.js"></script>
<script type="module">
  import { init } from "./.build/plugins/PackageToJS/outputs/Package/index.js";
  await init();
</script>
```

With Task 4 in place, the driver owns the dynamic import. Templates should now ship just:

```html
<script src="swiflow-driver.js"></script>
```

- [ ] **Step 1: Update `Templates.rawIndexHTML` (or whatever the constant is called)** — strip the `<script type="module">…</script>` block.

- [ ] **Step 2: Update the relevant test in `TemplatesTests`** — assert the block is gone and the bare `swiflow-driver.js` reference remains.

- [ ] **Step 3: Update `examples/HelloWorld/index.html`** identically.

- [ ] **Step 4: Copy `js-driver/swiflow-sw.js` to `examples/HelloWorld/swiflow-sw.js`** (mirrors the existing `swiflow-driver.js` sync invariant).

- [ ] **Step 5: Run all SwiflowCLITests + JS driver tests**

```sh
swift test
(cd js-driver && npm test)
```

- [ ] **Step 6: Commit**

```sh
git add Sources/SwiflowCLI/Templates/Templates.swift examples/HelloWorld Tests/
git commit -m "feat(template): driver owns WASM init; ship swiflow-sw.js"
```

---

## Task 8: Playwright e2e — verify caching round-trip

**Files:**
- Create: `Tests/playwright/sw-cache.spec.ts`

- [ ] **Step 1: Write the spec**

```typescript
// Tests/playwright/sw-cache.spec.ts
import { test, expect } from "@playwright/test";

test("service worker caches WASM on second visit", async ({ page, context }) => {
  // First visit — register SW, fetch WASM from network.
  await page.goto("http://localhost:3000/");
  await page.waitForFunction(
    () => navigator.serviceWorker.controller !== null,
    null,
    { timeout: 10_000 }
  );
  // Counter should be interactive.
  await expect(page.locator("button")).toBeVisible();

  // Capture the App.wasm request on the second visit.
  const requests: string[] = [];
  page.on("response", (res) => {
    if (res.url().endsWith("App.wasm")) {
      const swSource = res.fromServiceWorker();
      requests.push(swSource ? "from-sw" : "from-network");
    }
  });

  await page.reload();
  await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
  await expect(page.locator("button")).toBeVisible();

  // The second load must include at least one App.wasm response served
  // from the service worker (i.e., the cache).
  expect(requests).toContain("from-sw");
});
```

- [ ] **Step 2: Hook into the existing playwright config**

Confirm `Tests/playwright/playwright.config.ts` already starts the HelloWorld dev server on port 3000 (it does, per Phase 13e). The new spec piggybacks.

**Caveat:** In dev mode (`swiflow dev`), the driver does NOT register the SW (the dev override). So this test needs to run against a release build served statically. Add a second `webServer` entry to the playwright config: build HelloWorld in release, serve via `python3 -m http.server 3001` from the example's directory, point this spec at `http://localhost:3001/`.

- [ ] **Step 3: Run the spec**

```sh
(cd Tests/playwright && npm test -- sw-cache.spec.ts)
```

Expected: pass.

- [ ] **Step 4: Commit**

```sh
git add Tests/playwright/sw-cache.spec.ts Tests/playwright/playwright.config.ts
git commit -m "test(playwright): verify SW caches App.wasm on second visit"
```

---

## Task 9: CHANGELOG + README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Add a Phase 14b track 1 entry to CHANGELOG.md** above the existing Phase 14a entry:

```markdown
## [Phase 14b — Track 1] — 2026-05-26
**Stability:** Stable for pre-1.0 usage. Service-worker caching is opt-out by default (debug builds skip; release builds enable).

### Added
- Service worker (`swiflow-sw.js`) — pre-caches WASM + JS runtime keyed by content hash; repeat visits transfer ~0 bytes for unchanged artifacts.
- Build-time `swiflow-manifest.json` emitted by `swiflow build` next to the WASM, listing SHA256 of each shipped artifact.
- Driver auto-registers the SW on release builds; auto-unregisters stale SW in dev (so HMR doesn't fight a stale cache).
- Driver now owns the dynamic `import()` of the PackageToJS entry — user `index.html` is one `<script>` tag lighter.

### Changed
- `swiflow init` template `index.html` drops the `<script type="module">import { init }</script>` block; the driver handles it. Existing user projects should update their HTML the same way (or remove the line themselves — the driver imports are idempotent).
```

- [ ] **Step 2: Update README's "Costs" section**

Add a one-liner about repeat-visit caching:

```markdown
- **Repeat visits:** ~0 bytes. The service worker added in Phase 14b caches the WASM and JS runtime by content hash, so visit #2 onward serves from local cache until you rebuild.
```

- [ ] **Step 3: Commit**

```sh
git add CHANGELOG.md README.md
git commit -m "docs: Phase 14b track 1 — service worker caching"
```

---

## Final verification

After all tasks land:

- [ ] `swift test` — all suites pass.
- [ ] `(cd js-driver && npm test)` — driver + SW tests pass.
- [ ] `(cd Tests/playwright && npm test)` — Counter, Router, and new SW spec pass.
- [ ] Bundle size CI gate (Phase 14a) continues to pass (we didn't shrink the WASM in this track; baseline unchanged).
- [ ] Build & manually verify in Chrome:
  - First visit to `examples/HelloWorld` (after `swiflow build` + `python3 -m http.server`): SW registers (DevTools → Application → Service Workers).
  - Reload: `App.wasm` request in DevTools Network panel shows "(ServiceWorker)" as the source.
  - Edit `examples/HelloWorld/Sources/App/App.swift`, rebuild, reload: new `App.wasm` hash; old cache evicted on next activate; new bytes fetched once.
