// Phase 19 panel logic.
//
// The panel runs in a Chrome extension context isolated from the
// inspected page. The bridge is the chrome.devtools.inspectedWindow API,
// which runs a string expression in the inspected page's context and
// returns the JSON-serialized result.
//
// All page-side calls go through DataSource so a future event-driven
// impl (Phase 19b) can swap in without touching the rendering layer.

/**
 * Abstract source of devtools data. Methods resolve to documented
 * shapes or null on failure. Errors are surfaced via the returned
 * Promise rejecting with an Error whose .message is suitable for
 * display in the panel's error region.
 */
class DataSource {
  async tree()      { throw new Error("not implemented"); }
  async state(path) { throw new Error("not implemented"); }
  async perf()      { throw new Error("not implemented"); }
}

/**
 * MVP implementation: queries window.__swiflow.* in the inspected
 * page via the chrome.devtools.inspectedWindow API and returns the
 * JSON-serialized result. Wraps every call in an inline envelope so
 * page-side exceptions surface instead of being silently swallowed.
 */
class InspectedWindowDataSource extends DataSource {
  async tree()      { return this._call("window.__swiflow.tree()"); }
  async state(path) { return this._call(`window.__swiflow.state(${JSON.stringify(path)})`); }
  async perf()      { return this._call("window.__swiflow.perf()"); }

  _call(expr) {
    // Inline envelope: page-side try/catch produces { ok, value, error }.
    // Without this, the underlying chrome.devtools.inspectedWindow API
    // silently returns null on page exceptions and on non-JSON-serializable
    // values.
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
}

const dataSource = new InspectedWindowDataSource();

// Wire the refresh button. Task 5 replaces the console.log with real rendering.
document.getElementById("refresh-btn").addEventListener("click", async () => {
  try {
    const tree = await dataSource.tree();
    console.log("[Swiflow DevTools] tree:", tree);
    const perf = await dataSource.perf();
    console.log("[Swiflow DevTools] perf:", perf);
  } catch (err) {
    console.error("[Swiflow DevTools]", err.message);
  }
});
