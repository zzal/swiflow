// js-driver/test/build-error.test.js
//
// Audit III Wave-2 #7: compile errors must reach the browser. When the dev
// server broadcasts {"type":"build-error"} after a failed rebuild, the
// driver renders a dismissable full-viewport overlay (the Vite model) —
// without it the browser keeps rendering the last-good page with zero
// staleness indication. The overlay clears on the next successful rebuild
// (an hmr-swap frame) and is manually dismissable.
//
// Same manual-JSDOM setup as dev-reload.test.js: window.WebSocket must be
// faked BEFORE the driver loads.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

const OVERLAY_ID = "__swiflow-build-error-overlay";

/** Boots a dev-mode JSDOM with a fake WebSocket; returns { dom, send }
 * where send(payload) delivers a WS frame to the driver's onmessage. */
function bootDevDom() {
  let onMessage = null;

  class FakeWS {
    constructor(url) {}
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

  const scriptEl = dom.window.document.createElement("script");
  scriptEl.textContent = driverSource;
  dom.window.document.head.appendChild(scriptEl);

  return {
    dom,
    send: (payload) => onMessage({ data: JSON.stringify(payload) }),
  };
}

describe("build-error overlay", () => {

  test("a build-error frame renders the overlay with the compiler output", () => {
    const { dom, send } = bootDevDom();
    const diagnostics = "App.swift:7:9: error: cannot find 'oops' in scope";
    send({ type: "build-error", message: diagnostics });

    const overlay = dom.window.document.getElementById(OVERLAY_ID);
    assert.ok(overlay, "overlay element must be injected");
    assert.ok(
      overlay.textContent.includes(diagnostics),
      "the compiler output must be visible in the overlay"
    );
  });

  test("compiler output is rendered as text, never as HTML", () => {
    const { dom, send } = bootDevDom();
    send({ type: "build-error", message: "<img src=x onerror=alert(1)>" });

    const overlay = dom.window.document.getElementById(OVERLAY_ID);
    assert.ok(overlay);
    assert.equal(
      overlay.querySelector("img"),
      null,
      "markup in diagnostics must not become elements (textContent-only contract)"
    );
  });

  test("a second build-error replaces the first (no stacking)", () => {
    const { dom, send } = bootDevDom();
    send({ type: "build-error", message: "first failure" });
    send({ type: "build-error", message: "second failure" });

    const overlays = dom.window.document.querySelectorAll(`#${OVERLAY_ID}`);
    assert.equal(overlays.length, 1, "exactly one overlay at a time");
    assert.ok(overlays[0].textContent.includes("second failure"));
    assert.ok(!overlays[0].textContent.includes("first failure"));
  });

  test("the dismiss button removes the overlay", () => {
    const { dom, send } = bootDevDom();
    send({ type: "build-error", message: "boom" });

    const overlay = dom.window.document.getElementById(OVERLAY_ID);
    const button = overlay.querySelector("button");
    assert.ok(button, "overlay must offer a dismiss button");
    button.onclick();

    assert.equal(dom.window.document.getElementById(OVERLAY_ID), null);
  });

  test("a successful rebuild (hmr-swap frame) clears the overlay", () => {
    const { dom, send } = bootDevDom();
    // Fake module import + fetch so the swap kicked off by the frame can
    // run to (irrelevant) completion under jsdom instead of leaking an
    // unhandled rejection after the test ends.
    dom.window.swiflow.__importOverride = () =>
      Promise.resolve({ init: async () => {} });
    dom.window.fetch = async () => ({
      ok: true,
      headers: { get: () => null },
      body: null,
    });

    send({ type: "build-error", message: "mid-edit failure" });
    assert.ok(dom.window.document.getElementById(OVERLAY_ID));

    send({ type: "hmr-swap", wasmURL: "/App.wasm?h=1", jsURL: "/index.js?h=1" });

    // The overlay must clear synchronously on receipt of the swap frame —
    // the broadcast itself means the rebuild succeeded, so this must not
    // wait on the async module import.
    assert.equal(
      dom.window.document.getElementById(OVERLAY_ID),
      null,
      "hmr-swap means the rebuild succeeded — the overlay must clear"
    );
  });

  test("a malformed build-error frame (no message) still renders a labelled overlay", () => {
    const { dom, send } = bootDevDom();
    send({ type: "build-error" });

    const overlay = dom.window.document.getElementById(OVERLAY_ID);
    assert.ok(overlay, "a build failure with no forwarded output still needs a visible signal");
  });
});
