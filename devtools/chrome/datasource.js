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
  // Build a readable message from Chrome's eval exceptionInfo. A page-side throw
  // (isException) puts the message in .value; a DevTools-side failure (isError)
  // puts a printf-style template in .description (e.g. "Operation failed: %s")
  // with its args in .details — substitute them so we don't show a literal "%s".
  function describeException(exc) {
    if (exc.value) return String(exc.value);
    if (exc.description) {
      const details = Array.isArray(exc.details) ? exc.details.slice() : [];
      return exc.description.replace(/%[a-z]/gi, () => (details.length ? String(details.shift()) : ""));
    }
    return String(exc.code || "eval failed");
  }

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
          reject(new Error(describeException(exception)));
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
    // Chrome's eval always runs in the inspected page, so the binding is
    // never ambiguous — exactly one candidate. (Safari's messaging bridge
    // has to LOCATE the page and may report several; see its datasource.)
    pageInfo() {
      return call("location.href").then((url) => ({ url, candidates: [url] }));
    },
  };
})();
