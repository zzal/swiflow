// js-driver/test/regions/serialize-detail.test.js
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupDriver } from "../helpers.js";

describe("serializeEvent forwards object detail (regions)", () => {
  test("object detail on a CustomEvent is forwarded as a JSON string", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let payload = null;
    window.__swiflowDispatch = (_id, p) => { payload = p; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "sf-region" },
      { op: "addHandler", handle: 1, event: "sf:event", handlerId: 7 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("sf-region").dispatchEvent(
      new window.CustomEvent("sf:event", { detail: { kind: "select", id: 9 } })
    );
    assert.equal(payload.type, "sf:event");
    assert.equal(payload.detail, JSON.stringify({ kind: "select", id: 9 }));
    done();
  });

  test("a numeric detail (ordinary click) is NOT forwarded", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let payload = null;
    window.__swiflowDispatch = (_id, p) => { payload = p; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 8 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("button").click(); // click detail is a number
    assert.equal(payload.type, "click");
    assert.equal(payload.detail, null);
    done();
  });
});
