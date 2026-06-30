# Type-enforce `Scheduler` MainActor isolation (#92) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Annotate `Scheduler` `@MainActor` and make both schedulers `@MainActor` classes, so the `RAFScheduler → Renderer.flushDirty` boundary is compiler-enforced (via `MainActor.assumeIsolated` + an `@MainActor onFlushBatch`) — no behavior change, no `sending` diagnostics.

**Architecture:** This is a single **atomic** type-level change: annotating the protocol `@MainActor` requires both conformers (`SyncScheduler`, `RAFScheduler`) to be `@MainActor` in the same edit, or conformance breaks. A `@MainActor` class is implicitly `Sendable`, which is what makes the rAF `JSClosure` capture + `assumeIsolated` valid (the fix that failed in PR #90 only because `RAFScheduler` was nonisolated/non-`Sendable`). Verification is compile + existing tests (no behavior change → no new test).

**Tech Stack:** Swift 6.3 strict concurrency. Core (`Swiflow`) + WASM (`SwiflowDOM`, imports JavaScriptKit — compiles on this host).

**Spec:** `docs/superpowers/specs/2026-06-30-scheduler-mainactor-isolation-design.md`.

**Critical context (verified):**
- Every `Scheduler` caller is already `@MainActor`: `QueryClient` (`@MainActor`), `diff`/`update`/`mount` (`@MainActor`), `Component`/`_ComponentRuntime` (`@MainActor`, so the `@Component` macro's emitted `bind(owner:scheduler:)` runs there), `@State` `didSet` → `markDirty`. So the annotation is expected to be **zero call-site churn**.
- `Renderer` is `@MainActor`; its `RAFScheduler { [weak self] ids in self?.flushDirty(ids) }` closure is formed in `@MainActor Renderer.init` and targets `@MainActor flushDirty` — already satisfies an `@MainActor onFlushBatch`.
- `Timing.swift` / `DispatcherBridge.swift` are the precedent: JS→Swift boundaries that wrap their body in `MainActor.assumeIsolated`.

**Branch:** `refactor/scheduler-mainactor-isolation` (created off `origin/main`; spec committed there).

---

## Task 1: Isolate `Scheduler` + both conformers (atomic)

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Scheduler.swift` (protocol + `SyncScheduler`)
- Modify: `Sources/SwiflowDOM/RAFScheduler.swift` (class + `onFlushBatch` + rAF closure)

- [ ] **Step 1: Annotate the protocol `@MainActor`.** In `Sources/Swiflow/Reactivity/Scheduler.swift`, change:

```swift
public protocol Scheduler: AnyObject {
```
to:
```swift
@MainActor
public protocol Scheduler: AnyObject {
```

- [ ] **Step 2: Make `SyncScheduler` `@MainActor`.** In the same file, change:

```swift
public final class SyncScheduler: Scheduler {
```
to:
```swift
@MainActor
public final class SyncScheduler: Scheduler {
```
(No body changes — `markDirty`/`flush`/`rerenderCallback` are unchanged; they're just MainActor-isolated now.)

- [ ] **Step 3: Make `RAFScheduler` `@MainActor` + type-enforce the callback.** In `Sources/SwiflowDOM/RAFScheduler.swift`:

3a. Class declaration:
```swift
public final class RAFScheduler: Scheduler {
```
→
```swift
@MainActor
public final class RAFScheduler: Scheduler {
```

3b. Stored callback type:
```swift
    private let onFlushBatch: (Set<ObjectIdentifier>) -> Void
```
→
```swift
    private let onFlushBatch: @MainActor (Set<ObjectIdentifier>) -> Void
```

3c. Initializer parameter:
```swift
    public init(onFlushBatch: @escaping (Set<ObjectIdentifier>) -> Void) {
```
→
```swift
    public init(onFlushBatch: @escaping @MainActor (Set<ObjectIdentifier>) -> Void) {
```

3d. The rAF `JSClosure` body — wrap the `@MainActor` hop explicitly (matching `Timing.swift`/`DispatcherBridge.swift`). Change:
```swift
        let closure = JSClosure { [weak self] _ -> JSValue in
            self?.rafFired()
            return .undefined
        }
```
→
```swift
        let closure = JSClosure { [weak self] _ -> JSValue in
            // requestAnimationFrame fires on the main thread; hop onto MainActor
            // explicitly (matching DispatcherBridge.swift / Timing.swift) so the
            // @MainActor scheduler methods are invoked with enforced isolation.
            MainActor.assumeIsolated { self?.rafFired() }
            return .undefined
        }
```

`flush()` keeps calling `onFlushBatch(batch)` unchanged (now an `@MainActor` call from `@MainActor flush`). `markDirty`/`scheduleRAFIfNeeded`/`rafFired`/`rafClosure` bodies are otherwise unchanged.

- [ ] **Step 4: Build for host — the primary gate.**

Run: `swift build`
Expected: **Build complete, no errors and no `sending`/data-race warnings.** This compiles `SyncScheduler` + every `Scheduler` caller (core, SwiflowUI, SwiflowQuery) AND — since JavaScriptKit imports on this host — `RAFScheduler`/`Renderer` under the new annotations.

If the compiler reports an isolation error at a **call site** (not in the scheduler files), that's a genuine previously-unenforced nonisolated caller. Do NOT silence it by reverting the annotation. Assess it:
- If the caller is legitimately on the main actor but lacks the annotation, add `@MainActor` to that caller (it's the correct fix).
- If it's genuinely off-actor (unexpected), STOP and report — the design assumption (all callers MainActor) was wrong and needs the controller/human.
Report any such call-site change.

- [ ] **Step 5: Run the full host test suite.**

Run: `swift test`
Expected: PASS — including `SchedulerTests` (SyncScheduler batching/reentrancy), the scoped-rerender fuzz/diff suites, and everything else. No test should need editing (callers were already MainActor); if a test needs a trivial `@MainActor` annotation to call the now-isolated scheduler, that's acceptable — note it.

- [ ] **Step 6: Build the demo to wasm (confirm `wasm32` compilation).**

Run: `swift build -c release --product swiflow`
Then: `.build/release/swiflow build --path examples/SwiflowUIDemo`
Expected: both succeed — confirms `RAFScheduler`/`Renderer` compile for the real `wasm32` target with the `assumeIsolated` boundary.

- [ ] **Step 7: Commit.**

```bash
# revert any build-regenerated example driver/SW first
git checkout -- examples/SwiflowUIDemo/swiflow-driver.js examples/SwiflowUIDemo/swiflow-service-worker.js 2>/dev/null || true
git add Sources/Swiflow/Reactivity/Scheduler.swift Sources/SwiflowDOM/RAFScheduler.swift
# include any call-site files that needed a legitimate @MainActor (Step 4/5) — list them explicitly
git commit -m "refactor(perf): make Scheduler @MainActor; type-enforce RAFScheduler→flushDirty (#92)

Annotates the Scheduler protocol @MainActor (all callers already are) so both
schedulers are @MainActor/Sendable. RAFScheduler's rAF JSClosure now hops via
MainActor.assumeIsolated (matching Timing/DispatcherBridge) and onFlushBatch is
@MainActor-typed — the isolation is compiler-enforced, not erased. No behavior
change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `swift build` — clean, no `sending`/data-race diagnostics anywhere.
- [ ] `swift test` — full host suite green.
- [ ] `.build/release/swiflow build --path examples/SwiflowUIDemo` — wasm compiles.
- [ ] Working tree clean (no stray example `swiflow-driver.js`/`swiflow-service-worker.js`).
- [ ] Open a PR from `refactor/scheduler-mainactor-isolation` → `main` (`Closes #92`), noting any call-site `@MainActor` annotations that were required (ideally none). **Do not merge** until the user says "merge it -- CI is green" (`gh pr merge <n> --admin --rebase`).

## Spec coverage check

- `@MainActor` protocol + both `@MainActor` classes → Steps 1–3.
- `@MainActor onFlushBatch` + `assumeIsolated` rAF closure → Step 3b/3c/3d.
- No behavior change; no `sending` diagnostics; green build/test/wasm → Steps 4–6.
- Zero call-site churn (or documented isolation-hole fixes) → Step 4 guidance + commit note.
