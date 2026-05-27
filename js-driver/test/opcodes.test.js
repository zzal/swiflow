// js-driver/test/opcodes.test.js
//
// Unit coverage for the driver's 18 opcodes. Each test starts with a
// fresh jsdom + driver via setupDriver().

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupDriver } from "./helpers.js";

describe("driver opcodes", () => {

  test("createElement + appendChild + mount renders into #app", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createElement", handle: 2, tag: "span" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    const app = document.querySelector("#app");
    assert.equal(app.children.length, 1);
    assert.equal(app.firstElementChild.tagName, "DIV");
    assert.equal(app.firstElementChild.firstElementChild?.tagName, "SPAN");
  });

  test("createText creates a Text node addressable by handle", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "p" },
      { op: "createText", handle: 2, text: "hello" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("p").textContent, "hello");
  });

  test("createRawHTML installs parsed HTML as a single subtree", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createRawHTML", handle: 2, html: "<b>bold</b><i>italic</i>" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    const div = document.querySelector("div");
    assert.match(div.innerHTML, /<b>bold<\/b>.*<i>italic<\/i>/);
  });

  test("destroyNode drops the map entry; re-destroying is a no-op", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createElement", handle: 2, tag: "span" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("div").children.length, 1);
    swiflow.applyPatches([{ op: "destroyNode", handle: 2 }]);
    swiflow.applyPatches([{ op: "destroyNode", handle: 2 }]);
    // No DOM-removal assertion — destroyNode drops the driver's map
    // entry only. removeChild is what removes from DOM.
  });

  test("insertBefore places a child before a reference child", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "ul" },
      { op: "createElement", handle: 2, tag: "li" },
      { op: "createElement", handle: 3, tag: "li" },
      { op: "createElement", handle: 4, tag: "li" },
      { op: "setAttribute", handle: 2, name: "data-id", value: "a" },
      { op: "setAttribute", handle: 3, name: "data-id", value: "b" },
      { op: "setAttribute", handle: 4, name: "data-id", value: "c" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "appendChild", parent: 1, child: 3 },
      // After: [a, b]. Now insert c before b.
      { op: "insertBefore", parent: 1, child: 4, beforeChild: 3 },
    ]);
    swiflow.mount(1, "#app");
    const ul = document.querySelector("ul");
    assert.equal(ul.children.length, 3);
    // Order must be [a, c, b] — would fail if insertBefore silently
    // fell through to appendChild (which would produce [a, b, c]).
    const ids = Array.from(ul.children).map(li => li.getAttribute("data-id"));
    assert.deepEqual(ids, ["a", "c", "b"]);
  });

  test("removeChild removes the node from its parent in the DOM", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "ul" },
      { op: "createElement", handle: 2, tag: "li" },
      { op: "appendChild", parent: 1, child: 2 },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("ul").children.length, 1);
    swiflow.applyPatches([{ op: "removeChild", parent: 1, child: 2 }]);
    assert.equal(document.querySelector("ul").children.length, 0);
  });

  test("setAttribute + removeAttribute round-trip", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "a" },
      { op: "setAttribute", handle: 1, name: "href", value: "/somewhere" },
      { op: "setAttribute", handle: 1, name: "title", value: "go there" },
    ]);
    swiflow.mount(1, "#app");
    const a = document.querySelector("a");
    assert.equal(a.getAttribute("href"), "/somewhere");
    assert.equal(a.getAttribute("title"), "go there");
    swiflow.applyPatches([{ op: "removeAttribute", handle: 1, name: "title" }]);
    assert.equal(a.getAttribute("title"), null);
  });

  test("setProperty assigns directly (e.g. input.value)", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "input" },
      { op: "setProperty", handle: 1, name: "value", value: "typed" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("input").value, "typed");
  });

  test("removeProperty removes a JS own-property set via setProperty", () => {
    // Note: removeProperty uses `delete node[name]`. For IDL-backed properties
    // like input.value the delete call is a no-op in both browsers and jsdom
    // (the property is defined on the prototype). We test with a plain JS
    // property (__custom__) which behaves consistently.
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "setProperty", handle: 1, name: "__custom__", value: "set" },
      { op: "removeProperty", handle: 1, name: "__custom__" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("#app > div").__custom__, undefined);
  });

  test("setStyle + removeStyle round-trip on inline style", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "setStyle", handle: 1, name: "color", value: "red" },
      { op: "setStyle", handle: 1, name: "background", value: "white" },
    ]);
    swiflow.mount(1, "#app");
    // Use "#app > div" — querySelector("div") would match the outer #app div,
    // not the created element mounted inside it.
    const div = document.querySelector("#app > div");
    assert.equal(div.style.color, "red");
    assert.equal(div.style.background, "white");
    swiflow.applyPatches([{ op: "removeStyle", handle: 1, name: "color" }]);
    assert.equal(div.style.color, "");
  });

  test("setText updates a text node's data", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "p" },
      { op: "createText", handle: 2, text: "before" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "setText", handle: 2, text: "after" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("p").textContent, "after");
  });

  test("setRawHTML replaces a node's inner HTML wholesale", () => {
    const { swiflow, document } = setupDriver();
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "createRawHTML", handle: 2, html: "<b>v1</b>" },
      { op: "appendChild", parent: 1, child: 2 },
      { op: "setRawHTML", handle: 2, html: "<i>v2</i>" },
    ]);
    swiflow.mount(1, "#app");
    assert.match(document.querySelector("div").innerHTML, /<i>v2<\/i>/);
  });

  test("addHandler installs a listener that calls __swiflowDispatch", (t, done) => {
    const { swiflow, window, document } = setupDriver();
    let receivedHandlerId = null;
    let receivedPayload = null;
    window.__swiflowDispatch = (id, payload) => {
      receivedHandlerId = id;
      receivedPayload = payload;
    };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 42 },
    ]);
    swiflow.mount(1, "#app");
    document.querySelector("button").click();
    assert.equal(receivedHandlerId, 42);
    assert.equal(receivedPayload.type, "click");
    done();
  });

  test("removeHandler detaches the listener so subsequent events don't dispatch", () => {
    const { swiflow, window, document } = setupDriver();
    let callCount = 0;
    window.__swiflowDispatch = () => { callCount += 1; };
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "button" },
      { op: "addHandler", handle: 1, event: "click", handlerId: 1 },
    ]);
    swiflow.mount(1, "#app");
    const btn = document.querySelector("button");
    btn.click();
    assert.equal(callCount, 1);
    swiflow.applyPatches([{ op: "removeHandler", handle: 1, event: "click" }]);
    btn.click();
    assert.equal(callCount, 1, "After removeHandler the listener should NOT fire");
  });

  test("replaceMount swaps the current root child of the selector target", () => {
    const { swiflow, document } = setupDriver();
    // First mount: handle 1 (HomePage div) under #app.
    swiflow.applyPatches([
      { op: "createElement", handle: 1, tag: "div" },
      { op: "setAttribute", handle: 1, name: "class", value: "swiflow-HomePage" },
    ]);
    swiflow.mount(1, "#app");
    assert.equal(document.querySelector("#app").firstElementChild.className, "swiflow-HomePage");

    // Re-render swaps to handle 2 (AboutPage div). Per the contract, the
    // new root's createElement patches precede replaceMount, and the old
    // root's destroyNode patches follow.
    swiflow.applyPatches([
      { op: "createElement", handle: 2, tag: "div" },
      { op: "setAttribute", handle: 2, name: "class", value: "swiflow-AboutPage" },
      { op: "replaceMount", selector: "#app", newHandle: 2 },
      { op: "destroyNode", handle: 1 },
    ]);
    const app = document.querySelector("#app");
    assert.equal(app.children.length, 1);
    assert.equal(app.firstElementChild.className, "swiflow-AboutPage");
  });

  test("replaceMount throws when selector target is missing", () => {
    const { swiflow } = setupDriver();
    swiflow.applyPatches([{ op: "createElement", handle: 1, tag: "div" }]);
    assert.throws(
      () => swiflow.applyPatches([{ op: "replaceMount", selector: "#missing", newHandle: 1 }]),
      /replaceMount target '#missing' not found/
    );
  });
});
