// Registers the "Swiflow" panel in DevTools / Web Inspector. This file runs in
// the devtools_page context (separate from the panel's own page).
//
// The panel manages its OWN live-polling lifecycle from its document visibility
// (see panel.js). We used to start/stop polling here via panel.onShown/onHidden
// calling swiflowStart/Stop on the panel window — but Safari doesn't reliably
// fire those events or expose the panel window to the devtools_page, so polling
// never started (grey dot, no @State auto-update). Creating the panel is all
// this file needs to do.
chrome.devtools.panels.create(
  "Swiflow",
  "panel-icon.svg",    // bundled, extension-relative path. Chrome tolerates
                       // null here, but Safari resolves iconPath as a URL and
                       // rejects null/invalid paths — which silently aborts
                       // panel creation (no DevTools tab appears).
  "panel.html"
);
