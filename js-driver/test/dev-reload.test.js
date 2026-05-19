// js-driver/test/dev-reload.test.js
//
// Verifies that the driver's dev-mode WebSocket reload listener is
// installed when window.SWIFLOW_DEV is set, and that receiving a
// {"type":"reload"} frame triggers location.reload().
//
// Setup must mutate window.WebSocket BEFORE the driver loads, so we
// build the JSDOM window manually here (helpers.js's setupDriver
// loads the driver immediately after constructing the window).

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

describe("dev-mode WebSocket reload", () => {

  test("WebSocket connects to /reload and a reload frame triggers location.reload()", () => {
    let constructedURL = null;
    let onMessage = null;

    class FakeWS {
      constructor(url) { constructedURL = url; }
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

    let reloaded = false;
    // JSDOM makes location.reload non-configurable on the wrapper object, so
    // Object.defineProperty(dom.window.location, "reload", ...) throws.
    // Patch the underlying impl object via the Symbol(impl) key instead —
    // this is the internal object whose method the wrapper delegates to.
    const implSym = Object.getOwnPropertySymbols(dom.window.location)[0];
    dom.window.location[implSym].reload = () => { reloaded = true; };

    // Load the driver via script-tag append — JSDOM with runScripts:
    // "dangerously" executes the script synchronously upon append.
    const scriptEl = dom.window.document.createElement("script");
    scriptEl.textContent = driverSource;
    dom.window.document.head.appendChild(scriptEl);

    assert.match(constructedURL ?? "", /\/reload$/);
    onMessage({ data: JSON.stringify({ type: "reload" }) });
    assert.equal(reloaded, true, "{ type: 'reload' } frame must trigger location.reload()");
  });
});
