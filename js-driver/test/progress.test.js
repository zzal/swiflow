// js-driver/test/progress.test.js
//
// Unit tests for fetchWithProgress helper.
//
// The driver is a top-level IIFE that mutates globals, so we load it via
// fs.readFileSync + vm.runInContext (same pattern as sw.test.js / dev-reload.test.js)
// rather than a static import.
//
// Note on Blob: jsdom's Blob.arrayBuffer() is not a function in the jsdom
// version used here, so we inject Node.js's native `Blob` into the vm context
// so that the Response returned by fetchWithProgress has a working arrayBuffer().

import { test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import vm from "node:vm";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = fs.readFileSync(DRIVER_PATH, "utf8");

/**
 * Build a streamed Response whose body is emitted one chunk at a time.
 *
 * @param {Uint8Array[]} chunks
 * @param {number|null} contentLength  Pass null to omit the Content-Length header.
 * @returns {Response}
 */
function streamedResponse(chunks, contentLength) {
  const stream = new ReadableStream({
    async start(controller) {
      for (const c of chunks) {
        controller.enqueue(c);
        await new Promise((r) => setImmediate(r));
      }
      controller.close();
    },
  });
  const headers =
    contentLength != null ? { "Content-Length": String(contentLength) } : {};
  return new Response(stream, { headers });
}

/**
 * Create a fresh jsdom window + vm context with the driver loaded.
 *
 * `ctx.global` is set to `ctx` itself so that vm scripts can use
 * `global.__nextResponse` to pass a mock Response from the outer context.
 *
 * Node.js's native `Blob` (not jsdom's) is injected so that
 * `Response.arrayBuffer()` works on the value returned by fetchWithProgress.
 */
function setupDriver() {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    runScripts: "outside-only",
  });
  const win = dom.window;
  const ctx = vm.createContext({
    window: win,
    document: win.document,
    fetch: win.fetch,
    Response,
    ReadableStream,
    Uint8Array,
    Blob, // Node.js native Blob — jsdom's Blob lacks arrayBuffer()
    MutationObserver: win.MutationObserver,
    setImmediate,
  });
  // Expose the context itself as `global` so vm scripts can reference
  // outer-scope values via ctx.__nextResponse etc.
  ctx.global = ctx;
  vm.runInContext(
    `Object.assign(globalThis, window); window.__SWIFLOW_SKIP_BOOT = true;`,
    ctx
  );
  vm.runInContext(driverSource, ctx);
  return { window: win, ctx };
}

test("fetchWithProgress writes increasing percent when Content-Length known", async () => {
  const { window, ctx } = setupDriver();
  const fn = vm.runInContext("window.swiflow.__test_fetchWithProgress", ctx);
  assert.ok(typeof fn === "function");

  ctx.__nextResponse = streamedResponse(
    [new Uint8Array(250), new Uint8Array(250), new Uint8Array(500)],
    1000
  );
  vm.runInContext(
    "fetch = () => Promise.resolve(global.__nextResponse);",
    ctx
  );

  const seen = [];
  const obs = new window.MutationObserver(() => {
    seen.push(window.document.documentElement.dataset.swiflowProgress);
  });
  obs.observe(window.document.documentElement, { attributes: true });

  const res = await fn("any://url");
  obs.disconnect();

  const bytes = new Uint8Array(await res.arrayBuffer());
  assert.equal(bytes.length, 1000);
  assert.equal(
    window.document.documentElement.dataset.swiflowProgress,
    "100"
  );
  const intermediates = seen.filter((v) => v !== "100");
  assert.ok(
    intermediates.length >= 1,
    "expected at least one intermediate percent: " + JSON.stringify(seen)
  );
});

test("fetchWithProgress leaves attribute unset when Content-Length absent until completion", async () => {
  const { window, ctx } = setupDriver();
  const fn = vm.runInContext("window.swiflow.__test_fetchWithProgress", ctx);

  ctx.__nextResponse = streamedResponse(
    [new Uint8Array(500), new Uint8Array(500)],
    null
  );
  vm.runInContext(
    "fetch = () => Promise.resolve(global.__nextResponse);",
    ctx
  );

  const seen = [];
  const obs = new window.MutationObserver(() => {
    seen.push(window.document.documentElement.dataset.swiflowProgress);
  });
  obs.observe(window.document.documentElement, { attributes: true });

  await fn("any://url");
  obs.disconnect();

  assert.deepEqual(seen, ["100"]);
});

test("fetchWithProgress re-throws on fetch failure without touching the attribute", async () => {
  const { window, ctx } = setupDriver();
  const fn = vm.runInContext("window.swiflow.__test_fetchWithProgress", ctx);

  vm.runInContext(
    'fetch = () => Promise.reject(new Error("network down"));',
    ctx
  );

  await assert.rejects(() => fn("any://url"), /network down/);
  assert.equal(
    window.document.documentElement.dataset.swiflowProgress,
    undefined
  );
});

test("fetchWithProgress throws on non-ok HTTP status with the status code in the message", async () => {
  const { window, ctx } = setupDriver();
  const fn = vm.runInContext("window.swiflow.__test_fetchWithProgress", ctx);

  ctx.__nextResponse = new Response("not found", { status: 404 });
  vm.runInContext(
    "fetch = () => Promise.resolve(global.__nextResponse);",
    ctx
  );

  await assert.rejects(() => fn("any://url"), /404/);
  assert.equal(
    window.document.documentElement.dataset.swiflowProgress,
    undefined
  );
});
