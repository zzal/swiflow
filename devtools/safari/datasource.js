// Safari encapsulation — reads window.__swiflow.* through a messaging bridge.
// chrome.devtools.inspectedWindow.eval natively crashes Safari's Web Inspector
// (confirmed on Safari 26.5, even for a trivial `1 + 1`), so the panel can't
// touch the page directly. Instead the request hops:
//
//   this panel  --runtime-->  bridge-sw.js  --tabs-->  bridge-content.js
//               --postMessage-->  bridge-page.js  -->  window.__swiflow
//
// and the reply comes back along the same chain. Each hop tags its own errors,
// so a failure message points at the exact leg that broke.
//
// Note: the background locates the Swiflow tab itself (Safari's
// devtools.inspectedWindow.tabId is -1/unusable), so no tab id is sent here.
//
// Defines the SWIFLOW_DATA_SOURCE contract consumed by panel.js (the core):
//   async tree()      -> { selector: "indented tree string", … }
//   async state(path) -> { field: value, … } | null
//   async perf()      -> { selector: { renders, lastPatchCount, lastRenderMs }, … }
//   async pageInfo()  -> { url, candidates } — which tab the bridge is bound
//                        to, and every tab that could have answered. The
//                        background locates "the Swiflow tab" by scanning, so
//                        with several Swiflow tabs open the panel may be
//                        reading a different page than the inspected one;
//                        pageInfo() is what lets the panel SAY so.
(() => {
  // Updated on every successful reply (the background attaches the binding
  // to each response). pageInfo() reads this cache — the panel calls it
  // right after a successful poll, so it's always at most one reply old.
  let lastBinding = { url: null, candidates: [] };

  async function request(method, args) {
    let resp;
    try {
      resp = await browser.runtime.sendMessage({ __swiflow: true, method, args: args || [] });
    } catch (e) {
      throw new Error("bridge (panel→background): " + (e && e.message ? e.message : e));
    }
    if (!resp) {
      throw new Error("bridge: no response from the background relay (bridge-sw.js not running?).");
    }
    if (!resp.ok) {
      throw new Error(resp.error || "bridge: unknown error");
    }
    lastBinding = {
      url: resp.boundUrl ?? null,
      candidates: Array.isArray(resp.candidates) ? resp.candidates : [],
    };
    return resp.value;
  }

  globalThis.SWIFLOW_DATA_SOURCE = {
    tree()      { return request("tree", []); },
    state(path) { return request("state", [path]); },
    perf()      { return request("perf", []); },
    async pageInfo() { return lastBinding; },
  };
})();
