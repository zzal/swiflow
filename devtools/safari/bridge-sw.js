// Background relay (Safari, runs as a background page — see manifest). Forwards
// each panel request to the Swiflow page's content script and returns the reply.
//
// Safari's browser.devtools.inspectedWindow.tabId returns -1 (unusable), so we
// can't address the inspected tab directly the way Chrome does. Instead we LO-
// CATE the Swiflow page: ask each open http(s) tab's content script to read
// window.__swiflow, prefer the active tab, and cache the winner so repeat calls
// (and polling) are cheap. Assumes a single Swiflow app is open — fine for dev;
// with several open it talks to whichever answers first.
//
// Uses the WebExtensions promise model: onMessage RETURNS a promise whose
// resolution becomes the response (Safari doesn't deliver Chrome's
// sendResponse()+`return true` back to a promise-based sender).
// Flip to true to trace each hop in the background console. Off by default —
// at fast poll intervals it logs a request/reply every tick.
const DEBUG = false;
const dbg = DEBUG ? (...a) => console.log("[swiflow]", ...a) : () => {};

dbg("bridge-sw loaded");

let lastGoodTabId = null;

async function relay(method, args) {
  const payload = { __swiflowBridge: true, method, args: args || [] };

  // Fast path: re-use the tab we last got a good answer from.
  if (lastGoodTabId != null) {
    try {
      const resp = await browser.tabs.sendMessage(lastGoodTabId, payload);
      if (resp && resp.ok) return resp;
    } catch (e) {
      lastGoodTabId = null; // tab closed/navigated — fall through to a fresh scan
    }
  }

  let tabs;
  try {
    tabs = await browser.tabs.query({ url: ["http://*/*", "https://*/*"] });
  } catch (e) {
    return { ok: false, error: "bridge (background): tabs.query failed: " + (e && e.message ? e.message : e) };
  }
  tabs.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0)); // active tab first

  let lastErr = "no open http(s) tab has the Swiflow content script + runtime";
  for (const t of tabs) {
    let resp;
    try {
      resp = await browser.tabs.sendMessage(t.id, payload);
    } catch (e) {
      continue; // no content script in this tab (not injectable / not yet loaded)
    }
    if (resp && resp.ok) {
      lastGoodTabId = t.id;
      return resp;
    }
    if (resp && resp.error) lastErr = resp.error; // remember the page-side reason
  }
  return { ok: false, error: "bridge (background→content): " + lastErr };
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.__swiflow !== true) return; // not ours → unhandled
  dbg("bridge-sw request:", msg.method);
  return relay(msg.method, msg.args).then((resp) => {
    dbg("bridge-sw reply:", resp);
    return resp;
  });
});
