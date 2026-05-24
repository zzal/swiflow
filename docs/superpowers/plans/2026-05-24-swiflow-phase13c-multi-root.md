# Phase 13c — Multi-Root & Unmount Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the single-root precondition so multiple `Swiflow.render(into:)` calls with different selectors work correctly, add `Swiflow.unmount(into:)` for clean teardown, and update DevAPI to report all roots.

**Architecture:** Make handler IDs and node handles globally unique across all renderers by sharing static counters and a global dispatch table in `HandlerRegistry`, and a single module-level `HandleAllocator` in SwiflowWeb. Replace the single `ambientRenderer` global with a `[String: Renderer]` dict keyed by selector, and a `_currentRenderingRenderer` cursor set/cleared inside `renderOnce()` to support the `.on()` modifier during re-renders.

**Tech Stack:** Swift 6, JavaScriptKit, Swift Testing framework. No JS driver changes. All SwiflowWeb changes are gated behind `#if canImport(JavaScriptKit)` — `swift build` on macOS always succeeds.

---

## File Map

| File | Action |
|---|---|
| `Sources/Swiflow/HandlerRegistry.swift` | Static `nextID` + `globalTable`; add `deinit`; add `dispatchGlobal` |
| `Sources/SwiflowWeb/DispatcherBridge.swift` | Drop `registry` param; dispatch from `HandlerRegistry.dispatchGlobal` |
| `Sources/SwiflowWeb/SwiflowWeb.swift` | Add `renderers`, `_currentRenderingRenderer`, `sharedHandleAllocator`; remove `ambientRenderer`; lift precondition; add `unmount(into:)`; fix `rerender()` |
| `Sources/SwiflowWeb/Renderer.swift` | Add `handles` param with default; set/clear `_currentRenderingRenderer` in `renderOnce()`; add `teardown()` |
| `Sources/SwiflowWeb/AttributeModifiers.swift` | Read `_currentRenderingRenderer` instead of `ambientRenderer` |
| `Sources/SwiflowWeb/DevAPI.swift` | Replace `install(renderer:)` with `installAll()`; multi-root reporting |
| `Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift` | New: 4 tests for global ID uniqueness and deinit cleanup |

---

## Task 1: HandlerRegistry — global ID counter, dispatch table, deinit

**Files:**
- Modify: `Sources/Swiflow/HandlerRegistry.swift`
- Create: `Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift`:

```swift
import Testing
import Swiflow

@Suite("HandlerRegistry multi-root")
struct HandlerRegistryMultiRootTests {

    @Test("Two registries produce non-overlapping handler IDs")
    func nonOverlappingIDs() {
        let a = HandlerRegistry()
        let b = HandlerRegistry()
        let ha = a.register { _ in }
        let hb = b.register { _ in }
        #expect(ha.id != hb.id)
    }

    @Test("dispatchGlobal fires handler registered in registry A")
    func dispatchGlobalRegistryA() {
        let a = HandlerRegistry()
        var fired = false
        let h = a.register { _ in fired = true }
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("dispatchGlobal fires handler registered in registry B")
    func dispatchGlobalRegistryB() {
        let b = HandlerRegistry()
        var fired = false
        let h = b.register { _ in fired = true }
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("deinit sweeps handlers from globalTable; surviving registry still dispatches")
    func deinitSweepsGlobalTable() {
        // Registry B survives the whole test.
        let b = HandlerRegistry()
        var bFired = false
        let hb = b.register { _ in bFired = true }

        // Registry A goes out of scope at the end of the do block.
        let aID: Int
        do {
            let a = HandlerRegistry()
            let ha = a.register { _ in }
            aID = ha.id
        } // a is deallocated here; deinit must sweep aID from globalTable

        // Dispatching to A's swept ID must be a no-op (no crash, no effect).
        HandlerRegistry.dispatchGlobal(id: aID, event: EventInfo(type: "click"))

        // B is unaffected and still dispatches.
        HandlerRegistry.dispatchGlobal(id: hb.id, event: EventInfo(type: "click"))
        #expect(bFired)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter "HandlerRegistryMultiRootTests"
```

Expected: compile error — `HandlerRegistry.dispatchGlobal` not found.

- [ ] **Step 3: Update `HandlerRegistry.swift`**

Make the following changes to `Sources/Swiflow/HandlerRegistry.swift`:

3a. Replace the per-instance `nextID` with a static:
```swift
// Before:
private var nextID: Int = 0

// After:
nonisolated(unsafe) private static var nextID: Int = 0
```

3b. Add the static global dispatch table directly below the new `nextID` line:
```swift
nonisolated(unsafe) private static var globalTable: [Int: EventHandler] = [:]
```

3c. In `register(_:)`, change the ID allocation line and add the global table write:
```swift
// Before:
let id = nextID; nextID += 1
let h = EventHandler(id: id, invoke: invoke)
handlers[id] = h

// After:
let id = Self.nextID; Self.nextID += 1
let h = EventHandler(id: id, invoke: invoke)
handlers[id] = h
Self.globalTable[id] = h
```

3d. In `remove(id:)`, add cleanup of the global table:
```swift
// Before:
package func remove(id: Int) {
    handlers.removeValue(forKey: id)
    if let scopeID = handlerToScope.removeValue(forKey: id) {
        scopes[scopeID]?.ids.removeAll { $0 == id }
    }
}

// After:
package func remove(id: Int) {
    handlers.removeValue(forKey: id)
    Self.globalTable.removeValue(forKey: id)
    if let scopeID = handlerToScope.removeValue(forKey: id) {
        scopes[scopeID]?.ids.removeAll { $0 == id }
    }
}
```

3e. Add `deinit` and `dispatchGlobal` after the `dispatch` method:
```swift
deinit {
    for id in handlers.keys {
        Self.globalTable.removeValue(forKey: id)
    }
}

package static func dispatchGlobal(id: Int, event: EventInfo) {
    globalTable[id]?.invoke(event)
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter "HandlerRegistryMultiRootTests"
```

Expected: all 4 tests pass.

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
swift test
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/HandlerRegistry.swift Tests/SwiflowTests/HandlerRegistryMultiRootTests.swift
git commit -m "feat(registry): global handler ID counter + dispatch table for multi-root"
```

---

## Task 2: DispatcherBridge — drop registry param, dispatch via globalTable

**Files:**
- Modify: `Sources/SwiflowWeb/DispatcherBridge.swift`

The `DispatcherBridge` currently captures one `HandlerRegistry` and dispatches to it. With globally unique handler IDs across all registries, it can dispatch directly from `HandlerRegistry.dispatchGlobal` without needing a registry reference.

- [ ] **Step 1: Rewrite `DispatcherBridge.swift`**

Replace the entire content of `Sources/SwiflowWeb/DispatcherBridge.swift` with:

```swift
// Sources/SwiflowWeb/DispatcherBridge.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Registers a single Swift function as `window.__swiflowDispatch` so the JS
/// driver can route DOM events back to Swift handlers.
///
/// The registered closure expects two arguments from JS:
/// 1. `handlerId: Number` — the integer ID stored in `HandlerRegistry`.
/// 2. `eventPayload: Object` — `{ type: String, targetValue: String? }`.
enum DispatcherBridge {
    /// Strong reference holding the `JSClosure` so it isn't deallocated.
    nonisolated(unsafe) private static var installed: JSClosure?

    /// Idempotent: subsequent calls are no-ops. One JSClosure services all
    /// roots — handler IDs are globally unique across all `HandlerRegistry`
    /// instances (Phase 13c), so `HandlerRegistry.dispatchGlobal` routes
    /// correctly regardless of which root registered the handler.
    static func install() {
        guard installed == nil else { return }

        let closure = JSClosure { args -> JSValue in
            guard
                args.count >= 2,
                let handlerId = args[0].number.map({ Int($0) }),
                let payload = args[1].object
            else {
                return .undefined
            }

            let type = payload.type.string ?? ""
            let targetValue = payload.targetValue.string
            let targetChecked = payload.targetChecked.boolean

            MainActor.assumeIsolated {
                HandlerRegistry.dispatchGlobal(
                    id: handlerId,
                    event: EventInfo(
                        type: type,
                        targetValue: targetValue,
                        targetChecked: targetChecked
                    )
                )
            }

            return .undefined
        }

        JSObject.global.__swiflowDispatch = .object(closure)
        installed = closure
    }
}

#endif
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build
```

Expected: build succeeds. (The call site in `SwiflowWeb.swift` still uses the old `installIfNeeded(registry:)` signature — it will fail to compile. Fix it in the next step by updating the call site immediately.)

Actually, update the call site in the same step. In `Sources/SwiflowWeb/SwiflowWeb.swift`, find the line:
```swift
DispatcherBridge.installIfNeeded(registry: renderer.handlers)
```
and change it to:
```swift
DispatcherBridge.install()
```

Then run:
```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiflowWeb/DispatcherBridge.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "refactor(dispatcher): drop registry param; route via HandlerRegistry.dispatchGlobal"
```

---

## Task 3: SwiflowWeb globals + Renderer handles param + AttributeModifiers cursor

**Files:**
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`
- Modify: `Sources/SwiflowWeb/Renderer.swift`
- Modify: `Sources/SwiflowWeb/AttributeModifiers.swift`

Replace the single `ambientRenderer` global with the three-global pattern from the spec, update `Renderer` inits to accept a shared `HandleAllocator`, and fix `_registerAmbientHandler` to read the render-time cursor.

- [ ] **Step 1: Replace `ambientRenderer` with the three module globals in `SwiflowWeb.swift`**

In `Sources/SwiflowWeb/SwiflowWeb.swift`, inside the `#if canImport(JavaScriptKit)` block, replace:

```swift
// Module-internal ambient renderer — single root per app in Phase 2a.
// `internal` (not `private`) so AttributeModifiers.swift can reach it
// when registering handlers during a render cycle.
nonisolated(unsafe) var ambientRenderer: Renderer?
```

with:

```swift
/// All live roots, keyed by CSS selector. Package-internal so
/// AttributeModifiers.swift and DevAPI.swift can read it.
nonisolated(unsafe) var renderers: [String: Renderer] = [:]

/// Set to the active `Renderer` at the start of each `renderOnce()` call
/// and restored to `nil` in a defer. Lets `.on(_:perform:)` modifiers
/// find the correct registry during both initial renders and RAF re-renders.
nonisolated(unsafe) var _currentRenderingRenderer: Renderer?

/// Single shared handle allocator used by all production `Renderer` instances.
/// Guarantees globally unique node handles across all roots so the JS
/// driver's `nodes` Map never has collisions.
nonisolated(unsafe) let sharedHandleAllocator = HandleAllocator()
```

- [ ] **Step 2: Update `Renderer.init` to accept a shared `HandleAllocator`**

In `Sources/SwiflowWeb/Renderer.swift`, update both inits:

```swift
// Phase 2a init — before:
init(viewProducer: @escaping () -> VNode, selector: String) {
    self.viewProducer = viewProducer
    self.rootComponent = nil
    self.selector = selector
    self.handles = HandleAllocator()
    self.handlers = HandlerRegistry()
    self.mountTree = nil
}

// Phase 2a init — after:
init(viewProducer: @escaping () -> VNode, selector: String, handles: HandleAllocator = sharedHandleAllocator) {
    self.viewProducer = viewProducer
    self.rootComponent = nil
    self.selector = selector
    self.handles = handles
    self.handlers = HandlerRegistry()
    self.mountTree = nil
}
```

```swift
// Phase 3 init — before:
init(rootComponent: AnyComponent, selector: String) {
    self.viewProducer = nil
    self.rootComponent = rootComponent
    self.selector = selector
    self.handles = HandleAllocator()
    self.handlers = HandlerRegistry()
    self.mountTree = nil
    let raf = RAFScheduler { [weak self] in
        self?.renderOnce()
    }
    _schedulerBox.value = raf
}

// Phase 3 init — after:
init(rootComponent: AnyComponent, selector: String, handles: HandleAllocator = sharedHandleAllocator) {
    self.viewProducer = nil
    self.rootComponent = rootComponent
    self.selector = selector
    self.handles = handles
    self.handlers = HandlerRegistry()
    self.mountTree = nil
    let raf = RAFScheduler { [weak self] in
        self?.renderOnce()
    }
    _schedulerBox.value = raf
}
```

- [ ] **Step 3: Fix `_registerAmbientHandler` in `AttributeModifiers.swift`**

In `Sources/SwiflowWeb/AttributeModifiers.swift`, replace:

```swift
@MainActor
func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let renderer = ambientRenderer else {
        fatalError(
            "Swiflow modifier .on(_:perform:) was used before Swiflow.render(into:_:) was called. "
            + "Event handlers must be constructed inside a Component body that the renderer is "
            + "actively building — typically this means you're calling a Swiflow factory at module scope."
        )
    }
    return renderer.handlers.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}
```

with:

```swift
@MainActor
func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let renderer = _currentRenderingRenderer else {
        fatalError(
            "Swiflow modifier .on(_:perform:) was used outside a render cycle. "
            + "Event handlers must be constructed inside a Component body while the renderer is "
            + "actively building the tree. In a multi-root app, ensure each root is mounted via "
            + "Swiflow.render(into:_:) before any component body runs."
        )
    }
    return renderer.handlers.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}
```

- [ ] **Step 4: Verify it compiles**

```bash
swift build
```

Expected: build succeeds. (The `Swiflow.render` method still references `ambientRenderer` — that will be fixed in Task 5. If it fails to compile at `ambientRenderer`, temporarily comment out the `ambientRenderer = renderer` line in `SwiflowWeb.swift`, then continue.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowWeb/SwiflowWeb.swift Sources/SwiflowWeb/Renderer.swift Sources/SwiflowWeb/AttributeModifiers.swift
git commit -m "refactor(web): replace ambientRenderer with renderers dict + render cursor + shared handle allocator"
```

---

## Task 4: Renderer — cursor in `renderOnce()` + `teardown()`

**Files:**
- Modify: `Sources/SwiflowWeb/Renderer.swift`

Add the `_currentRenderingRenderer` cursor to `renderOnce()` so it covers both initial renders and RAF-driven re-renders. Add `teardown()` to destroy the mount tree and cancel the scheduler.

- [ ] **Step 1: Add cursor to `renderOnce()`**

In `Sources/SwiflowWeb/Renderer.swift`, at the very start of `func renderOnce()`, add:

```swift
func renderOnce() {
    _currentRenderingRenderer = self
    defer { _currentRenderingRenderer = nil }

    // ... rest of existing renderOnce() body unchanged ...
```

- [ ] **Step 2: Add `teardown()` to `Renderer`**

Add this method to `Renderer` after `renderOnce()`:

```swift
/// Destroys the mounted tree, emits remove patches to the JS driver,
/// and cancels the RAF scheduler. Called by `Swiflow.unmount(into:)`.
/// Safe to call on an already-torn-down renderer (no-op if mountTree is nil).
package func teardown() {
    guard let tree = mountTree else { return }

    var patches: [Patch] = []
    destroy(tree, into: &patches, handlers: handlers)

    let jsArray = JSObject.global.Array.function!.new()
    for (index, patch) in patches.enumerated() {
        let payload = PatchSerializer.encode(patch)
        jsArray[index] = JSAdapter.toJSValue(payload)
    }
    let swiflowGlobal = JSObject.global.swiflow.object!
    _ = swiflowGlobal.applyPatches!(jsArray)

    // Nil out the scheduler to prevent any pending RAF from triggering
    // a render on a torn-down tree. The weak-self capture in the RAF
    // closure means it becomes a no-op once the RAFScheduler is released.
    _schedulerBox.value = nil
    mountTree = nil
}
```

- [ ] **Step 3: Verify it compiles**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Run tests**

```bash
swift test
```

Expected: all tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowWeb/Renderer.swift
git commit -m "feat(renderer): add render cursor to renderOnce(); add teardown() for unmount"
```

---

## Task 5: Swiflow extension — lift precondition, add `unmount(into:)`, fix `rerender()`

**Files:**
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`

Update the `Swiflow` public extension to support multiple roots.

- [ ] **Step 1: Update `render(into:_:)`**

In `Sources/SwiflowWeb/SwiflowWeb.swift`, inside the `Swiflow` public extension, make the following changes to `render(into:_:)`:

Replace:
```swift
precondition(
    ambientRenderer == nil,
    "Swiflow.render(into:_:) was already called. v1 supports a single root per app; " +
    "a second render would silently drop event dispatch for new handlers because the JS " +
    "dispatcher remains bound to the first registry."
)
```
with:
```swift
precondition(
    renderers[selector] == nil,
    "Swiflow.render(into: \"\(selector)\") was already called. " +
    "Call Swiflow.unmount(into: \"\(selector)\") before mounting a new root at the same selector."
)
```

Replace:
```swift
ambientRenderer = renderer
```
with nothing — this line is deleted. The renderer is stored in `renderers[selector]` **after** `renderOnce()` (see below).

After `renderer.renderOnce()` and the HMR restore cleanup, replace:
```swift
DevAPI.install(renderer: renderer)
```
with:
```swift
renderers[selector] = renderer
DevAPI.installAll()
```

The final `render(into:_:)` body should look like:

```swift
static func render<C: Component>(
    into selector: String,
    _ factory: @escaping @MainActor () -> C
) {
    precondition(
        renderers[selector] == nil,
        "Swiflow.render(into: \"\(selector)\") was already called. " +
        "Call Swiflow.unmount(into: \"\(selector)\") before mounting a new root at the same selector."
    )

    let pendingIndex = HMRBridge.takePendingSnapshot()
    if let index = pendingIndex {
        HMRRestoreInstall.stateFor = { path, typeName, key in
            let lookupKey = SnapshotKey(path: path, typeName: typeName, key: key)
            return index[lookupKey]
        }
    }

    let root = factory()
    CSSInjector.setup()
    let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
    DispatcherBridge.install()
    RefResolverInstall.resolver = { handle in
        guard let swiflowGlobal = JSObject.global.swiflow.object else {
            return nil
        }
        let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
        return result.object
    }

    HMRBridge.installSnapshotExporter { [weak renderer] in
        renderer?.mountTree
    }

    renderer.renderOnce()

    if pendingIndex != nil {
        HMRRestoreInstall.stateFor = nil
    }

    renderers[selector] = renderer
    DevAPI.installAll()
}
```

- [ ] **Step 2: Fix `rerender()`**

Replace:
```swift
static func rerender() {
    ambientRenderer?.renderOnce()
}
```
with:
```swift
static func rerender() {
    renderers.values.forEach { $0.renderOnce() }
}
```

- [ ] **Step 3: Add `unmount(into:)`**

Add this method to the `Swiflow` public extension, after `rerender()`:

```swift
/// Removes the component tree mounted at `selector` from the DOM and
/// releases all associated state, handlers, and the RAF scheduler.
///
/// A no-op if `selector` was never mounted or has already been unmounted.
///
/// Usage:
/// ```swift
/// Swiflow.unmount(into: "#widget")
/// ```
@MainActor
static func unmount(into selector: String) {
    guard let renderer = renderers.removeValue(forKey: selector) else { return }
    renderer.teardown()
    DevAPI.installAll()
}
```

- [ ] **Step 4: Verify it compiles**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Run tests**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat(web): lift single-root precondition; add Swiflow.unmount(into:); fix rerender() for multi-root"
```

---

## Task 6: DevAPI — `installAll()` with per-selector multi-root reporting

**Files:**
- Modify: `Sources/SwiflowWeb/DevAPI.swift`

Replace `install(renderer:)` with `installAll()` that reads from the module-level `renderers` dict and reports all roots.

- [ ] **Step 1: Rewrite `DevAPI.swift`**

Replace the entire content of `Sources/SwiflowWeb/DevAPI.swift` with:

```swift
// Sources/SwiflowWeb/DevAPI.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

enum DevAPI {

    // MARK: - Closure retention

    nonisolated(unsafe) private static var treeClosure: JSClosure?
    nonisolated(unsafe) private static var stateClosure: JSClosure?
    nonisolated(unsafe) private static var handlersClosure: JSClosure?
    nonisolated(unsafe) private static var perfClosure: JSClosure?

    // MARK: - Install

    /// Installs (or re-installs) `window.__swiflow` commands pointing at all
    /// currently mounted roots. Called after every `render(into:)` and
    /// `unmount(into:)` so the API always reflects the live root set.
    ///
    /// All four commands return JS objects keyed by selector when multiple
    /// roots are mounted, and return the same structure for a single root so
    /// existing usage is unchanged.
    @MainActor
    static func installAll() {
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }

        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }

        // tree() — component tree per selector
        let tree = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                guard let mountTree = renderer.mountTree else { continue }
                obj[selector] = .string(DevAPIFormatter.treeString(from: mountTree))
            }
            return .object(obj)
        }
        ns.tree = .object(tree)
        treeClosure = tree

        // state(path) — @State values; searches all roots, first match wins
        let state = JSClosure { args -> JSValue in
            guard let path = args.first?.string else { return .null }
            for renderer in renderers.values {
                guard let mountTree = renderer.mountTree else { continue }
                if let vals = DevAPIFormatter.stateValues(from: mountTree, path: path) {
                    return encodeStateForDisplay(vals)
                }
            }
            return .null
        }
        ns.state = .object(state)
        stateClosure = state

        // handlers() — per-selector handler counts
        let handlers = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                let byScope = renderer.handlers.countPerScope()
                let total = byScope.values.reduce(0, +)
                let entry = JSObject.global.Object.function!.new()
                entry.total = .number(Double(total))
                let scopeObj = JSObject.global.Object.function!.new()
                for (path, count) in byScope {
                    scopeObj[path] = .number(Double(count))
                }
                entry.byScope = .object(scopeObj)
                obj[selector] = .object(entry)
            }
            return .object(obj)
        }
        ns.handlers = .object(handlers)
        handlersClosure = handlers

        // perf() — render stats per selector
        let perf = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                let entry = JSObject.global.Object.function!.new()
                entry.renders = .number(Double(renderer.renderCount))
                entry.lastPatchCount = .number(Double(renderer.lastPatchCount))
                entry.lastRenderMs = .number(renderer.lastRenderMs)
                obj[selector] = .object(entry)
            }
            return .object(obj)
        }
        ns.perf = .object(perf)
        perfClosure = perf
    }

    // MARK: - State encoding

    private static func encodeStateForDisplay(_ state: [String: Any]) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        for (k, v) in state {
            // Bool MUST be checked before Int (Swift bridges Bool to NSNumber).
            if let b = v as? Bool {
                obj[k] = .boolean(b)
            } else if let s = v as? String {
                obj[k] = .string(s)
            } else if let i = v as? Int {
                obj[k] = .number(Double(i))
            } else if let d = v as? Double {
                obj[k] = .number(d)
            } else {
                let mirror = Mirror(reflecting: v)
                if mirror.displayStyle == .optional {
                    if mirror.children.isEmpty {
                        obj[k] = .null
                    } else {
                        let payload = mirror.children.first!.value
                        if let b = payload as? Bool { obj[k] = .boolean(b) }
                        else if let s = payload as? String { obj[k] = .string(s) }
                        else if let i = payload as? Int { obj[k] = .number(Double(i)) }
                        else if let d = payload as? Double { obj[k] = .number(d) }
                    }
                }
            }
        }
        return .object(obj)
    }
}

#endif
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiflowWeb/DevAPI.swift
git commit -m "feat(devapi): installAll() reports all mounted roots keyed by selector"
```

---

## Task 7: Full test suite + README status line

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests pass, including `HandlerRegistryMultiRootTests` (4 tests). Zero regressions.

Verify these suites specifically pass:
- `HandlerRegistryMultiRootTests` — 4 tests
- `DriverEmbedderTests` — `embeddedDriverIsFresh` must pass (no JS changes were made)
- `SwiflowTestingTests` — existing harness tests unaffected

- [ ] **Step 2: Update README status line**

In `README.md`, find the current status line (search for the most recent phase name, e.g. "Phase 13b") and update it to:

```
**Status:** Phase 13c (Multi-Root & Unmount) — Active development toward 1.0
```

Adjust the surrounding context to match the exact line format used in the file.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): update status line to Phase 13c (Multi-Root & Unmount)"
```

---

## Exit Criteria Checklist

Before marking this plan complete, verify:

- [ ] `swift test` passes with zero failures
- [ ] `DriverEmbedderTests.embeddedDriverIsFresh` passes (JS driver unchanged)
- [ ] `HandlerRegistryMultiRootTests` — all 4 tests green
- [ ] `ambientRenderer` no longer exists in any source file: `grep -r "ambientRenderer" Sources/` returns empty
- [ ] `renderers[selector] == nil` precondition is in place in `render(into:)`
- [ ] `Swiflow.unmount(into:)` is public and callable
- [ ] `DevAPI.installAll()` is called from both `render(into:)` and `unmount(into:)`
- [ ] README status line updated
