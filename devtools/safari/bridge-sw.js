// Background relay (Safari). A DevTools panel can't message a content script
// directly, so this service worker forwards each request from the panel to the
// inspected tab's content script (by tabId) and returns the reply.
//
// Uses the WebExtensions promise model: the onMessage listener RETURNS a promise
// whose resolution becomes the response. Safari does not reliably deliver the
// Chrome-style sendResponse()+`return true` pattern back to a promise-based
// sender, which left the panel seeing "no response from the background relay".
console.log("[swiflow] bridge-sw loaded");

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || msg.__swiflow !== true) return; // not ours → undefined (unhandled)
  console.log("[swiflow] bridge-sw request:", msg.method, "→ tab", msg.tabId);

  return browser.tabs
    .sendMessage(msg.tabId, {
      __swiflowBridge: true,
      method: msg.method,
      args: msg.args || [],
    })
    .then(
      (resp) => {
        console.log("[swiflow] bridge-sw reply:", resp);
        return resp;
      },
      (err) => ({
        ok: false,
        error:
          "bridge (background→content): " +
          (err && err.message ? err.message : err) +
          " — is the inspected page an injectable http(s) page with the content script loaded?",
      })
    );
});
