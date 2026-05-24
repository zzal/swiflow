# Phase 13c — Multi-Root & Unmount Design

**Date:** 2026-05-24
**Phase:** 13c (Maturity & 1.0 Readiness — Multi-Root Lift)
**Status:** Approved

---

## Goal

Lift the single-root `precondition` so multiple `Swiflow.render(into:)` calls with different selectors work correctly. Add `Swiflow.unmount(into:)` for clean teardown. Update `DevAPI` to report all roots.

No JS driver changes. No `EmbeddedDriver.swift` re-embed. No WASM protocol changes.

---

## Context

The single-root constraint was introduced in Phase 2a as a deliberate simplification. It is enforced by:

1. A `precondition(ambientRenderer == nil, …)` in `Swiflow.render(into:)`.
2. A single `nonisolated(unsafe) var ambientRenderer: Renderer?` global used both as the root registry and as the "currently rendering" cursor for `_registerAmbientHandler`.
3. Per-instance `nextID` in `HandlerRegistry` — two registries both start at 0, causing handler ID collisions if dispatched from a shared JS-side dispatcher.
4. Per-`Renderer` `HandleAllocator` — two renderers both allocate node handle 0, causing JS `nodes` Map collisions.
5. `DispatcherBridge` — one `JSClosure` bound to one registry via the `registry` param of `installIfNeeded(registry:)`.

All five must be resolved. The chosen approach (Option A from brainstorming) uses shared static counters and a global dispatch table to keep globally unique IDs without JS changes.

---

## Architecture

### Core invariant

Every event handler ID and every node handle is globally unique across all live roots. This is guaranteed by:

- `HandlerRegistry.nextID` becomes a `static` counter (shared across all instances).
- `HandleAllocator` — the per-`Renderer` instance is replaced in production by a single module-level `sharedHandleAllocator` in `SwiflowWeb`. Tests and `SwiflowTesting` pass their own instances and are unaffected.

### Global state map

| Symbol | Location | Purpose |
|---|---|---|
| `renderers: [String: Renderer]` | `SwiflowWeb.swift` | All live roots, keyed by CSS selector |
| `_currentRenderingRenderer: Renderer?` | `SwiflowWeb.swift` | Cursor set/cleared around each `renderOnce()` call |
| `HandlerRegistry.nextID` (static) | `HandlerRegistry.swift` | Globally unique handler ID counter |
| `HandlerRegistry.globalTable` (static) | `HandlerRegistry.swift` | `[Int: EventHandler]` — fast O(1) dispatch across all roots |
| `sharedHandleAllocator` | `SwiflowWeb` module level | Shared `HandleAllocator` for all production `Renderer` instances |

---

## Component-Level Changes

### `Sources/Swiflow/HandlerRegistry.swift`

- `private var nextID: Int = 0` → `nonisolated(unsafe) private static var nextID: Int = 0`
- Add `nonisolated(unsafe) private static var globalTable: [Int: EventHandler] = [:]`
- `register`: use `Self.nextID`; write entry to both `handlers` (per-instance, scope tracking) and `Self.globalTable` (dispatch).
- `remove(id:)`: remove from both `handlers` and `Self.globalTable`.
- Add `deinit`: iterates `handlers.keys`, sweeps each from `Self.globalTable`. Prevents leaks when a registry is deallocated (e.g. after `unmount`).
- Add `package static func dispatchGlobal(id: Int, event: EventInfo)`: calls `globalTable[id]?.invoke(event)`.

### `Sources/SwiflowWeb/` — module level

Add at top of `SwiflowWeb.swift` (inside `#if canImport(JavaScriptKit)`):

```swift
nonisolated(unsafe) var renderers: [String: Renderer] = [:]
nonisolated(unsafe) var _currentRenderingRenderer: Renderer?
nonisolated(unsafe) let sharedHandleAllocator = HandleAllocator()
```

Remove `nonisolated(unsafe) var ambientRenderer: Renderer?`.

### `Sources/SwiflowWeb/SwiflowWeb.swift` — `Swiflow` extension

**`render(into:_:)`:**
- Replace `precondition(ambientRenderer == nil, …)` with `precondition(renderers[selector] == nil, "Swiflow.render(into: \"\(selector)\") was already called — call Swiflow.unmount(into: \"\(selector)\") first.")`.
- Replace `ambientRenderer = renderer` with `renderers[selector] = renderer` (after `renderOnce()` completes).
- Call `DispatcherBridge.install()` (no registry param).
- Call `DevAPI.installAll()` (re-installs pointing at the full `renderers` dict) after `renderOnce()`.

**`rerender()`:**
- Replace `ambientRenderer?.renderOnce()` with `renderers.values.forEach { $0.renderOnce() }`.

**New `unmount(into selector: String)` — `@MainActor static`:**
```
guard let renderer = renderers.removeValue(forKey: selector) else { return }
renderer.teardown()
DevAPI.installAll()
```

### `Sources/SwiflowWeb/Renderer.swift`

**`init(rootComponent:selector:)` and `init(viewProducer:selector:)`:**
- Add `handles: HandleAllocator = sharedHandleAllocator` param.
- Remove internal `HandleAllocator()` construction.

**`renderOnce()`:**
- At entry: `_currentRenderingRenderer = self`
- At exit (in `defer`): `_currentRenderingRenderer = nil`

This is the single authoritative place the cursor is set — covers both the initial render (called from `render(into:)`) and all reactive re-renders triggered by the RAF scheduler.

**New `package func teardown()`:**
- Guard `mountTree != nil`, else return.
- Call `destroy(mountTree!, into: &patches, handlers: handlers)`.
- Apply patches via the existing JS patch applier path.
- Call `scheduler?.invalidate()` (or equivalent — cancel the RAF loop).
- Nil out `mountTree`.

### `Sources/SwiflowWeb/DispatcherBridge.swift`

- `installIfNeeded(registry: HandlerRegistry)` → `install()` (no param).
- JSClosure body: replace `registry.dispatch(id:event:)` with `HandlerRegistry.dispatchGlobal(id:event:)`.
- `install()` is still idempotent via the `guard installed == nil` check.

### `Sources/SwiflowWeb/AttributeModifiers.swift`

- `_registerAmbientHandler`: `guard let renderer = ambientRenderer` → `guard let renderer = _currentRenderingRenderer`.
- Update the `fatalError` message to reflect multi-root context.

### `Sources/SwiflowWeb/DevAPI.swift`

- `install(renderer: Renderer)` → `installAll()` (reads `renderers` module global directly).
- `tree()`: returns a JSON object keyed by selector: `{ "#app": "<tree string>", "#sidebar": "<tree string>" }`.
- `state(path)`: searches all renderers in `renderers.values`; path format unchanged (first match wins).
- `handlers()`: returns per-selector handler counts.
- `perf()`: returns per-selector perf stats (renders, lastPatchCount, lastRenderMs).

---

## Data Flow

### Render

```
Swiflow.render(into: "#sidebar") { Sidebar() }
  precondition: renderers["#sidebar"] == nil
  renderer = Renderer(rootComponent: AnyComponent(Sidebar()), selector: "#sidebar",
                      handles: sharedHandleAllocator)
  DispatcherBridge.install()          // idempotent no-op after first root
  RefResolverInstall.resolver = …    // last-renderer-wins; safe: handles are globally unique
  HMRBridge.installSnapshotExporter  // last-renderer-wins; acceptable for 13c
  renderer.renderOnce()
    _currentRenderingRenderer = self    // set inside renderOnce() — covers RAF re-renders too
    … diff …
    _currentRenderingRenderer = nil     // deferred clear
  renderers["#sidebar"] = renderer
  DevAPI.installAll()
```

### Event dispatch

```
DOM event → __swiflowDispatch(handlerId, payload)
  DispatcherBridge JSClosure
  HandlerRegistry.dispatchGlobal(id: handlerId, event: …)
  globalTable[handlerId]?.invoke(event)   // O(1), unique IDs guarantee no cross-root match
```

### Unmount

```
Swiflow.unmount(into: "#sidebar")
  renderer = renderers.removeValue(forKey: "#sidebar")   // nil → no-op
  renderer.teardown()
    destroy(mountTree, patches, handlers)   // fires onDisappear, closes scopes, clears Refs
    apply patches                           // removes DOM nodes
    scheduler.invalidate()                  // cancels RAF loop
    deinit of renderer.handlers             // sweeps handler IDs from globalTable
  DevAPI.installAll()                       // re-installs without "#sidebar"
```

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `render(into:)` called twice for same selector | `precondition` with selector-specific message pointing to `unmount` |
| `unmount(into:)` called for unknown selector | Silent no-op |
| `_registerAmbientHandler` outside a render cycle | Existing `fatalError` (message updated for multi-root) |
| `rerender()` with no roots mounted | No-op (iterating empty dict) |

---

## Known limitations (acceptable for 13c)

- `HMRBridge.installSnapshotExporter` is last-renderer-wins. HMR snapshots will only include the last-mounted root's state. This is acceptable until a full HMR multi-root story is designed (post-1.0).
- `RefResolverInstall.resolver` is last-renderer-wins. Safe because node handles are globally unique across all roots (shared `sharedHandleAllocator`), so the JS `nodeForHandle` lookup is unambiguous regardless of which renderer installed the resolver.

---

## Testing

### New: `Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift`

- Two separate `HandlerRegistry` instances produce strictly non-overlapping handler IDs.
- Handler registered in registry A dispatches correctly via `dispatchGlobal`.
- Handler registered in registry B dispatches correctly via `dispatchGlobal`.
- After registry A is deallocated (`deinit`), its handler IDs are absent from `globalTable`; registry B still dispatches.

### Existing tests — no regressions expected

- `SwiflowTests` (diff, reactivity, scoped handlers) — `HandleAllocator` custom-start inits are unaffected.
- `SwiflowTestingTests` — `SwiflowTesting` uses its own `HandleAllocator` and `HandlerRegistry`; never touches `DispatcherBridge` or `sharedHandleAllocator`.
- `SwiflowCLITests` — `DriverEmbedderTests.embeddedDriverIsFresh` passes unchanged (no JS changes).

---

## File Map

| File | Change |
|---|---|
| `Sources/Swiflow/HandlerRegistry.swift` | Static `nextID` + `globalTable`; `deinit`; `dispatchGlobal` |
| `Sources/SwiflowWeb/SwiflowWeb.swift` | `renderers` dict; `_currentRenderingRenderer`; `sharedHandleAllocator`; lift precondition; `unmount(into:)`; `rerender()` fix |
| `Sources/SwiflowWeb/Renderer.swift` | `handles` param default; set/clear `_currentRenderingRenderer` in `renderOnce()`; `teardown()` |
| `Sources/SwiflowWeb/DispatcherBridge.swift` | Drop registry param; dispatch from `globalTable` |
| `Sources/SwiflowWeb/AttributeModifiers.swift` | Read `_currentRenderingRenderer`; update error message |
| `Sources/SwiflowWeb/DevAPI.swift` | `installAll()`; multi-root reporting for all four commands |
| `Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift` | New test suite (4 tests) |

---

## Exit criteria

1. `swift test` passes with zero regressions.
2. `DriverEmbedderTests.embeddedDriverIsFresh` passes (no JS changes).
3. `HandlerRegistryMultiRootTests` — all 4 tests green.
4. Two separate `Swiflow.render` calls in a WASM build do not trap.
5. `Swiflow.unmount(into:)` removes DOM nodes and cleans up handlers.
6. `window.__swiflow.tree()` returns results for all mounted roots.
7. README status line updated to "Phase 13c (Multi-Root & Unmount)".
