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
    schedule: (cb) => queueMicrotask(cb),
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

  test("setting sfProps after connect posts a single coalesced props message", async () => {
    const { el, workers } = mountRegion(); // schedule(cb) runs synchronously in the fixture
    workers[0].posted.length = 0;          // ignore the init burst
    el.sfProps = JSON.stringify({ count: 2 });
    el.sfProps = JSON.stringify({ count: 3 });
    await new Promise((r) => setTimeout(r, 0)); // flush microtask queue
    const props = workers[0].posted.filter((m) => m.kind === "props");
    assert.equal(props.length, 1, "two synchronous sets coalesce to one post");
    assert.equal(props[0].payload, JSON.stringify({ count: 3 }));
  });

  test("worker 'event' becomes a sf:event CustomEvent with parsed detail", () => {
    const { el, workers } = mountRegion();
    let got = null;
    el.addEventListener("sf:event", (e) => { got = e.detail; });
    workers[0]._send({ v: 1, kind: "event", payload: JSON.stringify({ kind: "select", id: 9 }) });
    assert.deepEqual(got, { kind: "select", id: 9 });
  });

  test("worker 'ready' and 'error' map to sf:ready / sf:error", () => {
    const { el, workers } = mountRegion();
    let ready = false, err = null;
    el.addEventListener("sf:ready", () => { ready = true; });
    el.addEventListener("sf:error", (e) => { err = e.detail; });
    workers[0]._send({ v: 1, kind: "ready", payload: { protocol: 1 } });
    workers[0]._send({ v: 1, kind: "error", payload: { code: "init-failed", message: "boom" } });
    assert.equal(ready, true);
    assert.deepEqual(err, { code: "init-failed", message: "boom" });
  });

  test("a size-observer callback posts a resize with device pixels", () => {
    let sizeCb = null;
    const dom = new JSDOM(`<!DOCTYPE html><div id="app"></div>`);
    const { window } = dom;
    const workers = [];
    SfRegion.install(window, {
      makeWorker: () => { const w = new FakeWorker(); workers.push(w); return w; },
      makeCanvas: () => ({ transferControlToOffscreen: () => ({}) }),
      schedule: (cb) => cb(),
      observeSize: (_el, cb) => { sizeCb = cb; return { disconnect() {} }; },
      observeVisible: () => ({ disconnect() {} }),
    });
    const el = window.document.createElement("sf-region");
    el.setAttribute("data-source", "g.js");
    window.document.getElementById("app").appendChild(el);
    workers[0].posted.length = 0;
    sizeCb(640, 480, 2); // device-pixel-content-box already × dpr
    const resize = workers[0].posted.find((m) => m.kind === "resize");
    assert.deepEqual(resize.payload, { w: 640, h: 480, dpr: 2 });
  });
});
