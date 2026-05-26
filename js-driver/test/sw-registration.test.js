// js-driver/test/sw-registration.test.js
//
// Verifies the driver's service-worker registration behaviour exposed via
// window.swiflow.__bootForTest({ swiflowDev }).
//
// Each test calls setupDriver() to get a fresh jsdom window, then mocks
// window.navigator.serviceWorker before calling __bootForTest, so the mock
// is in place when __boot reads navigator.serviceWorker.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupDriver } from "./helpers.js";

describe("service worker registration", () => {

  test("driver registers swiflow-sw.js when SWIFLOW_DEV is unset", async () => {
    const { window } = setupDriver();
    const registered = [];
    window.navigator.serviceWorker = {
      register: (url) => { registered.push(url); return Promise.resolve({}); },
      getRegistrations: async () => [],
    };
    await window.swiflow.__bootForTest({ swiflowDev: false });
    assert.deepEqual(registered, ["swiflow-sw.js"]);
  });

  test("driver skips registration when SWIFLOW_DEV is true", async () => {
    const { window } = setupDriver();
    const registered = [];
    window.navigator.serviceWorker = {
      register: (url) => { registered.push(url); return Promise.resolve({}); },
      getRegistrations: async () => [],
    };
    await window.swiflow.__bootForTest({ swiflowDev: true });
    assert.equal(registered.length, 0);
  });

  test("driver unregisters stale swiflow SW in dev", async () => {
    const { window } = setupDriver();
    const unregistered = [];
    const fakeReg = {
      active: { scriptURL: "https://x.test/swiflow-sw.js" },
      unregister: () => { unregistered.push("yes"); return Promise.resolve(true); },
    };
    window.navigator.serviceWorker = {
      register: () => Promise.resolve({}),
      getRegistrations: async () => [fakeReg],
    };
    await window.swiflow.__bootForTest({ swiflowDev: true });
    assert.equal(unregistered.length, 1);
  });

  test("driver does NOT unregister non-swiflow SW in dev", async () => {
    const { window } = setupDriver();
    const unregistered = [];
    const otherReg = {
      active: { scriptURL: "https://x.test/my-pwa-sw.js" },
      unregister: () => { unregistered.push("yes"); return Promise.resolve(true); },
    };
    window.navigator.serviceWorker = {
      register: () => Promise.resolve({}),
      getRegistrations: async () => [otherReg],
    };
    await window.swiflow.__bootForTest({ swiflowDev: true });
    assert.equal(unregistered.length, 0, "non-swiflow SW must not be unregistered");
  });

});
