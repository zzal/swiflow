// js-driver/test/regions/element.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { SfRegion } from "../../swiflow-regions.js";

class FakeWorker {
  constructor() { this.posted = []; this.terminated = false; this.onmessage = null; }
  postMessage(msg, _transfer) { this.posted.push(msg); }
  terminate() { this.terminated = true; }
  _send(msg) { this.onmessage?.({ data: msg }); } // simulate worker → host
}

function mountRegion() {
  const dom = new JSDOM(`<!DOCTYPE html><div id="app"></div>`, { runScripts: "outside-only" });
  const { window } = dom;
  const workers = [];
  SfRegion.install(window, {
    makeWorker: () => { const w = new FakeWorker(); workers.push(w); return w; },
    makeCanvas: () => ({ transferControlToOffscreen: () => ({ _offscreen: true }) }),
    schedule: (cb) => cb(),
    observeSize: () => ({ disconnect() {} }),
    observeVisible: () => ({ disconnect() {} }),
  });
  const el = window.document.createElement("sf-region");
  el.setAttribute("data-source", "regions/scene.js");
  el.sfProps = JSON.stringify({ count: 1 });
  window.document.getElementById("app").appendChild(el);
  return { window, el, workers };
}

describe("SfRegion element", () => {
  test("connecting spawns a worker and posts init with source + props + size", () => {
    const { workers } = mountRegion();
    assert.equal(workers.length, 1);
    const init = workers[0].posted.find((m) => m.kind === "init");
    assert.ok(init, "expected an init message");
    assert.equal(init.payload.source, "regions/scene.js");
    assert.equal(init.payload.props, JSON.stringify({ count: 1 }));
    assert.ok(init.payload.size && typeof init.payload.size.w === "number");
  });

  test("disconnecting posts destroy and terminates the worker", () => {
    const { el, workers } = mountRegion();
    el.remove();
    assert.ok(workers[0].posted.some((m) => m.kind === "destroy"));
    assert.equal(workers[0].terminated, true);
  });
});
