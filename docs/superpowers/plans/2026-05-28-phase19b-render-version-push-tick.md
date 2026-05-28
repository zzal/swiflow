# Phase 19b — Render-Version Push Tick Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the DevTools panel auto-update on every Swiflow render without manual ↻ Refresh, via per-selector `renders` count polling on the existing `__swiflow.perf()` surface.

**Architecture:** Panel runs a 250 ms `setInterval` while visible, polls `__swiflow.perf()` (cheap — primitive integers), JSON-stringifies the per-selector `renders` counts to a signature string, compares to last seen. On change, calls the same refresh function the ↻ button uses. Poll-time errors are silent (paint live indicator red); manual refresh errors stay loud. Visibility gated via `chrome.devtools.panels.Panel.onShown` / `onHidden`. Zero Swift changes — the render counter already exists.

**Tech Stack:** Vanilla JS (no build step). `chrome.devtools.panels` (visibility events) + the `chrome.devtools.inspectedWindow` API (page queries, via the existing DataSource — same plumbing as Phase 19a).

**Spec:** `docs/superpowers/specs/2026-05-28-phase19b-render-version-push-tick-design.md` (commit `c96689d`)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `devtools/panel.html` | Panel UI shell | Add live-indicator `<span>` to the footer + CSS for its three color states |
| `devtools/panel.js` | Panel logic | Extract existing refresh code into `refreshAll()`; add `setLiveIndicator`, `computePerfSignature`, `pollTick`, `swiflowStart`/`swiflowStop`; preserve manual refresh + navigation handlers untouched |
| `devtools/devtools.js` | Cross-context wiring | Add `panel.onShown` / `panel.onHidden` listeners that call `win.swiflowStart` / `win.swiflowStop` on the cached panel window |
| `devtools/README.md` | User docs | Document auto-update + live indicator; remove "Click ↻ Refresh" from the limitations list |
| `CHANGELOG.md` | Release notes | Phase 19b entry |

Verification is manual after each task (no automated panel-UI tests — Phase 19a's spec accepted this trade-off, and 19b adds no behavior the existing Playwright contract test can verify).

---

## Task 1: Live indicator in the footer

**Files:**
- Modify: `devtools/panel.html`

Adds the visual element that subsequent tasks will drive. Three color states (green = live polling, grey = paused, red = poll failed), no JS yet — Task 2 wires it.

- [ ] **Step 1: Add the indicator markup to the footer**

In `devtools/panel.html`, find the `<footer id="footer"></footer>` line near the end of `<body>`. Replace it with:

```html
    <footer>
      <span id="live-indicator" class="live-indicator live-indicator--grey" title="Paused"></span>
      <span id="footer"></span>
    </footer>
```

The indicator is a sibling of (not a child of) the existing `#footer` text span. The existing `renderFooter()` writes to `#footer`'s `textContent`; keeping the indicator separate prevents `replaceChildren()` from accidentally wiping it.

- [ ] **Step 2: Add the indicator CSS to the `<style>` block**

In the same file, find the existing `footer { ... }` CSS rule. Append these three CSS rules immediately AFTER that block:

```css
      .live-indicator {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        margin-right: 6px;
        vertical-align: middle;
        background: var(--sys-color-on-surface-subtle);
      }
      .live-indicator--green { background: var(--sys-color-primary); }
      .live-indicator--grey  { background: var(--sys-color-on-surface-subtle); }
      .live-indicator--red   { background: var(--sys-color-error); }
```

The base `.live-indicator` rule sets shape + size; the three modifier classes override only the background color.

- [ ] **Step 3: Verify the markup is well-formed**

There's no syntax checker for HTML/CSS that catches semantic issues here, but a quick smoke check:

```bash
grep -c "live-indicator" devtools/panel.html
```
Expected: at least 5 matches.

- [ ] **Step 4: Commit**

```bash
git add devtools/panel.html
git commit -m "$(cat <<'EOF'
feat(devtools): add live-indicator dot to the footer

Phase 19b Task 1: markup + CSS for the small status dot that Task 2
will drive (green = live polling, grey = paused, red = poll failed).
Sibling of the existing #footer text span so renderFooter()'s
replaceChildren() can't accidentally wipe the indicator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Polling loop, signature comparison, start/stop hooks

**Files:**
- Modify: `devtools/panel.js`

The meat of the phase. Refactors the existing inline refresh body into a named `refreshAll()` function (so the poll loop can reuse it), adds the polling machinery, and exposes `window.swiflowStart` / `window.swiflowStop` for the devtools_page to call.

- [ ] **Step 1: Extract the existing refresh body into a named function**

In `devtools/panel.js`, find the existing refresh-btn click handler (currently around line 280):

```js
document.getElementById("refresh-btn").addEventListener("click", async () => {
  clearError();
  try {
    const tree = await dataSource.tree();
    renderTree(tree);
    const perf = await dataSource.perf();
    renderFooter(perf, null);
    if (selectedPath !== null) {
      const state = await dataSource.state(selectedPath);
      renderState(state);
    } else {
      clearState();
    }
  } catch (err) {
    showError(err.message);
  }
});
```

Replace it with the following block (which extracts the body into `refreshAll()`, then wires the click handler to call it):

```js
// ── Refresh ───────────────────────────────────────────────────────────────────
//
// Single source of truth for "re-fetch everything and re-render". Called
// by the ↻ Refresh button (user-driven), the navigation handler, and the
// poll loop. `surfaceErrors` controls whether failures bubble to the
// error region (true for user-initiated, false for poll-driven).

async function refreshAll(surfaceErrors) {
  try {
    const tree = await dataSource.tree();
    renderTree(tree);
    const perf = await dataSource.perf();
    renderFooter(perf, null);
    if (selectedPath !== null) {
      const state = await dataSource.state(selectedPath);
      renderState(state);
    } else {
      clearState();
    }
  } catch (err) {
    if (surfaceErrors) {
      showError(err.message);
    }
    throw err;
  }
}

document.getElementById("refresh-btn").addEventListener("click", async () => {
  clearError();
  try {
    await refreshAll(true);
  } catch (_) {
    // Error already surfaced via showError inside refreshAll.
  }
});
```

Also update the existing navigation handler — it currently does
`document.getElementById("refresh-btn").click()`. That still works
(the click handler now calls `refreshAll(true)`), so no change needed
to the `onNavigated` block.

- [ ] **Step 2: Add the polling block at the end of `devtools/panel.js`**

Append this block to the END of `devtools/panel.js` (after the existing `chrome.devtools.network.onNavigated.addListener(...)` block):

```js
// ── Live polling (Phase 19b) ──────────────────────────────────────────────────
//
// Polls __swiflow.perf() every POLL_INTERVAL_MS while the panel is visible.
// On a change in any selector's `renders` count, runs refreshAll(). Poll-time
// errors are silent — they only paint the live indicator red. Visibility
// gating is driven externally by devtools.js calling swiflowStart/swiflowStop.

const POLL_INTERVAL_MS = 250;
const liveIndicator = document.getElementById("live-indicator");

let pollHandle = null;
let lastPerfSignature = null;

function setLiveIndicator(state, tooltip) {
  liveIndicator.classList.remove(
    "live-indicator--green",
    "live-indicator--grey",
    "live-indicator--red"
  );
  liveIndicator.classList.add(`live-indicator--${state}`);
  liveIndicator.title = tooltip;
}

function computePerfSignature(perf) {
  if (!perf) return "";
  const keys = Object.keys(perf).sort();
  const compact = {};
  for (const k of keys) compact[k] = perf[k].renders;
  return JSON.stringify(compact);
}

async function pollTick() {
  try {
    const perf = await dataSource.perf();
    setLiveIndicator("green", "Live");
    const signature = computePerfSignature(perf);
    if (signature !== lastPerfSignature) {
      lastPerfSignature = signature;
      // refreshAll(false): poll-driven, suppress error-region surfacing.
      // If the refresh itself fails, swallow — pollTick's own catch
      // (below) covers it on the next tick.
      try {
        await refreshAll(false);
      } catch (_) {
        // Silent — handled by the outer catch on the next poll.
      }
    }
  } catch (err) {
    setLiveIndicator("red", `Connection lost: ${err.message}`);
    // Preserve lastPerfSignature: when polling recovers, the next
    // successful tick will see whatever state moved during the outage
    // and trigger a single recovery refresh.
  }
}

window.swiflowStart = () => {
  if (pollHandle !== null) return; // already running
  setLiveIndicator("green", "Live");
  // Kick an immediate refresh so onShown doesn't wait 250ms to populate.
  // lastPerfSignature stays null here; the immediate poll will detect
  // "different" and run refreshAll on the first tick.
  pollHandle = setInterval(pollTick, POLL_INTERVAL_MS);
  pollTick();  // immediate first poll
};

window.swiflowStop = () => {
  if (pollHandle === null) return;
  clearInterval(pollHandle);
  pollHandle = null;
  setLiveIndicator("grey", "Paused (panel hidden)");
};
```

- [ ] **Step 3: Verify the file parses**

Run: `node --check devtools/panel.js`
Expected: no output (clean parse).

- [ ] **Step 4: Verify the existing manual refresh path still works**

Manual smoke check:

1. Sideload-reload the extension at `chrome://extensions`.
2. Open a Swiflow app, open the panel.
3. Click ↻ Refresh. Confirm tree appears as before. (The polling is NOT yet started — Task 3 wires devtools.js to call `swiflowStart`. For now, the indicator stays grey and the manual button is the only way to refresh.)

The indicator remaining grey throughout this task is correct — visibility wiring lands in Task 3.

- [ ] **Step 5: Commit**

```bash
git add devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): poll loop + signature comparison + start/stop hooks

Phase 19b Task 2: extracts the existing refresh body into a named
refreshAll(surfaceErrors) function so it can be shared between the
manual ↻ button (errors loud) and the poll loop (errors silent).

Adds the polling machinery:
- POLL_INTERVAL_MS = 250
- pollTick(): polls __swiflow.perf(), JSON-stringifies a sorted
  per-selector renders map as the signature, compares to last seen,
  triggers refreshAll(false) on diff. Poll-time errors paint the
  live indicator red without surfacing in the error region.
- window.swiflowStart / window.swiflowStop: exposed for devtools.js
  to call from the onShown/onHidden listeners (wired in Task 3).

Indicator stays grey until Task 3 hooks up visibility events. The
manual refresh path is unchanged behaviorally — same fetch sequence,
same error surfacing, just routed through the extracted function.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: devtools.js — visibility wiring

**Files:**
- Modify: `devtools/devtools.js`

Hooks Chrome's panel visibility events to call the start/stop functions exposed in Task 2. After this task, the panel auto-updates while visible.

- [ ] **Step 1: Replace devtools.js with the visibility-wired version**

Use the Write tool to replace `devtools/devtools.js` with this EXACT content:

```js
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
  "Swiflow/",
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
```

The cached `panelWindow` is non-null between any `onShown` and the next `onHidden`, which is exactly the lifetime we need.

- [ ] **Step 2: Verify the file parses**

Run: `node --check devtools/devtools.js`
Expected: no output (clean parse).

- [ ] **Step 3: Manual smoke test**

Requires the user to reload the extension and exercise it:

1. `chrome://extensions` → reload "Swiflow DevTools".
2. Open a Swiflow app (e.g., the Counter on port 3000).
3. Open DevTools → Swiflow tab.
4. Observe: the live indicator dot in the footer turns green within ~250 ms. The tree populates without clicking ↻ Refresh.
5. In the inspected tab, click the Increment button. The `count` value in the state pane updates within ~250 ms.
6. Switch DevTools to the Elements tab. The Swiflow panel's `onHidden` fires; if you switch back, observe the indicator briefly grey on enter then green on first successful poll.
7. Navigate the inspected tab to `about:blank`. The indicator turns red. The error region stays empty. Navigate back; the indicator returns to green and the tree reappears.
8. Click ↻ Refresh while on `about:blank`. The error region DOES surface "No Swiflow runtime detected on this page ..." — manual refresh still loud, as designed.

- [ ] **Step 4: Commit**

```bash
git add devtools/devtools.js
git commit -m "$(cat <<'EOF'
feat(devtools): wire panel visibility to start/stop the poll loop

Phase 19b Task 3: hooks chrome.devtools.panels Panel.onShown and
Panel.onHidden to call swiflowStart / swiflowStop on the panel
window. Caches the window ref because onHidden doesn't receive a
window arg.

After this commit the panel auto-updates within ~250 ms of every
Swiflow render, with zero Swift-side changes. Polling pauses when
the user switches DevTools tabs away from Swiflow and resumes on
return; the live indicator dot in the footer surfaces green/grey/red
status accurately.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: User docs

**Files:**
- Modify: `devtools/README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update devtools/README.md**

In `devtools/README.md`, find the "## What it shows" heading. Immediately AFTER the existing bullets in that section but BEFORE the "Multi-root apps render one section per mounted selector..." paragraph, insert:

```markdown
- **Live indicator (footer, left edge):** a small dot. **Green**: the panel is polling the inspected app and last poll succeeded. **Grey**: panel is paused (you're viewing a different DevTools tab). **Red**: polling failed (no Swiflow runtime, page navigated away, etc) — the manual ↻ Refresh button still works in this state and will surface the actual error.
```

Then in the "## Limitations (MVP)" section, find and replace the entire bullet that says `**No automatic polling.**` ... `Auto-refresh fires only on full page navigation.` with:

```markdown
- **No state-change row highlight.** When a `@State` value changes between polls, the panel re-renders the row but doesn't visually flash it. A nice-to-have for a follow-up.
```

- [ ] **Step 2: Add the Phase 19b entry to CHANGELOG.md**

Insert a new `##` section IMMEDIATELY ABOVE the existing `## [Phase 19] — Component DevTools (Chrome panel, MVP)` entry. The new entry:

```markdown
## [Phase 19b] — Live DevTools panel (render-version push tick)

### Added
- The Chrome DevTools panel now auto-updates within ~250 ms of every Swiflow render. No more manual ↻ Refresh after every `@State` mutation.
- Footer live indicator (small dot) surfaces panel status: **green** = polling live, **grey** = paused (panel hidden), **red** = poll failed (e.g. inspected tab navigated to a non-Swiflow page). The manual ↻ Refresh button remains as a fallback that always works.

### Mechanism
- Panel polls the existing `window.__swiflow.perf()` surface every 250 ms via the `chrome.devtools.inspectedWindow` API while the panel is visible (gated on `chrome.devtools.panels.Panel.onShown` / `onHidden`). Polls JSON-stringify the per-selector `renders` count map as a stable signature; on change, the existing refresh path runs. Poll-time errors are silent — only manual ↻ Refresh failures surface in the error region.

### Internals
- Zero Swift code changes. `Renderer.renderCount` already incremented on every render (Phase 9) and is already exposed as `__swiflow.perf()[selector].renders` — Phase 19b just teaches the panel to poll it.
```

- [ ] **Step 3: Commit**

```bash
git add devtools/README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(phase19b): document live updates + live-indicator + Phase 19b CHANGELOG

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

- [ ] `node --check devtools/panel.js` — clean
- [ ] `node --check devtools/devtools.js` — clean
- [ ] All five Phase 19a success criteria from `docs/superpowers/specs/2026-05-28-phase19-devtools-mvp-design.md` still hold (manual smoke against the Counter demo).
- [ ] Phase 19b success criteria (from the spec):
  - Counter `count` value updates in the state pane within 250 ms of clicking Increment in the demo, no ↻ click.
  - Switching DevTools tabs pauses (grey) and resumes (green); immediate refresh on resume.
  - Inspected tab → `about:blank` turns indicator red, no error-region spam.
  - Manual ↻ Refresh during outage still surfaces the error loudly.
  - Live indicator color is always accurate.

If any check fails, the offending task is the obvious place to start; the panel.js diff is small enough that bisecting by commit is cheap.
