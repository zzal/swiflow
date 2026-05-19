// js-driver/test/helpers.js
//
// Loads swiflow-driver.js inside a fresh jsdom window for each test
// via a <script> tag append. JSDOM with runScripts: "dangerously"
// executes the script synchronously upon append — same code path
// production uses when the page loads the driver. This avoids any
// dynamic-code-construction APIs.

import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DRIVER_PATH = resolve(__dirname, "../swiflow-driver.js");
const driverSource = readFileSync(DRIVER_PATH, "utf8");

/**
 * Creates a fresh jsdom window, loads the driver into it via a
 * <script> tag append, and returns { window, document, swiflow }.
 *
 * For dev-mode tests (those that need the WebSocket reload listener
 * installed via `window.SWIFLOW_DEV = true`), build the JSDOM
 * manually instead of using this helper — the fake WebSocket must
 * be injected onto the window BEFORE the driver loads, which this
 * helper's append-then-return ordering doesn't allow. See
 * dev-reload.test.js for the pattern.
 *
 * @returns {{ window: Window, document: Document, swiflow: any }}
 */
export function setupDriver() {
  const dom = new JSDOM(
    "<!DOCTYPE html><html><body><div id='app'></div></body></html>",
    { url: "http://localhost:3000/", runScripts: "dangerously" }
  );
  const scriptEl = dom.window.document.createElement("script");
  scriptEl.textContent = driverSource;
  dom.window.document.head.appendChild(scriptEl);
  return {
    window: dom.window,
    document: dom.window.document,
    swiflow: dom.window.swiflow,
  };
}
