// Background relay (Safari). A DevTools panel can't message a content script
// directly, so this service worker forwards each request from the panel to the
// inspected tab's content script (by tabId) and passes the reply back.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.__swiflow !== true) return; // not one of ours

  chrome.tabs
    .sendMessage(msg.tabId, {
      __swiflowBridge: true,
      method: msg.method,
      args: msg.args || [],
    })
    .then(
      (resp) => sendResponse(resp),
      (err) =>
        sendResponse({
          ok: false,
          error:
            "bridge (background→content): " +
            (err && err.message ? err.message : err) +
            " — is the inspected page an injectable http(s) page with the content script loaded?",
        })
    );

  return true; // keep the channel open for the async sendResponse
});
