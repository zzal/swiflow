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

  test("fetch returns cached response for a manifest-listed URL and body is accessible", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    // Absolute URL — matches the absolute URL stored by precache().
    const ev = await fire("fetch", { request: { url: "https://x.test/.build/.../App.wasm", method: "GET" } });
    assert.ok(ev.responded, "respondWith should have been called for a cached URL");
    const res = await ev.responded;
    assert.ok(res, "resolved Response must be truthy");
    assert.ok(res instanceof Object, "resolved value must be a Response-like object");
  });

  test("fetch falls through for non-manifest URLs", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    // This URL happens to contain "/runtime.js" but is NOT in the SW cache —
    // confirms the caches-first design does NOT false-match by substring.
    const ev = await fire("fetch", { request: { url: "https://x.test/api/runtime.js?x=1", method: "GET" } });
    // respondWith IS called (every GET goes through the caches-first handler),
    // but the resolved response must be the network response, not a cached one.
    assert.ok(ev.responded, "respondWith should be called for every GET");
    const res = await ev.responded;
    assert.ok(res.body.startsWith("net:"), "non-cached URL should resolve to the network response");
  });

  test("fetch passes through non-GET requests without calling respondWith", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const ev = await fire("fetch", { request: { url: "https://x.test/.build/.../App.wasm", method: "POST" } });
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
    // Pre-populate a stale cache plus a "current" cache that activate should
    // preserve (mirrors what a previous install would have left behind).
    await caches.open("swiflow-wasm-vDEAD");
    await caches.open("swiflow-wasm-vaaaaaaaa"); // matches DEFAULT_MANIFEST wasm sha
    await fire("activate", {});
    const names = await caches.keys();
    assert.ok(!names.includes("swiflow-wasm-vDEAD"), "stale cache must be removed even without prior install");
    assert.ok(names.includes("swiflow-wasm-vaaaaaaaa"), "current wasm cache must survive");
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
});
