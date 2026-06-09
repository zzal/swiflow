// Chrome encapsulation — reads window.__swiflow.* from the inspected page via
// chrome.devtools.inspectedWindow.eval (callback form; works in Chrome).
//
// Defines the SWIFLOW_DATA_SOURCE contract that panel.js (the shared core)
// consumes:
//   async tree()      -> { selector: "indented tree string", … }
//   async state(path) -> { field: value, … } | null
//   async perf()      -> { selector: { renders, lastPatchCount, lastRenderMs }, … }
//
// Safari ships its own messaging-based datasource.js instead — inspectedWindow
// .eval natively crashes Safari's Web Inspector, so it can't be used there.
(() => {
  function call(expr) {
    // Page-side envelope: a try/catch that returns { ok, value, error } so page
    // exceptions and a missing runtime surface as readable errors instead of
    // the API's silent null on failure.
    const wrapped = `
      (() => {
        try {
          if (!window.__swiflow) {
            return { ok: false, error: "No Swiflow runtime detected on this page (window.__swiflow is undefined). Make sure the app is running in dev mode." };
          }
          return { ok: true, value: ${expr} };
        } catch (e) {
          return { ok: false, error: String(e && e.message ? e.message : e) };
        }
      })()
    `;
    return new Promise((resolve, reject) => {
      chrome.devtools.inspectedWindow.eval(wrapped, (result, exception) => {
        if (exception) {
          reject(new Error(String(exception.value || exception.description || exception)));
          return;
        }
        if (!result || !result.ok) {
          reject(new Error((result && result.error) || "Unknown page-side error"));
          return;
        }
        resolve(result.value);
      });
    });
  }

  globalThis.SWIFLOW_DATA_SOURCE = {
    tree()      { return call("window.__swiflow.tree()"); },
    state(path) { return call(`window.__swiflow.state(${JSON.stringify(path)})`); },
    perf()      { return call("window.__swiflow.perf()"); },
  };
})();
