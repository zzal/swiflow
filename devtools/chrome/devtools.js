// Registers the "Swiflow" panel in Chrome DevTools. This file runs in
// the devtools_page context — separate from the panel's own context.
// chrome.devtools.panels lives here, not in panel.js, so visibility
// events (onShown/onHidden) can only be wired in this file.
//
// Phase 19b adds live polling: on panel.onShown we call swiflowStart
// in the panel window to begin the 250ms perf() poll; on panel.onHidden
// we call swiflowStop. The win reference is cached because onHidden
// doesn't receive a window argument.

chrome.devtools.panels.create(
  "Swiflow",
  null,                // no icon path for MVP
  "panel.html",
  (panel) => {
    let panelWindow = null;
    panel.onShown.addListener((win) => {
      panelWindow = win;
      // swiflowStart is defined in panel.js at module load. The first
      // onShown happens after panel.js has executed, so the function
      // is reliably present.
      if (win.swiflowStart) win.swiflowStart();
    });
    panel.onHidden.addListener(() => {
      if (panelWindow && panelWindow.swiflowStop) panelWindow.swiflowStop();
    });
  }
);
