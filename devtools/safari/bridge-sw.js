// Background relay (Safari, runs as a background page — see manifest). Forwards
// each panel request to the Swiflow page's content script and returns the reply.
//
// Safari's browser.devtools.inspectedWindow.tabId returns -1 (unusable), so we
// can't address the inspected tab directly the way Chrome does. Instead we LO-
// CATE the Swiflow page: ask each open http(s) tab's content script to read
// window.__swiflow, prefer the already-bound tab then the active tab, and cache
// the winner so repeat calls (and polling) are cheap. With several Swiflow tabs
// open we stay bound to one, but every reply carries `boundUrl` + `candidates`
// so the panel can SHOW which page it's reading and warn about the ambiguity
// (a periodic re-scan keeps the candidate list fresh).
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
let lastGoodTabUrl = null;
let lastCandidates = []; // URLs of every tab whose runtime answered ok on the last scan
let lastScanAtMs = 0;

// How long the fast path may skip re-scanning. Only a scan notices a SECOND
// Swiflow tab opening (the fast path talks exclusively to the bound tab), so
// the panel's multi-tab warning is at most this stale.
const RESCAN_INTERVAL_MS = 5000;

// Every successful reply carries which tab it came from (`boundUrl`) and which
// tabs COULD have answered (`candidates`) — the panel renders these so a
// wrong-tab binding is visible instead of silently plausible.
function withBinding(resp) {
  resp.boundUrl = lastGoodTabUrl;
  resp.candidates =
    lastCandidates.length > 0 ? lastCandidates : lastGoodTabUrl ? [lastGoodTabUrl] : [];
  return resp;
}

async function relay(method, args) {
  const payload = { __swiflowBridge: true, method, args: args || [] };

  // Fast path: re-use the tab we last got a good answer from (until a
  // periodic re-scan is due).
  const scanDue = Date.now() - lastScanAtMs >= RESCAN_INTERVAL_MS;
  if (lastGoodTabId != null && !scanDue) {
    try {
      const resp = await browser.tabs.sendMessage(lastGoodTabId, payload);
      if (resp && resp.ok) return withBinding(resp);
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
  // Prefer the already-bound tab (binding stability — the panel shouldn't
  // flip trees because the user focused another Swiflow tab), then the
  // active tab for the initial bind.
  const rank = (t) => (t.id === lastGoodTabId ? 2 : 0) + (t.active ? 1 : 0);
  tabs.sort((a, b) => rank(b) - rank(a));

  let lastErr = "no open http(s) tab has the Swiflow content script + runtime";
  const answered = []; // every tab whose runtime answered ok
  for (const t of tabs) {
    let resp;
    try {
      resp = await browser.tabs.sendMessage(t.id, payload);
    } catch (e) {
      continue; // no content script in this tab (not injectable / not yet loaded)
    }
    if (resp && resp.ok) {
      answered.push({ tab: t, resp });
    } else if (resp && resp.error) {
      lastErr = resp.error; // remember the page-side reason
    }
  }
  lastScanAtMs = Date.now();
  if (answered.length > 0) {
    const chosen = answered[0];
    lastGoodTabId = chosen.tab.id;
    lastGoodTabUrl = chosen.tab.url || null;
    lastCandidates = answered.map((a) => a.tab.url || "(unknown url)");
    return withBinding(chosen.resp);
  }
  lastGoodTabId = null;
  lastGoodTabUrl = null;
  lastCandidates = [];
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
