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

  test("hmr-swap frame re-imports the entry AND calls init() with the new wasm", async () => {
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
      "<!DOCTYPE html><html><body><div id='app'></div></body></html>",
      { url: "http://localhost:3000/", runScripts: "dangerously" }
    );
    dom.window.SWIFLOW_DEV = true;
    dom.window.WebSocket = FakeWS;
    dom.window.__SWIFLOW_SKIP_BOOT = true;
    dom.window.performance = { now: () => 0 };
    // jsdom has no fetch; stub so fetchWithProgress(payload.wasmURL) resolves
    // cleanly (no streaming body → returns the response as-is).
    let fetchedURL = null;
    dom.window.fetch = async (u) => {
      fetchedURL = u;
      return { ok: true, headers: { get: () => null }, body: null };
    };

    // Patch location.reload (non-configurable on the wrapper) so the
    // fallback path can't navigate/crash the runner, and a failed swap is
    // observable.
    let reloaded = false;
    const implSym = Object.getOwnPropertySymbols(dom.window.location)[0];
    dom.window.location[implSym].reload = () => { reloaded = true; };

    // Load the driver — connect() runs synchronously and captures onMessage.
    const scriptEl = dom.window.document.createElement("script");
    scriptEl.textContent = driverSource;
    dom.window.document.head.appendChild(scriptEl);

    // Stub the ESM importer: jsdom can't run dynamic import(). The fake
    // module mirrors a PackageToJS index.js — it only *exports* init().
    let importedURL = null;
    let initArg = null;
    dom.window.swiflow.__importOverride = async (url) => {
      importedURL = url;
      return { init: async (opts) => { initArg = opts; } };
    };

    // Fire the swap frame (onmessage calls hmrSwap without awaiting it).
    onMessage({
      data: JSON.stringify({
        type: "hmr-swap",
        wasmURL: "/p/App.wasm?h=42",
        jsURL: "/p/index.js?h=42",
      }),
    });

    // hmrSwap is async; poll until it resolves one way or the other.
    for (let i = 0; i < 100 && initArg === null && !reloaded; i++) {
      await new Promise((r) => setTimeout(r, 0));
    }

    assert.equal(reloaded, false, "swap must succeed without falling back to full reload");
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
});
