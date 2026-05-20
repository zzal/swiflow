# Swiflow Phase 8 — HMR & The Instant Dev Loop

> **Motto:** *"The single most important thing Swiflow can do between now and 1.0 is to make `save → pixels` feel instant. Everything else is downstream of that."*

**Date:** 2026-05-20
**Phase:** 8 of 13 (the motto centerpiece)
**Status:** Spec — ready for plan
**Predecessors:** Phase 5 (API Polish), Phase 6 (Trust & Polish), Phase 7 (Bindings, Refs & Form Foundations)

---

## 1. Why this phase

Today's `swiflow dev` loop on a file save:

1. FileWatcher fires (`Sources/SwiflowCLI/DevServer/FileWatcher.swift:38`).
2. WASM rebuilds (~8s hot on M1 Max).
3. `WebSocketHub.broadcastReload()` sends `{"type":"reload"}` to every connected browser.
4. The JS driver calls `location.reload()` (`js-driver/swiflow-driver.js:294`).
5. The page reloads. **Every `@State` cell resets to its initial value.** Scroll resets. Focus is lost. The user retypes whatever they were demoing.

The 8s rebuild is partly hardware-bound and not the worst part of this. The worst part is the state loss — even a 100ms rebuild that nukes `count = 47` back to `count = 0` is a worse demo than a 2s rebuild that keeps `count = 47`. The motto says save→pixels should *feel* instant; "feel" is dominated by continuity, not latency.

This phase replaces `location.reload()` with a **state-preserving hot module swap**: the browser fetches the new WASM, the runtime extracts state from the old module, the new module rebuilds the tree seeded with that state, the DOM is patched, and `@State` survives.

---

## 2. Scope

### 2.1 In scope

1. **Server-side HMR broadcast.** `WebSocketHub` gains `broadcastHMRSwap(wasmURL:jsURL:)` alongside the existing `broadcastReload`. `DevCommand`'s rebuild loop calls the new method on success.
2. **HTML injection of the HMR signal.** `DevModeInjection` also injects `window.SWIFLOW_HMR = true` so the driver's HMR branch activates only under the dev server.
3. **JS driver HMR branch.** On receiving `{"type":"hmr-swap", ...}`, the driver:
   - Asks the live Swift module for a snapshot of `@State` values.
   - Clears the JS handle map, listener map, and mount-target DOM children (via `replaceChildren()` — no HTML-property writes).
   - Dynamically imports the new `index.js` (cache-busted).
   - Stashes the snapshot in `window.__swiflowPendingSnapshot`.
   - On any load failure, falls back to `location.reload()` with a `console.warn`.
4. **Snapshot extraction.** Swift exposes `window.__swiflow.hmrSnapshot()` returning a JS array of `{ path, typeName, key, state }` per Component. Implemented in `Sources/SwiflowWeb/HMR/HMRSnapshot.swift`.
5. **State restore on first render.** `Swiflow.render(into:_:)` checks `window.__swiflowPendingSnapshot` on entry; if non-null, it routes through `HMRRestore` which seeds newly-constructed Component instances with state values matched by `(path, typeName, key)`. User code (`Swiflow.render(into: "#app") { App() }`) is unchanged.
6. **State value type support.** v1 preserves `String`, `Int`, `Double`, `Bool`, and `Optional`s of these. Anything else logs a debug warning and resets to the Component's declared initial value for that cell.
7. **Counter template demo.** `examples/HelloWorld` Counter gets a brief inline comment pointing at the new HMR behavior. The existing `count`, `greeting`, `celebrate` fields are all primitives, so the demo "just works" once the runtime is in place.
8. **Forms guide cross-link.** `docs/guides/forms.md` gains a one-sentence "HMR preserves form state across saves" callout.
9. **Performance baseline doc.** `docs/perf/2026-05-20-hmr-baseline.md` records the measured save→pixels time on Counter, hot vs. cold, M1 Max with Swift 6.3 / WASM SDK 6.3. The doc lives in the repo so future regressions are visible.
10. **README status line and "What works today" update.** Phase 8 listed as latest completed; HMR moved from "not in the box yet" to "works today" with the measured save→pixels number.

### 2.2 Explicitly out of scope (deferred)

- **DOM-handle preservation across swap.** v1 clears and re-mounts. Focus, scroll position, and `<input>` cursor index are lost. Reattaching to existing DOM nodes by `(path, typeName)` is a Phase 9+ devtools refinement.
- **Codable state values.** Only the primitive set above. The Counter template doesn't need more. Adding generic `Encodable`/`Decodable` support is a follow-on once a user actually trips on the limitation.
- **DWARF / source-map browser stack traces.** Tangential to the motto; revisited in Phase 13 alongside the macro-diagnostics work. The current dev experience around stack traces is documented (with its warts) in `docs/guides/debugging.md`.
- **Sub-3-second incremental rebuild via linker-skipping.** Phase 8 measures and documents but does not optimize. A future perf task can profile and prune.
- **Multi-root HMR.** v1 stays single-root, matching the existing `render(into:)` precondition. Phase 13 lifts the trap and multi-root HMR comes with it.
- **HMR across editor-driven Component renames.** Renaming a Component class breaks the snapshot's `typeName` match and that subtree's `@State` resets. Acceptable; React Fast Refresh has the same limitation.

---

## 3. The protocol

```
                                 ┌────────────────────────────────┐
                                 │  swiflow dev (Swift process)   │
                                 │                                │
                                 │   FileWatcher → rebuild → ok?  │
                                 │                  │             │
                                 │                  │ yes         │
                                 │                  ▼             │
                                 │  WebSocketHub.broadcastHMRSwap │
                                 │  ({type:"hmr-swap",            │
                                 │    wasmURL:"/Bundle.wasm?h=X", │
                                 │    jsURL: "/index.js?h=X"})    │
                                 └────────────────┬───────────────┘
                                                  │
                                                  ▼ (WS message)
                                 ┌─────────────────────────────────┐
                                 │  swiflow-driver.js (browser)    │
                                 │                                 │
                                 │  1. snapshot = window.__swiflow │
                                 │      ?.hmrSnapshot?.()          │
                                 │  2. window.__swiflowPending     │
                                 │      Snapshot = snapshot        │
                                 │  3. nodes.clear()               │
                                 │     listeners.clear()           │
                                 │     mountTarget.replaceChildren │
                                 │  4. import(jsURL)               │
                                 │  5. on any failure: warn +      │
                                 │     location.reload()           │
                                 └────────────────┬────────────────┘
                                                  │
                                                  ▼ (new module loads)
                                 ┌─────────────────────────────────┐
                                 │  user's App.swift (new module)  │
                                 │                                 │
                                 │  Swiflow.render(into: "#app")   │
                                 │    { App() }                    │
                                 │                                 │
                                 │  ↓ runtime detects pending      │
                                 │    snapshot, routes through     │
                                 │    HMRRestore.render(...)       │
                                 │                                 │
                                 │  ↓ mount tree builds, each new  │
                                 │    Component checks snapshot    │
                                 │    by (path,typeName,key),      │
                                 │    overwrites @State boxes      │
                                 │    before first body() call     │
                                 │                                 │
                                 │  ↓ Renderer.renderOnce() emits  │
                                 │    create* patches for the      │
                                 │    new DOM, applies, mounts.    │
                                 │                                 │
                                 │  ↓ window.__swiflowPending      │
                                 │    Snapshot = null              │
                                 │  ↓ window.__swiflow.hmrSnapshot │
                                 │    installs the new walker      │
                                 └─────────────────────────────────┘
```

---

## 4. Component-by-component design

### 4.1 `Sources/SwiflowCLI/DevServer/WebSocketHub.swift`

Add an HMR broadcast method alongside the existing reload broadcast. Symmetric error handling (drop on write failure, don't propagate).

```swift
/// Send `{"type":"hmr-swap","wasmURL":..,"jsURL":..}` to every connected
/// client. Used by `DevCommand`'s rebuild loop when HMR is in effect
/// (currently always in dev mode). On any write failure, drop the client
/// from the registry and continue.
///
/// The URLs are cache-busted (with a query-string hash) by the caller so
/// the browser's HTTP cache is bypassed.
func broadcastHMRSwap(wasmURL: String, jsURL: String) async
```

The payload includes both URLs because the new entry point (`index.js`) loads the WASM and bootstraps the runtime; the browser needs the JS module URL, the WASM URL is informational for now (the JS knows how to find it via the same path-with-hash convention).

**Cache-busting strategy.** Use the mtime (or content hash) of `Bundle.wasm` in milliseconds. The `?h=<mtime>` query string forces fresh fetch and is invisible to the file system. Hash is cheap; mtime is cheaper. v1 uses mtime.

### 4.2 `Sources/SwiflowCLI/DevServer/DevModeInjection.swift`

Inject **two** globals, not one:

```html
<script>window.SWIFLOW_DEV=true;window.SWIFLOW_HMR=true;</script>
```

Idempotency: the marker is updated to include both. `SWIFLOW_HMR` defaults true when the dev server injects it; production builds leave both undefined.

Splitting the two globals (instead of overloading `SWIFLOW_DEV`) keeps room for future dev-server features that don't want HMR (e.g., a "production preview" mode).

### 4.3 `Sources/SwiflowCLI/Commands/DevCommand.swift`

Replace the `broadcastReload()` call in the rebuild loop with `broadcastHMRSwap(wasmURL:jsURL:)`. The URLs are derived from the project's `dist/` layout (`/Bundle.wasm?h=…`, `/index.js?h=…`) with the mtime of `Bundle.wasm` appended.

The first build still uses the existing initial-build path; HMR only affects subsequent rebuilds, so the cold-start UX is unchanged.

### 4.4 `js-driver/swiflow-driver.js`

The driver gains:

1. **Mount-target memory.** The existing `mount` function gets a query selector; today the driver doesn't remember it. Store it as `let mountSelector = null` and set it in `mount(rootHandle, selector)`.
2. **HMR branch in the WS message handler.** Replace the single `if (payload.type === "reload")` with a switch over `type`:
   - `"reload"` → `location.reload()` (kept for graceful fallback).
   - `"hmr-swap"` → kick off the HMR pipeline (see below).
3. **HMR pipeline function:**
   ```js
   async function hmrSwap(payload) {
     try {
       const snapshot =
         window.__swiflow && window.__swiflow.hmrSnapshot
           ? window.__swiflow.hmrSnapshot()
           : null;
       window.__swiflowPendingSnapshot = snapshot;

       // Drop maps + clear DOM mount target via replaceChildren()
       // (no HTML-property writes — matches the driver's XSS-safe
       // contract: setRawHTML is the only intentional HTML-writing
       // site).
       nodes.clear();
       listeners.clear();
       if (mountSelector) {
         const t = document.querySelector(mountSelector);
         if (t) t.replaceChildren();
       }

       // Re-import the new entry. Browsers cache ES-module imports by
       // URL, so the cache-busting query is what makes the new module
       // load fresh. We `await` it so failures fall through to catch.
       await import(payload.jsURL);
     } catch (e) {
       console.warn(
         "[swiflow] HMR swap failed, falling back to full reload:",
         e
       );
       location.reload();
     }
   }
   ```
4. **No DOM cleanup in the OLD module.** The old WASM's `Renderer` is unreachable after the new module loads (the new instance has fresh static storage). The JS driver clears state on its side. No deinitialization races.

Mirror the JS into `Sources/SwiflowCLI/EmbeddedDriver.swift` via `swift scripts/embed-driver.swift` per the `project_js_driver_embedded_sync` invariant.

### 4.5 `Sources/Swiflow/Reactivity/State.swift`

Extend `State<Value>` with **package-internal** HMR hooks:

```swift
extension State {
    /// Used by HMR snapshot extraction. Returns the current value typed as
    /// `Any` so the snapshot walker can pattern-match on the underlying
    /// primitive (String/Int/Double/Bool/Optional thereof) and serialize
    /// it. Returns the value as-is for any type — the walker decides what
    /// to encode.
    package func _hmrSnapshotValue() -> Any { storage.value }

    /// Used by HMR restore. If `newValue` is type-compatible with `Value`,
    /// overwrites the storage in place (no scheduler notification — the
    /// owner isn't wired yet at restore time; the first render after
    /// restore will pick up the new value naturally).
    /// Returns true on success, false on type mismatch.
    package func _hmrRestore(_ newValue: Any) -> Bool {
        guard let typed = newValue as? Value else { return false }
        storage.value = typed
        return true
    }
}
```

`StateWireable` (the existing protocol used by `wireState(on:scheduler:)`) gains the two methods so the Mirror walk can reach them without a concrete-type cast.

```swift
protocol StateWireable: AnyObject {
    func _setOwner(_ owner: AnyComponent, scheduler: Scheduler)
    func _hmrSnapshotValue() -> Any
    func _hmrRestore(_ newValue: Any) -> Bool
}
```

`State` already conforms via the trailing extension.

### 4.6 `Sources/SwiflowWeb/HMR/HMRSnapshot.swift` (new)

Snapshot extraction. The walker visits the live mount tree and produces a JS array.

```swift
@MainActor
enum HMRSnapshot {
    /// Walk the live mount tree of `renderer` and produce a JSValue
    /// array. Each entry: { path, typeName, key, state: {fieldName: value} }.
    /// Called from JS via `window.__swiflow.hmrSnapshot()`.
    static func collect(from renderer: Renderer) -> JSValue
}
```

Path = a dot-joined string of mount-tree child indices, e.g., `"0.2.1"`. typeName = `String(reflecting: type(of: component.instance))`. key = the component's description key (often nil).

For each Component, walk `Mirror(reflecting: instance).children`; for each child whose value is a `StateWireable`, call `_hmrSnapshotValue()` and encode to JSValue if the type is in the supported primitive set. The field name is the Mirror child label stripped of its leading `_` (so `_count` → `count`).

### 4.7 `Sources/SwiflowWeb/HMR/HMRRestore.swift` (new)

Restoration. Run during the first render of the new module when a pending snapshot exists.

```swift
@MainActor
enum HMRRestore {
    /// Decode a JSValue snapshot into a Swift-side index, keyed by
    /// (path, typeName, key). One entry per Component in the old tree.
    static func decode(_ js: JSValue) -> [SnapshotKey: [String: Any]]

    /// For a freshly-instantiated AnyComponent at `path`, look up
    /// matching state in `index` (by path+typeName+key) and write the
    /// values into the new Component's @State cells via Mirror +
    /// `StateWireable._hmrRestore`.
    /// Mismatches (type drift, missing field) are skipped silently and
    /// logged via `swiflowDiagnostic`.
    static func apply(
        _ index: [SnapshotKey: [String: Any]],
        to component: AnyComponent,
        at path: String
    )
}

struct SnapshotKey: Hashable {
    let path: String
    let typeName: String
    let key: String?
}
```

The restore-walk runs during the diff's component-mount path. The simplest hook is to call `HMRRestore.apply(...)` immediately after `wireState(on:scheduler:)` (the same Mirror walk site, doing one more thing). This means **the existing diff machinery is the only place that needs to know HMR exists** — there is no second "HMR pass" over the tree.

### 4.8 `Sources/SwiflowWeb/HMR/SwiflowHMR.swift` (new)

JS-callable installers and the snapshot-aware render entry.

```swift
public extension Swiflow {
    /// Render-or-restore entry. Used internally by render(into:_:).
    /// If `window.__swiflowPendingSnapshot` is non-null, the snapshot is
    /// decoded and threaded through the diff's first-mount path; the
    /// snapshot global is then cleared.
    @MainActor
    static func render<C: Component>(
        into selector: String,
        _ factory: @escaping @MainActor () -> C
    ) {
        // existing precondition + setup ...
        // NEW: peek at window.__swiflowPendingSnapshot
        // NEW: if non-null, decode + stash on the Renderer for use in the
        //      next renderOnce()
        // NEW: install window.__swiflow.hmrSnapshot once
        // ... continue with existing renderer creation + renderOnce()
    }
}
```

The HMR snapshot installer is idempotent and runs on every render entry; safe to call repeatedly across module loads (the new module installs its own).

### 4.9 `Sources/SwiflowWeb/Renderer.swift`

Renderer carries an optional `hmrSnapshotIndex: [SnapshotKey: [String: Any]]?` plus a per-mount-path tracker so the diff can ask: "for the Component being mounted at path X, what's the restore record?" The tracker is consulted only on first mount; after `renderOnce()` returns, the index can be cleared (subsequent renders are normal reactivity, no HMR involved).

### 4.10 `Sources/Swiflow/Diff/Diff.swift`

Single change: at the site where `wireState(on:scheduler:)` is called for a newly-mounted Component, also call into the renderer's HMR-restore hook. The hook is package-internal and a no-op when no snapshot is pending.

**Why here:** the diff already walks every newly-mounted Component anchor exactly once. Adding a sibling call to the existing wiring site keeps HMR off the diff's hot path entirely (the hook is a single `if let index = …` check and an immediate return when nil).

### 4.11 `docs/perf/2026-05-20-hmr-baseline.md` (new)

Records measured save→pixels times. Format:

| Scenario | Cold build | Hot rebuild | HMR swap (perceptual) |
| --- | --- | --- | --- |
| Counter (M1 Max, Swift 6.3) | …s | …s | …ms |
| Counter (M1 Max, Swift 6.3, after `swift package clean`) | …s | n/a | n/a |

Plus a one-paragraph narrative for "what changed about the dev loop." Numbers measured during Phase 8 implementation, not estimated.

---

## 5. Failure modes

| Failure | Behavior |
| --- | --- |
| Snapshot extraction throws (unexpected JS error) | Caught in JS; `console.warn` + `location.reload()` |
| New `index.js` 404s or syntax-errors | Caught in JS; `console.warn` + `location.reload()` |
| New WASM module instantiation throws | Caught in JS during `import()`; same fallback |
| `__swiflowPendingSnapshot` decode fails (corrupt JSON, missing fields) | Swift-side decode returns empty index; restore is a no-op; new tree starts fresh |
| `@State var count: Int` → user changed to `@State var count: String` | `_hmrRestore(_:)` returns false; that field resets to declared initial; debug log via `swiflowDiagnostic` |
| Component renamed (typeName mismatch) | No match in index; entire subtree resets; debug log |
| Component tree shape changed dramatically | Unmatched old entries silently dropped; new tree mounts normally |
| Two components at same path with same typeName but different `key`s | Matched by key (precise); state preserved per-instance |
| `Mirror.children` returns nothing (no `@State`) | Snapshot/restore are no-ops for that Component |

Across all failure modes, the user **never sees a broken page**: either HMR succeeds, or full reload triggers. There is no third state.

---

## 6. Test plan

### 6.1 Unit (Swift host)

- **HMRSnapshotTests** — synthetic tree of nested Components, assert path / typeName / key / state structure.
- **HMRRestoreTests** — apply a hand-rolled snapshot index to a freshly-built Component, verify @State values overwritten.
- **HMRRoundTripTests** — round-trip: build tree A, snapshot, build tree A' (identical), restore, verify @State values match originals. Cover String/Int/Double/Bool/Optional<String>.
- **HMRTypeDriftTests** — old snapshot says `count: Int`, new tree's State is `String`; assert `_hmrRestore` returns false and the field falls back to initial value.
- **HMRShapeChangeTests** — old snapshot has Component "Foo" at path "0.1"; new tree has "Bar" there. Assert no restore (typeName mismatch).
- **WebSocketHubHMRTests** — extend the existing hub tests with `broadcastHMRSwap(wasmURL:jsURL:)`: verify payload is correct JSON, includes both URLs, and that drop-on-write-failure semantics still hold.
- **DevModeInjectionTests** — assert both globals are injected, idempotent on second injection, fallback to `</body>` works.
- **StateHMRHookTests** — verify `_hmrSnapshotValue()` and `_hmrRestore(_:)` happy path and type-mismatch path on each primitive.

### 6.2 Manual / integration (browser)

- Load Counter, click count to 7, save Counter.swift (touch only — comment edit), verify after rebuild that count stays at 7.
- Edit Counter.swift to change `count += 1` to `count += 2`, save. Verify count stays at 7 *and* next click bumps to 9.
- Type "hello" into the greeting input, save. Verify "hello" survives.
- Rename `Counter` → `MyCounter`, save. Verify the component subtree resets (typeName changed) but page does not full-reload.
- Introduce a compile error, save. Verify `swiflow: rebuild failed …` message in CLI, browser unchanged (no broadcast → no swap).
- Kill `swiflow dev` mid-session and restart it. Verify reconnect → first save triggers full reload (the post-restart browser had no module to snapshot from, but the runtime still installs cleanly).

### 6.3 Performance baseline (Counter, M1 Max)

Measure and record in `docs/perf/2026-05-20-hmr-baseline.md`:

- Cold build (`swift package clean` first): time `swiflow dev`'s initial build banner → first paint.
- Hot rebuild: file save → WS broadcast → DOM repainted with state preserved. Use `performance.now()` in the JS driver to bracket from `hmr-swap` receipt to the first patch-application after the new module loads.

**Target:** hot rebuild HMR perceptual time **<1s** with `@State` preserved.

---

## 7. File-by-file summary

**New:**
- `Sources/SwiflowWeb/HMR/HMRSnapshot.swift`
- `Sources/SwiflowWeb/HMR/HMRRestore.swift`
- `Sources/SwiflowWeb/HMR/SwiflowHMR.swift`
- `docs/perf/2026-05-20-hmr-baseline.md`
- `Tests/SwiflowTests/HMR/HMRSnapshotTests.swift`
- `Tests/SwiflowTests/HMR/HMRRestoreTests.swift`
- `Tests/SwiflowTests/HMR/HMRRoundTripTests.swift`
- `Tests/SwiflowTests/HMR/HMRTypeDriftTests.swift`
- `Tests/SwiflowTests/HMR/HMRShapeChangeTests.swift`
- `Tests/SwiflowTests/HMR/StateHMRHookTests.swift`
- `Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift`

**Modified:**
- `Sources/SwiflowCLI/DevServer/WebSocketHub.swift` — `broadcastHMRSwap(wasmURL:jsURL:)`
- `Sources/SwiflowCLI/DevServer/DevModeInjection.swift` — inject both globals
- `Sources/SwiflowCLI/Commands/DevCommand.swift` — call `broadcastHMRSwap` instead of `broadcastReload`
- `Sources/Swiflow/Reactivity/State.swift` — `StateWireable` gains two methods; trailing extension
- `Sources/Swiflow/Diff/Diff.swift` — single-line call into restore hook at the existing mount-wire site
- `Sources/SwiflowWeb/SwiflowWeb.swift` — `render(into:_:)` peeks at pending snapshot, installs `__swiflow.hmrSnapshot`
- `Sources/SwiflowWeb/Renderer.swift` — carries optional `hmrSnapshotIndex` for the first render
- `js-driver/swiflow-driver.js` — mount-selector memory + HMR branch + `hmrSwap` function
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated via embed script (bit-for-bit mirror)
- `examples/HelloWorld/Sources/App/App.swift` — inline HMR explainer comment
- `Sources/SwiflowCLI/Templates/Templates.swift` — mirror the comment
- `docs/guides/forms.md` — one-sentence HMR callout
- `README.md` — Phase 8 status; HMR moved to "works today"; updated rebuild/HMR numbers

---

## 8. Exit criteria

This phase ships when all of these hold:

1. **All 327+ existing tests still pass** plus the new HMR/HMRHook/DevServerHMR tests.
2. **The Counter template demos a `@State`-preserving save→pixels loop in the browser**, recorded in `docs/perf/2026-05-20-hmr-baseline.md`.
3. **HMR swap measured time is under 1 second** on M1 Max, Counter template, hot rebuild.
4. **Failure modes all fall back gracefully** to `location.reload()` with a `console.warn` — verified manually for at least one path (introduce a syntax error in `index.js` after a successful initial load, observe fallback).
5. **README's "What works today" lists HMR** with the measured number.
6. **Phase 8 spec (this doc) and plan are committed** to the repo per `reference_swiflow_phase_doc_layout`.
7. **`js-driver/swiflow-driver.js` and `Sources/SwiflowCLI/EmbeddedDriver.swift` are bit-for-bit identical** per the `project_js_driver_embedded_sync` invariant.

---

## 9. Design decisions log

- **State migration carrier = JS array of `{path, typeName, key, state}` objects, not a Swift `Codable` blob.** The blob would need a wire format that survives WASM module boundaries; JS is the only neutral medium between the two modules. Side benefit: the snapshot is inspectable in DevTools as a real JS object.
- **Path = dot-joined child indices, not stable IDs.** Stable IDs would require user annotation. Child-index paths work for the structural-stability cases that matter most (small edits to a stable tree) and degrade gracefully otherwise (mismatched paths drop their state).
- **No DOM preservation.** The handle map and listener map are unreachable from the new module without a cross-module handle bridge that would dominate this phase's complexity. The cheaper win — preserving `@State` — captures most of the perceived "instant" feel. DOM continuity is a future phase.
- **HMR installer (`window.__swiflow.hmrSnapshot`) lives at the same namespace as Phase 7's Ref resolver.** Reusing the namespace keeps the runtime surface tight and self-documenting from a DevTools console.
- **Two globals (`SWIFLOW_DEV` + `SWIFLOW_HMR`), not one.** Future dev-mode features (e.g., a "production preview" mode) may want dev features without HMR. Cheap to split now, painful to retrofit later.
- **Render entry detects pending snapshot internally; user code is unchanged.** Forcing the user to call `hmrRestore(into:_:)` would break the "save and forget" promise. The runtime owns the branch.
- **Mount-target clearing uses `replaceChildren()`, not `innerHTML = ""`.** The driver's XSS-safe contract restricts HTML-property writes to a single named-loud site (`setRawHTML`). `replaceChildren()` is the modern, hook-friendly equivalent for "drop all children."
- **Phase 8 measures performance; it does not optimize.** Adding linker-skip or DWARF inline-source machinery balloons scope without changing the user-perceptual outcome of *this phase*. The HMR mechanism is the deliverable; perf optimization comes later.
