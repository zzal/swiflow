// js-driver/test/hmr-swap.test.js
//
// Verifies the dev-mode HMR swap actually re-instantiates the app.
// Receiving a {"type":"hmr-swap",...} frame must:
//   1. re-import the new PackageToJS entry (payload.jsURL), and
//   2. call its exported init() with the freshly-built wasm
//      (payload.wasmURL) — which re-runs @main and repopulates the
//      cleared mount target.
//
// Regression guard: the swap previously did `await import(payload.jsURL)`
// WITHOUT calling init(). A PackageToJS index.js only *exports* init; it
// never runs @main on import. So the swap cleared #app and never refilled
// it → blank page. See EmbeddedDriver.swift hmrSwap.
//
// jsdom cannot execute a real dynamic import(), so the driver consults an
// overridable importer seam (window.swiflow.__importOverride) that this
// test stubs with a fake module exporting an init() spy.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

describe("dev-mode HMR swap", () => {

  // Shared DOM + FakeWS factory so all three cases boot identically.
  function makeEnv() {
    let onMessage = null;

    class FakeWS {
      constructor() {}
      addEventListener() {}
      set onmessage(fn) { onMessage = fn; }
      get onmessage() { return onMessage; }
      set onopen(fn) {}
      set onclose(fn) {}
      set onerror(fn) {}
    }

    const dom = new JSDOM(
      "<!DOCTYPE html><html><head></head><body><div id='app'></div></body></html>",
      { url: "http://localhost:3000/", runScripts: "dangerously" }
    );
    dom.window.SWIFLOW_DEV = true;
    dom.window.WebSocket = FakeWS;
    dom.window.__SWIFLOW_SKIP_BOOT = true;
    // `window.performance` is a getter-only accessor on current jsdom/Node, so
    // a plain assignment throws ("Cannot set property … which has only a
    // getter"). Define an own data property to override it deterministically.
    Object.defineProperty(dom.window, "performance", {
      value: { now: () => 0 },
      configurable: true,
      writable: true,
    });
    dom.window.fetch = async (u) => ({
      ok: true,
      headers: { get: () => null },
      body: null,
    });

    let reloaded = false;
    const implSym = Object.getOwnPropertySymbols(dom.window.location)[0];
    dom.window.location[implSym].reload = () => { reloaded = true; };

    const scriptEl = dom.window.document.createElement("script");
    scriptEl.textContent = driverSource;
    dom.window.document.head.appendChild(scriptEl);

    /** Fire a hmr-swap frame and return the onMessage reference. */
    function fireSwap(payload) {
      onMessage({
        data: JSON.stringify(Object.assign({ type: "hmr-swap" }, payload)),
      });
    }

    /** Drain the microtask / timer queue for up to `ticks` turns. */
    async function drain(ticks = 100) {
      for (let i = 0; i < ticks; i++) {
        await new Promise((r) => setTimeout(r, 0));
      }
    }

    return { dom, fireSwap, drain, get reloaded() { return reloaded; } };
  }

  test("hmr-swap frame re-imports the entry AND calls init() with the new wasm", async () => {
    const env = makeEnv();

    // Track fetch URL separately for this case.
    let fetchedURL = null;
    env.dom.window.fetch = async (u) => {
      fetchedURL = u;
      return { ok: true, headers: { get: () => null }, body: null };
    };

    // Stub the ESM importer: jsdom can't run dynamic import(). The fake
    // module mirrors a PackageToJS index.js — it only *exports* init().
    let importedURL = null;
    let initArg = null;
    env.dom.window.swiflow.__importOverride = async (url) => {
      importedURL = url;
      return { init: async (opts) => { initArg = opts; } };
    };

    // Fire the swap frame (onmessage calls hmrSwap without awaiting it).
    env.fireSwap({ wasmURL: "/p/App.wasm?h=42", jsURL: "/p/index.js?h=42" });

    // hmrSwap is async; poll until it resolves one way or the other.
    for (let i = 0; i < 100 && initArg === null && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(env.reloaded, false, "swap must succeed without falling back to full reload");
    assert.equal(importedURL, "/p/index.js?h=42", "must re-import the new entry (payload.jsURL)");
    assert.ok(
      initArg && typeof initArg === "object" && "module" in initArg,
      "must call init({ module }) — re-instantiate the wasm, not merely import the entry"
    );
    assert.equal(
      fetchedURL,
      "/p/App.wasm?h=42",
      "the module handed to init() must be fetched from the NEW wasm URL (payload.wasmURL), not the stale boot WASM_URL"
    );
  });

  test("hmr-swap removes previously injected swiflow style tags", async () => {
    const env = makeEnv();

    // Pre-inject one swiflow-namespaced style and one unrelated user style.
    const style = env.dom.window.document.createElement("style");
    style.id = "swiflow-DemoComponent";
    env.dom.window.document.head.appendChild(style);
    const userStyle = env.dom.window.document.createElement("style");
    userStyle.id = "user-styles";
    env.dom.window.document.head.appendChild(userStyle);

    let initArg = null;
    env.dom.window.swiflow.__importOverride = async () => ({
      init: async (opts) => { initArg = opts; },
    });

    env.fireSwap({ wasmURL: "/p/App.wasm?h=1", jsURL: "/p/index.js?h=1" });

    // Drain until the swap completes.
    for (let i = 0; i < 100 && initArg === null && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(
      env.dom.window.document.getElementById("swiflow-DemoComponent"),
      null,
      "swiflow-injected styles must be cleared so the new module re-injects fresh CSS"
    );
    assert.ok(
      env.dom.window.document.getElementById("user-styles"),
      "non-swiflow styles must be left alone"
    );
  });

  test("hmr-swap tears down the old module: snapshot first, then hmrTeardown, then import", async () => {
    const env = makeEnv();

    // The wasm-installed dev namespace. Order matters and is the contract:
    //   1. hmrSnapshot  — capture @State while the old tree is still alive
    //   2. hmrTeardown  — unmount every root (stops the revalidation interval,
    //                     router listeners, RAF scheduler) so the orphaned
    //                     module can never wake up and resync-remount its old
    //                     UI over the new module's DOM
    //   3. import/init  — boot the new module
    const events = [];
    env.dom.window.__swiflow = {
      hmrSnapshot: () => { events.push("snapshot"); return []; },
      hmrTeardown: () => { events.push("teardown"); },
    };

    let initArg = null;
    env.dom.window.swiflow.__importOverride = async (url) => {
      events.push("import");
      return { init: async (opts) => { initArg = opts; } };
    };

    env.fireSwap({ wasmURL: "/p/App.wasm?h=7", jsURL: "/p/index.js?h=7" });
    for (let i = 0; i < 100 && initArg === null && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(env.reloaded, false, "swap must succeed without falling back to full reload");
    assert.deepEqual(
      events,
      ["snapshot", "teardown", "import"],
      "old module must be torn down AFTER the state snapshot and BEFORE the new module boots"
    );
  });

  test("a namespace with hmrSnapshot but NO hmrTeardown still swaps (old-wasm compat)", async () => {
    const env = makeEnv();

    // A wasm module built before the teardown hook existed installs only
    // hmrSnapshot. The driver's typeof guard must skip the missing hook —
    // and an install-order regression that left teardown out would
    // otherwise only surface as a mid-swap TypeError → full-reload fallback.
    let snapshotCalled = false;
    env.dom.window.__swiflow = {
      hmrSnapshot: () => { snapshotCalled = true; return []; },
    };

    let initArg = null;
    env.dom.window.swiflow.__importOverride = async () => ({
      init: async (opts) => { initArg = opts; },
    });

    env.fireSwap({ wasmURL: "/p/App.wasm?h=9", jsURL: "/p/index.js?h=9" });
    for (let i = 0; i < 100 && initArg === null && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(env.reloaded, false, "missing hmrTeardown must not trigger the full-reload fallback");
    assert.ok(snapshotCalled, "the snapshot must still be taken");
    assert.ok(initArg !== null, "the new module must still be imported and init()ed");
  });

  test("a throwing hmrTeardown does not abort the swap", async () => {
    const env = makeEnv();

    env.dom.window.__swiflow = {
      hmrSnapshot: () => [],
      hmrTeardown: () => { throw new Error("teardown exploded"); },
    };

    let initArg = null;
    env.dom.window.swiflow.__importOverride = async () => ({
      init: async (opts) => { initArg = opts; },
    });

    env.fireSwap({ wasmURL: "/p/App.wasm?h=8", jsURL: "/p/index.js?h=8" });
    for (let i = 0; i < 100 && initArg === null && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(env.reloaded, false, "teardown failure must not trigger the full-reload fallback");
    assert.ok(initArg !== null, "the new module must still be imported and init()ed");
  });

  test("a second hmr-swap during an in-flight swap is coalesced, not interleaved", async () => {
    const env = makeEnv();

    let resolveFirstImport;
    let importCalls = 0;
    env.dom.window.swiflow.__importOverride = () => {
      importCalls++;
      if (importCalls === 1) {
        return new Promise((resolve) => {
          resolveFirstImport = () => resolve({ init: async () => {} });
        });
      }
      return Promise.resolve({ init: async () => {} });
    };

    // Fire TWO swaps back-to-back. The second arrives while the first is
    // awaiting its (deliberately stalled) import.
    env.fireSwap({ wasmURL: "/p/App.wasm?h=1", jsURL: "/p/index.js?h=1" });
    env.fireSwap({ wasmURL: "/p/App.wasm?h=2", jsURL: "/p/index.js?h=2" });

    // Give the event loop one turn so the first hmrSwap enters its await.
    await new Promise((r) => setTimeout(r, 0));

    // Second swap must be queued, not started.
    assert.equal(importCalls, 1, "second swap must be queued while first is in-flight (not started)");

    // Unblock the first import and drain until both swaps have run.
    resolveFirstImport();
    for (let i = 0; i < 100 && importCalls < 2 && !env.reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(importCalls, 2, "queued swap must run after the in-flight swap finishes");
  });
});
