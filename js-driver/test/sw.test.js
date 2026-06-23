// js-driver/test/sw.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import {
  loadServiceWorker,
  DEFAULT_MANIFEST,
  SW_ORIGIN,
  defaultBodyFor,
  sha256Hex,
} from "./sw-helpers.js";

const WASM_ABS = `${SW_ORIGIN}${DEFAULT_MANIFEST.wasm.url}`;

describe("service worker", () => {
  test("install fetches manifest and precaches WASM + runtime into two caches", async () => {
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const names = await caches.keys();
    assert.equal(names.filter(n => n.startsWith("swiflow-wasm-v")).length, 1);
    assert.equal(names.filter(n => n.startsWith("swiflow-runtime-v")).length, 1);
  });

  test("install calls skipWaiting so a rebuilt worker activates on the next reload", async () => {
    const { fire, self } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    let skipped = false;
    self.skipWaiting = async () => { skipped = true; };
    await fire("install", {});
    assert.ok(skipped, "install must call self.skipWaiting() — else a rebuild waits for every old-worker tab to close");
  });

  test("fetch returns cached response for a manifest-listed URL without re-hitting the network", async () => {
    const { fire, fetchLog } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const fetchesAfterInstall = fetchLog.length;
    // Absolute URL — matches the absolute URL stored by precache().
    const ev = await fire("fetch", { request: { url: WASM_ABS, method: "GET" } });
    assert.ok(ev.responded, "respondWith should have been called for a cached URL");
    const res = await ev.responded;
    assert.ok(res, "resolved Response must be truthy");
    assert.equal(res.body, defaultBodyFor(WASM_ABS), "must serve the bytes fetched at install time");
    assert.equal(fetchLog.length, fetchesAfterInstall, "a cache hit must not hit the network again");
  });

  test("fetch falls through for non-manifest URLs", async () => {
    const { fire, fetchLog } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const fetchesAfterInstall = fetchLog.length;
    // This URL happens to contain "/runtime.js" but is NOT in the SW cache —
    // confirms the caches-first design does NOT false-match by substring.
    const ev = await fire("fetch", { request: { url: `${SW_ORIGIN}/api/runtime.js?x=1`, method: "GET" } });
    // respondWith IS called (every GET goes through the caches-first handler),
    // but the resolved response must be the network response, not a cached one.
    assert.ok(ev.responded, "respondWith should be called for every GET");
    const res = await ev.responded;
    assert.ok(res.body.startsWith("net:"), "non-cached URL should resolve to the network response");
    assert.equal(fetchLog.length, fetchesAfterInstall + 1, "fall-through must hit the network");
  });

  test("fetch passes through non-GET requests without calling respondWith", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const ev = await fire("fetch", { request: { url: WASM_ABS, method: "POST" } });
    assert.equal(ev.responded, undefined, "respondWith must not be called for non-GET requests");
  });

  test("activate deletes stale swiflow-* caches", async () => {
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await caches.open("swiflow-wasm-vDEAD");
    await fire("install", {});
    await fire("activate", {});
    const names = await caches.keys();
    assert.ok(!names.includes("swiflow-wasm-vDEAD"), "stale wasm cache must be removed");
  });

  test("cold activate (no prior install in this process) re-loads manifest and cleans stale caches", async () => {
    // Simulate SW process eviction between install and activate by NOT firing
    // install — so self.__swiflowManifest is never set in this context.
    // The activate handler must fetch the manifest itself and still clean up.
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    const currentWasmCache = `swiflow-wasm-v${DEFAULT_MANIFEST.wasm.sha256.slice(0, 8)}`;
    // Pre-populate a stale cache plus a "current" cache that activate should
    // preserve (mirrors what a previous install would have left behind).
    await caches.open("swiflow-wasm-vDEAD");
    await caches.open(currentWasmCache);
    await fire("activate", {});
    const names = await caches.keys();
    assert.ok(!names.includes("swiflow-wasm-vDEAD"), "stale cache must be removed even without prior install");
    assert.ok(names.includes(currentWasmCache), "current wasm cache must survive");
  });

  test("manifest fetch failure causes install to reject", async () => {
    const { fire } = loadServiceWorker({
      manifest: DEFAULT_MANIFEST,
      fetchHandler: async (urlOrReq) => {
        const url = typeof urlOrReq === "string" ? urlOrReq : urlOrReq.url;
        if (url.endsWith("swiflow-manifest.json")) {
          // Return a non-2xx response to trigger the error path.
          return { ok: false, status: 503 };
        }
        return { ok: true, status: 200, body: `net:${url}`, json: async () => ({}) };
      },
    });
    await assert.rejects(
      () => fire("install", {}),
      /manifest fetch failed/,
      "install must reject when the manifest returns a non-2xx status"
    );
  });

  // ── Content verification ──────────────────────────────────────────────────
  //
  // The manifest names each artifact's sha256, and precache() must verify the
  // bytes it actually fetched before caching them under a sha-named cache.
  // Without this, a manifest/outputs desync (e.g. `swiflow dev` overwriting
  // `swiflow build` outputs without rewriting the manifest) poisons the cache
  // with wrong bytes that cleanupStale() then protects forever.

  test("install does NOT cache a file whose bytes mismatch the manifest sha256; fetch falls back to network", async () => {
    const manifest = structuredClone(DEFAULT_MANIFEST);
    manifest.wasm.sha256 = "f".repeat(64); // disk bytes won't hash to this
    const { fire, fetchLog } = loadServiceWorker({ manifest });
    await fire("install", {}); // must resolve — a mismatch skips caching, never fails install
    const fetchesAfterInstall = fetchLog.length;
    const ev = await fire("fetch", { request: { url: WASM_ABS, method: "GET" } });
    const res = await ev.responded;
    assert.ok(res.body.startsWith("net:"), "mismatched artifact must be served from network, not cache");
    assert.equal(fetchLog.length, fetchesAfterInstall + 1, "the poisoned URL must fall through to network");
  });

  test("a mismatched runtime file is skipped while verified files still cache", async () => {
    const manifest = structuredClone(DEFAULT_MANIFEST);
    manifest.runtime[0].sha256 = "f".repeat(64);
    const { fire, fetchLog } = loadServiceWorker({ manifest });
    await fire("install", {});
    const fetchesAfterInstall = fetchLog.length;
    const badAbs = `${SW_ORIGIN}${manifest.runtime[0].url}`;
    const goodAbs = `${SW_ORIGIN}${manifest.runtime[1].url}`;
    const badEv = await fire("fetch", { request: { url: badAbs, method: "GET" } });
    const goodEv = await fire("fetch", { request: { url: goodAbs, method: "GET" } });
    assert.equal(fetchLog.length, fetchesAfterInstall + 1, "only the mismatched URL goes to network");
    assert.equal((await goodEv.responded).body, defaultBodyFor(goodAbs), "verified sibling stays cached");
    assert.ok((await badEv.responded).body.startsWith("net:"));
  });

  test("verified install caches bytes that hash to the manifest sha256 (sanity of the happy path)", async () => {
    // Belt-and-suspenders: DEFAULT_MANIFEST's hashes are computed from the mock
    // bodies, so this asserts the verification logic agrees with node:crypto.
    assert.equal(DEFAULT_MANIFEST.wasm.sha256, sha256Hex(defaultBodyFor(WASM_ABS)));
    const { fire, caches } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const wasmCache = await caches.open(`swiflow-wasm-v${DEFAULT_MANIFEST.wasm.sha256.slice(0, 8)}`);
    const cached = await wasmCache.match(WASM_ABS);
    assert.ok(cached, "verified wasm must be cached");
    assert.equal(cached.body, defaultBodyFor(WASM_ABS));
  });

  test("sw source carries the build-tag placeholder for CLI stamping", () => {
    const src = fs.readFileSync(new URL("../swiflow-service-worker.js", import.meta.url), "utf8");
    assert.ok(src.includes('const BUILD_TAG = "__SWIFLOW_BUILD_TAG__";'));
  });
});
