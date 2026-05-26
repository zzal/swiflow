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
    const ev = await fire("fetch", { request: { url: "https://x.test/.build/.../App.wasm" } });
    assert.ok(ev.responded, "respondWith should have been called for a manifest URL");
  });

  test("fetch falls through for non-manifest URLs", async () => {
    const { fire } = loadServiceWorker({ manifest: DEFAULT_MANIFEST });
    await fire("install", {});
    const ev = await fire("fetch", { request: { url: "https://x.test/api/other" } });
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
