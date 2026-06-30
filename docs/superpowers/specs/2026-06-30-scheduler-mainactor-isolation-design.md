# Type-enforce `Scheduler` MainActor isolation (#92) — Design

**Goal:** Make the `RAFScheduler → Renderer.flushDirty` boundary MainActor-isolated in a way the **compiler enforces**, eliminating the erased-isolation gap flagged in the #90 Swift review — with no behavior change and no `sending`-data-race diagnostics.

**Issue:** #92. Follow-up from the scoped-rerender perf arc (PR #90).

## Problem

`RAFScheduler.flush()` invokes `onFlushBatch`, which reaches `@MainActor Renderer.flushDirty` — but `onFlushBatch` is stored as a plain `(Set<ObjectIdentifier>) -> Void`, so its MainActor isolation is **erased** at the storage boundary. The code is sound only because the rAF `JSClosure` fires on WASM's single thread; nothing enforces it. The codebase's other JS→Swift boundaries (`Sources/SwiflowDOM/Timing.swift`, `DispatcherBridge.swift`) make this explicit with `MainActor.assumeIsolated { … }`, but `RAFScheduler` cannot today: it is a **nonisolated** class (it witnesses the nonisolated `Scheduler` protocol), so it isn't `Sendable`, so capturing `self` into the rAF `JSClosure` and hopping to the main actor trips `sending 'self' risks causing data races` (verified during PR #90 — every `assumeIsolated` variant failed for this reason).

## Root cause + key insight

The `Scheduler` protocol (`Sources/Swiflow/Reactivity/Scheduler.swift`) is `AnyObject`-bound but **not** `@MainActor` — yet everything that touches it already is:
- `QueryClient` (`@MainActor`), the diff `diff`/`update`/`mount` (`@MainActor`), `Component`/`_ComponentRuntime` (`@MainActor`, so the `@Component` macro's emitted `bind(owner:scheduler:)` is too), and `@State` `didSet` → `markDirty` (runs during body/event handling on the main actor).

A `@MainActor` class is **implicitly `Sendable`**. So isolating the protocol makes both schedulers `Sendable`, which makes the rAF `JSClosure` capture clean and `MainActor.assumeIsolated` valid — the exact `Timing.swift`/`DispatcherBridge.swift` pattern.

## Design

### 1. Isolate the protocol
Annotate `Scheduler` `@MainActor`:
```swift
@MainActor
public protocol Scheduler: AnyObject {
    func markDirty(_ component: AnyComponent)
    func flush()
}
```
Because every caller is already on the main actor, this is expected to be **zero call-site churn** — it makes the existing reality explicit and compiler-checked. Any call site that *does* break is a real (currently-unenforced) isolation hole and is surfaced at build time.

### 2. `SyncScheduler` (core, tests/headless)
Becomes `@MainActor public final class SyncScheduler: Scheduler`. Its `rerenderCallback: (AnyComponent) -> Void`, `markDirty`, and `flush` are now MainActor-isolated. Test/headless callers are already `@MainActor`, so no change there.

### 3. `RAFScheduler` (WASM) — the actual fix
Becomes `@MainActor public final class RAFScheduler: Scheduler` (now `Sendable`). Then:
- `onFlushBatch` is typed `@MainActor (Set<ObjectIdentifier>) -> Void` (isolation enforced, not erased).
- `flush()` invokes it directly (it's `@MainActor`, and `flush` is now `@MainActor`).
- The rAF `JSClosure` in `scheduleRAFIfNeeded` wraps its body in `MainActor.assumeIsolated { self?.rafFired() }` — valid now that `self` is a `Sendable` `@MainActor` class and `rafFired`/`flush` are `@MainActor`, matching the `Timing.swift` convention. `rafFired` clears the scheduling flags and calls `flush()` as before.
- `markDirty` / `scheduleRAFIfNeeded` / `rafFired` are `@MainActor`; the `requestAnimationFrame` registration and `JSClosure` lifetime handling are unchanged.

### 4. `Renderer` (WASM)
The `RAFScheduler { [weak self] ids in self?.flushDirty(ids) }` closure already targets `@MainActor Renderer.flushDirty` from `Renderer.init` (`@MainActor`), so it satisfies the new `@MainActor onFlushBatch` type with no change. `_schedulerBox`/`scheduler` typing is unchanged (`(any Scheduler)?` — now a `@MainActor` existential, accessed only from `@MainActor` `Renderer`).

### Behavior
Identical. Still one `onFlushBatch` per rAF tick; still scoped-vs-full chosen in `flushDirty`; still single-threaded. This is purely making the isolation explicit and compiler-enforced.

## Testing

- **Compile is the primary gate.** Host `swift build` compiles `SyncScheduler` + all `Scheduler` callers (core/SwiflowUI/SwiflowQuery) under the new annotation; the WASM-only `RAFScheduler`/`Renderer` compile under `#if canImport(JavaScriptKit)` (this host imports JavaScriptKit, so `swift build` exercises them — confirmed during the perf arc) and additionally via the demo wasm build.
- **No `sending`/data-race diagnostics** anywhere after the change (the whole point).
- **`swift test`** — full host suite green, including `SchedulerTests` (SyncScheduler batching/reentrancy) and the scoped-rerender fuzz/diff suites. No test should need changing (callers were already MainActor).
- **wasm demo build** — `swiflow build --path examples/SwiflowUIDemo` compiles, confirming `RAFScheduler`/`Renderer` build for `wasm32`.
- **e2e smoke** — the existing `run-e2e`-gated Playwright suite still passes (reactive re-render path unaffected). Not required locally for this change beyond the wasm build; the behavior is unchanged.

## Acceptance criteria
1. `Scheduler` is `@MainActor`; `SyncScheduler` and `RAFScheduler` are `@MainActor final class`.
2. `RAFScheduler.onFlushBatch` is `@MainActor`-typed and its rAF `JSClosure` uses `MainActor.assumeIsolated`, matching `Timing.swift`/`DispatcherBridge.swift`.
3. No `sending`/data-race diagnostics; no behavior change.
4. `swift build`, `swift test`, and the wasm demo build are all green, with no call-site changes outside the scheduler classes (or, if a call site DID require a change, it's a genuine isolation hole — documented in the PR).

## Out of scope
- Any change to the scheduling *behavior* (batching, rAF cadence, scoped-vs-full decision).
- Tightening `EventHandler`/other unrelated closures' `Sendable`ness.
- The `@Component` macro's emitted `bind` signature (it already runs on `@MainActor`; if the `@MainActor` protocol requires a tweak to the emitted code, that's in-scope as a necessary consequence, but no behavioral change).
