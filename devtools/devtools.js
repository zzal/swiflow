// Registers the "Swiflow" panel in Chrome DevTools. This file runs in
// the devtools_page context — separate from the panel's own context.
// chrome.devtools.panels.create returns the panel handle but we don't
// currently need to attach any cross-context listeners here; all data
// flow happens inside panel.js via the chrome.devtools.inspectedWindow API.
chrome.devtools.panels.create(
  "𝕊𝔽 Devtool",
  null,                // no icon path for MVP
  "panel.html",
  () => {
    // Panel created. Nothing to do here yet.
  }
);
