// MAIN-world reader (Safari). Injected into the inspected page by
// bridge-content.js. This is the only script in the chain that can see the
// page's window.__swiflow global. It answers tree()/state()/perf() requests
// that arrive via window.postMessage and posts the result back the same way.
//
// Request:  { __swiflowReq: true, id, method, args }
// Reply:    { __swiflowRes: true, id, ok, value, error }
(() => {
  window.addEventListener("message", (ev) => {
    if (ev.source !== window) return;
    const d = ev.data;
    if (!d || d.__swiflowReq !== true) return;

    let out;
    try {
      const api = window.__swiflow;
      if (!api) {
        out = {
          ok: false,
          error:
            "No Swiflow runtime on this page (window.__swiflow is undefined). Make sure the app is running in dev mode.",
        };
      } else if (typeof api[d.method] !== "function") {
        out = { ok: false, error: "window.__swiflow." + d.method + " is not a function" };
      } else {
        out = { ok: true, value: api[d.method].apply(api, d.args || []) };
      }
    } catch (e) {
      out = { ok: false, error: String(e && e.message ? e.message : e) };
    }

    window.postMessage(
      { __swiflowRes: true, id: d.id, ok: out.ok, value: out.value, error: out.error },
      "*"
    );
  });
})();
