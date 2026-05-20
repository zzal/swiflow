# Swiflow Phase 9 — Devtools: Component Inspector Design

**Date:** 2026-05-20
**Status:** Approved

---

## Goal

Expose a `window.__swiflow` browser console API that lets a developer inspect the live component tree, per-component `@State`, handler counts, and render performance — all without leaving the browser DevTools.

DOM overlay is explicitly deferred to a later phase.

---

## Scope

Four functions added to the existing `window.__swiflow` JS object:

- `tree()` — indented string of the live mount tree
- `state(path)` — `@State` values for the component at a given path
- `handlers()` — HandlerRegistry counts per scope
- `perf()` — render count, last patch count, last render time

Plus `docs/guides/devtools.md`.

---

## Architecture

### File layout

**New:** `Sources/SwiflowWeb/DevAPI.swift`

Single internal entry point: `DevAPI.install(renderer: Renderer)`.

Checks `JSObject.global.SWIFLOW_DEV.boolean == true` at install time. If the gate passes, attaches four `JSClosure` instances to the existing `window.__swiflow` JS object. All closures capture a `weak` reference to the renderer.

No new module. No new `Package.swift` target. Stays inside `SwiflowWeb`.

**Modified:** `Sources/SwiflowWeb/SwiflowWeb.swift`

One line added at the end of `Swiflow.render()`, after `renderer.renderOnce()`:

```swift
DevAPI.install(renderer: renderer)
```

**Modified:** `Sources/SwiflowWeb/Renderer.swift`

Three additions:
- `private(set) var renderCount: Int = 0` — incremented every `renderOnce()` call
- `private(set) var lastPatchCount: Int = 0` — set to the patch count produced by the last diff
- `private(set) var lastRenderMs: Double = 0` — wall-clock duration of the last `renderOnce()` call, measured via `CFAbsoluteTimeGetCurrent()`

---

## API Surface

### `__swiflow.tree() → String`

Returns an indented string. Each line: `TypeName "path"`. Component anchors whose rendered body is a continuation of the same path show `[body→]`. State values are not included here.

```
App "" [body→]
  Sidebar "" [body→]
    NavItem "0"
  MainArea "1" [body→]
    Counter "1.0"
    Counter "1.1"
    UserProfile "1.2"
```

### `__swiflow.state(path) → Object | null`

Takes a dot-joined child-index path string (e.g. `"1.0"`). Returns a plain JS object whose keys are `@State` field names (leading `_` stripped) and whose values are the current snapshot primitives.

Primitive coercion:
- `Int` / `Double` → JS number
- `String` → JS string
- `Bool` → JS boolean
- `Optional.none` / `HMRNilSentinel` → JS `null`
- Any other type → omitted (no error)

Returns `null` if no component exists at the given path.

```js
__swiflow.state("1.0")   // → { count: 5, label: "clicks" }
__swiflow.state("99")    // → null
```

Identification is path-only. Type-name lookup is not supported — it is ambiguous when multiple instances of the same component type exist in the tree.

### `__swiflow.handlers() → Object`

Returns handler counts from `HandlerRegistry`.

```js
__swiflow.handlers()
// → { total: 14, byScope: { "": 2, "1.0": 6, "1.1": 4, "1.2": 2 } }
```

`total` is the sum of all per-scope counts. `byScope` maps each component path to its registered handler count. A scope whose count grows unboundedly across re-renders indicates a handler leak.

Requires a new `HandlerRegistry.countPerScope() -> [String: Int]` method.

### `__swiflow.perf() → Object`

```js
__swiflow.perf()
// → { renders: 7, lastPatchCount: 3, lastRenderMs: 1.2 }
```

- `renders`: cumulative count of `renderOnce()` calls since page load.
- `lastPatchCount`: number of DOM patches applied during the most recent render.
- `lastRenderMs`: wall-clock duration of the most recent render in milliseconds.

---

## Data Flow

Each function walks Swift data structures at call time and serializes to `JSValue`. Nothing is cached — every call reflects the live state at that moment.

**`tree()`** — recursive `MountNode` walk in the same traversal order as `HMRWalker.snapshot()`. Builds the indented string in Swift; returns `JSValue.string`. The `[body→]` marker is emitted when a node has a non-nil `componentBody`.

**`state(path)`** — calls `HMRWalker.snapshot(from: renderer.mountTree)`, finds the matching snapshot by path, encodes `[String: Any]` to `JSValue.object` using the primitive coercion rules above.

**`handlers()`** — calls `HandlerRegistry.countPerScope()`, sums entries, encodes total + map to `JSValue.object`.

**`perf()`** — reads `renderer.renderCount`, `renderer.lastPatchCount`, `renderer.lastRenderMs` directly; encodes to `JSValue.object`.

All four are `JSClosure` instances stored on `window.__swiflow`. They are not deallocated (held by the JS side) for the lifetime of the page.

---

## Dev-Mode Gate

`DevAPI.install(renderer:)` checks `JSObject.global.SWIFLOW_DEV.boolean == true` before attaching anything. `SWIFLOW_DEV` is injected by `DevModeInjection` in the CLI dev server — it is never present in a production build. Production pages see no devtools functions on `window.__swiflow`.

---

## Testing

**`Tests/SwiflowTests/DevAPI/DevAPISnapshotTests.swift`** (new)

Unit tests against the Swift-side walk and serialization logic; no JavaScriptKit required. Builds small `MountNode` trees manually, calls the internal walk functions, asserts output.

Covers:
- Tree indentation and `[body→]` marker
- `state()` path lookup hit and miss (nil return)
- Non-serialisable values are omitted without error
- `handlers()` total equals sum of per-scope counts
- `perf()` counters increment correctly across multiple `renderOnce()` calls

The `SWIFLOW_DEV` JS gate and the `window.__swiflow` attachment are not testable from the macOS unit-test target (no JavaScriptKit). A future WASM end-to-end test target should verify that calling `__swiflow.tree()` in a real browser returns a non-empty string after `Swiflow.render()`.

---

## Documentation

**`docs/guides/devtools.md`** — covers:
1. How to open the devtools (browser console, dev server only)
2. `tree()` walkthrough with sample output
3. `state(path)` — how to find a path from `tree()` output, then inspect
4. `handlers()` — how to spot a leak
5. `perf()` — what each field means and when to care

---

## Out of Scope (Phase 9)

- DOM overlay (`__swiflow.overlay()`) — deferred
- In-browser devtools panel / browser extension
- `state()` mutation from the console
- Type-name lookup shortcut for `state()`
