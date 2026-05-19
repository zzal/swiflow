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
 * @param {object} [opts]
 * @param {boolean} [opts.dev=false] — sets window.SWIFLOW_DEV before
 *   the driver loads, so the dev-mode reload listener installs.
 * @returns {{ window: Window, document: Document, swiflow: any }}
 */
export function setupDriver(opts = {}) {
  const dom = new JSDOM(
    "<!DOCTYPE html><html><body><div id='app'></div></body></html>",
    { url: "http://localhost:3000/", runScripts: "dangerously" }
  );
  if (opts.dev) {
    dom.window.SWIFLOW_DEV = true;
  }
  const scriptEl = dom.window.document.createElement("script");
  scriptEl.textContent = driverSource;
  dom.window.document.head.appendChild(scriptEl);
  return {
    window: dom.window,
    document: dom.window.document,
    swiflow: dom.window.swiflow,
  };
}
