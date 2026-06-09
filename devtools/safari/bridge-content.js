// Content-script relay (Safari, isolated world). Two jobs:
//   1. Inject bridge-page.js into the page's MAIN world — the only place that
//      can see the page's window.__swiflow global. Content scripts run in an
//      isolated world and cannot read page globals.
//   2. Relay requests from the background to that MAIN-world script (via
//      window.postMessage) and return the replies.
//
// Uses the WebExtensions promise model: the onMessage listener returns a promise
// that resolves when the MAIN-world script replies (or on timeout).
(() => {
  // Flip to true to trace relay hops in the page console. Off by default.
  const DEBUG = false;
  const dbg = DEBUG ? (...a) => console.log("[swiflow]", ...a) : () => {};
  dbg("bridge-content loaded @", location.href);

  // 1) Inject the MAIN-world reader. It runs in the page context, sets up its
  //    message listener, then removes its own <script> element.
  try {
    const s = document.createElement("script");
    s.src = browser.runtime.getURL("bridge-page.js");
    s.onload = () => s.remove();
    (document.head || document.documentElement).appendChild(s);
  } catch (e) {
    console.warn("[swiflow] bridge-page injection failed:", e);
  }

  // 2) Correlate MAIN-world replies back to the pending background request.
  let seq = 0;
  const pending = new Map();

  window.addEventListener("message", (ev) => {
    if (ev.source !== window) return;
    const d = ev.data;
    if (!d || d.__swiflowRes !== true) return;
    const resolve = pending.get(d.id);
    if (resolve) {
      pending.delete(d.id);
      resolve({ ok: d.ok, value: d.value, error: d.error });
    }
  });

  browser.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.__swiflowBridge !== true) return;
    dbg("bridge-content request:", msg.method);
    return new Promise((resolve) => {
      const id = ++seq;
      const timer = setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          resolve({
            ok: false,
            error:
              "bridge (content→page): no reply within 2s — bridge-page.js may be blocked by the page's Content-Security-Policy, or window.__swiflow is absent.",
          });
        }
      }, 2000);
      pending.set(id, (res) => {
        clearTimeout(timer);
        resolve(res);
      });
      window.postMessage({ __swiflowReq: true, id, method: msg.method, args: msg.args || [] }, "*");
    });
  });
})();
