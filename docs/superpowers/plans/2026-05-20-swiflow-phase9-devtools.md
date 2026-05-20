# Swiflow Phase 9 — Devtools: Component Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `window.__swiflow.tree()`, `.state(path)`, `.handlers()`, and `.perf()` in dev-server builds so frontend engineers can inspect the live component tree from the browser console.

**Architecture:** Pure Swift formatting logic lives in `Sources/Swiflow/DevAPIFormatter.swift` (testable on macOS/Linux); the JavaScript attachment layer lives in `Sources/SwiflowWeb/DevAPI.swift` (WASM-only, gated on `window.SWIFLOW_DEV`). `Swiflow.render()` calls `DevAPI.install(renderer:)` at the end of its body — the same pattern as `HMRBridge.installSnapshotExporter`. `HandlerRegistry` gains named scope tracking so `handlers()` can report counts per component path.

**Tech Stack:** Swift, JavaScriptKit (WASM side only), Swift Testing

---

## File map

| Action | File | What changes |
|---|---|---|
| Modify | `Sources/Swiflow/HandlerRegistry.swift` | Named scopes + `countPerScope()` |
| Modify | `Sources/Swiflow/Diff/Diff.swift` | Pass `path` to `openScope(name:)` |
| Modify | `Sources/SwiflowWeb/Renderer.swift` | Add `renderCount`, `lastPatchCount`, `lastRenderMs` |
| Create | `Sources/Swiflow/DevAPIFormatter.swift` | `treeString(from:)` + `stateValues(from:path:)` |
| Create | `Sources/SwiflowWeb/DevAPI.swift` | JS attachment: all 4 devtools closures |
| Modify | `Sources/SwiflowWeb/SwiflowWeb.swift` | Call `DevAPI.install(renderer:)` |
| Create | `Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift` | Named scope tests |
| Create | `Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift` | Tree + state formatter tests |
| Create | `docs/guides/devtools.md` | User guide |

---

### Task 1: Named scopes in HandlerRegistry

The `handlers()` devtools function needs a per-component-path count of registered handlers. `HandlerRegistry` currently tracks scopes as an anonymous stack (`[[Int]]`). This task adds a parallel name array and a `countPerScope()` read accessor.

**Files:**
- Modify: `Sources/Swiflow/HandlerRegistry.swift`
- Create: `Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift`:

```swift
// Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift
import Testing
@testable import Swiflow

@Suite("HandlerRegistry: named scopes")
struct HandlerRegistryNamedScopeTests {

    @Test("openScope(name:) with two named scopes reports per-scope counts")
    func namedScopesCounts() {
        let r = HandlerRegistry()
        r.openScope(name: "0")
        r.register { _ in }
        r.register { _ in }
        r.openScope(name: "1")
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["0"] == 2)
        #expect(counts["1"] == 1)
        #expect(counts.values.reduce(0, +) == 3)
    }

    @Test("closeScope removes its name from countPerScope()")
    func closeScopeRemovesName() {
        let r = HandlerRegistry()
        r.openScope(name: "A")
        r.register { _ in }
        r.closeScope()
        #expect(r.countPerScope()["A"] == nil)
        #expect(r.countPerScope().isEmpty)
    }

    @Test("openScope() with default name uses empty string key")
    func defaultNameIsEmptyString() {
        let r = HandlerRegistry()
        r.openScope()   // no name argument
        r.register { _ in }
        #expect(r.countPerScope()[""] == 1)
    }

    @Test("countPerScope is empty when no scopes are open")
    func emptyWhenNoScopes() {
        let r = HandlerRegistry()
        r.register { _ in }    // registration outside any scope
        #expect(r.countPerScope().isEmpty)
    }

    @Test("duplicate scope names accumulate counts")
    func duplicateNamesAccumulate() {
        let r = HandlerRegistry()
        r.openScope(name: "x")
        r.register { _ in }
        r.openScope(name: "x")
        r.register { _ in }
        r.register { _ in }
        let counts = r.countPerScope()
        #expect(counts["x"] == 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter HandlerRegistryNamedScopeTests 2>&1 | tail -20
```

Expected: compile error — `openScope(name:)` and `countPerScope()` don't exist yet.

- [ ] **Step 3: Implement named scopes in HandlerRegistry**

Open `Sources/Swiflow/HandlerRegistry.swift`. The current `scopeStack` declaration is at line 17. Make these changes:

```swift
package final class HandlerRegistry {
    private var nextID: Int = 0
    private var handlers: [Int: EventHandler] = [:]
    private var scopeStack: [[Int]] = []
    private var scopeNames: [String] = []   // ADD THIS LINE

    package init() {}

    @discardableResult
    package func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = nextID
        nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(id)
        }
        return h
    }

    package func handler(forID id: Int) -> EventHandler? { handlers[id] }
    package func remove(id: Int) { handlers.removeValue(forKey: id) }
    package func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

    // REPLACE the old openScope() with:
    package func openScope(name: String = "") {
        scopeStack.append([])
        scopeNames.append(name)
    }

    // REPLACE the old closeScope() with:
    package func closeScope() {
        guard let ids = scopeStack.popLast() else { return }
        if !scopeNames.isEmpty { scopeNames.removeLast() }
        for id in ids { handlers.removeValue(forKey: id) }
    }

    // ADD this new method:
    /// Returns the count of currently-registered handlers for each open named scope.
    /// Scopes opened with the default `openScope()` call are keyed under `""`.
    /// Scopes with duplicate names have their counts summed.
    package func countPerScope() -> [String: Int] {
        var result: [String: Int] = [:]
        for (name, ids) in zip(scopeNames, scopeStack) {
            result[name, default: 0] += ids.count
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter HandlerRegistryNamedScopeTests 2>&1 | tail -10
```

Expected: all 5 tests pass.

- [ ] **Step 5: Run full test suite for regressions**

```bash
swift test 2>&1 | tail -5
```

Expected: all existing tests still pass. The `openScope()` call signature is backward-compatible (default `name: ""`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/HandlerRegistry.swift Tests/SwiflowTests/HandlerRegistryNamedScopeTests.swift
git commit -m "feat(devtools): HandlerRegistry named scopes + countPerScope()"
```

---

### Task 2: Thread component path into openScope

`Diff.swift` currently calls `handlers.openScope()` without a name when mounting a component anchor. Now that `openScope(name:)` accepts a path, we pass `path` so `handlers()` can report per-component counts.

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`

- [ ] **Step 1: Find the openScope call**

In `Sources/Swiflow/Diff/Diff.swift`, search for `handlers.openScope()` — it appears around line 221 in the `mount()` function's `.component` case, right before `instance.instance.body` is evaluated.

- [ ] **Step 2: Change the call**

Replace:
```swift
handlers.openScope()
```
With:
```swift
handlers.openScope(name: path)
```

No other changes needed. The `closeScope()` call in `destroy()` (around line 478) is unchanged.

- [ ] **Step 3: Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: all tests pass. No behavioral change — only the name stored alongside each scope changes.

- [ ] **Step 4: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift
git commit -m "feat(devtools): thread component path into HandlerRegistry.openScope(name:)"
```

---

### Task 3: Renderer perf counters

`perf()` reads three counters from the live `Renderer`. These are stored properties incremented inside `renderOnce()`.

**Files:**
- Modify: `Sources/SwiflowWeb/Renderer.swift`

Note: `Renderer` is WASM-only (`#if canImport(JavaScriptKit)`). These counters cannot be tested from the macOS test target. Correctness is verified by `swift build` + the WASM e2e harness.

- [ ] **Step 1: Add stored properties**

In `Sources/SwiflowWeb/Renderer.swift`, after the `mountTree` property (around line 45), add:

```swift
/// Cumulative count of `renderOnce()` calls since this Renderer was created.
/// Read by `DevAPI` to populate `__swiflow.perf().renders`.
private(set) var renderCount: Int = 0

/// Count of patches emitted by the most recent `renderOnce()` call.
/// Read by `DevAPI` to populate `__swiflow.perf().lastPatchCount`.
private(set) var lastPatchCount: Int = 0

/// Wall-clock duration of the most recent `renderOnce()` call, in milliseconds.
/// Measured via `window.performance.now()`. Read by `DevAPI` to populate
/// `__swiflow.perf().lastRenderMs`.
private(set) var lastRenderMs: Double = 0
```

- [ ] **Step 2: Instrument renderOnce()**

In `renderOnce()`, wrap the `diff(...)` call to capture timing and patch count. Replace the block starting at `let result = diff(` with:

```swift
let renderStartMs = JSObject.global.performance.now().number ?? 0
let result = diff(
    mounted: mountTree,
    next: nextVNode,
    handles: handles,
    handlers: handlers,
    scheduler: _schedulerBox.value
)
lastPatchCount = result.patches.count
renderCount += 1
lastRenderMs = (JSObject.global.performance.now().number ?? 0) - renderStartMs
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```

Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowWeb/Renderer.swift
git commit -m "feat(devtools): Renderer perf counters (renderCount, lastPatchCount, lastRenderMs)"
```

---

### Task 4: DevAPIFormatter — tree string and state lookup

The formatting logic lives in `Sources/Swiflow/` (no JavaScriptKit dependency) so it is testable from the macOS/Linux test target. `DevAPI.swift` (Task 5) calls these functions and wraps the results in `JSValue`.

**Files:**
- Create: `Sources/Swiflow/DevAPIFormatter.swift`
- Create: `Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift`

- [ ] **Step 1: Write failing tests**

Create directory and test file:

```bash
mkdir -p Tests/SwiflowTests/DevAPI
```

Create `Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift`:

```swift
// Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift
import Testing
@testable import Swiflow

// MARK: - Shared test components

private final class Leaf: Component {
    var body: VNode { .text("x") }
}

private final class Outer: Component {
    var body: VNode { .text("") }
}

private final class Counted: Component {
    @State var count: Int = 0
    var body: VNode { .text("") }
}

// MARK: - Tree string tests

@Suite("DevAPIFormatter: treeString")
@MainActor
struct DevAPIFormatterTreeTests {

    @Test("single component with text body → short type name and empty path")
    func singleComponent() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text("x"))
        )
        let out = DevAPIFormatter.treeString(from: anchor)
        #expect(out == #"Leaf """#)
    }

    @Test("component whose direct body is another component gets [body→] marker")
    func nestedComponentBody() {
        let innerAnchor = MountNode(
            handle: 2,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: innerAnchor
        )
        let lines = DevAPIFormatter.treeString(from: outerAnchor).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Outer "" [body→]"#)
        #expect(lines[1] == #"  Leaf """#)
    }

    @Test("component whose body is an element (not a component) gets no [body→] marker")
    func elementBodyNoMarker() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        let out = DevAPIFormatter.treeString(from: anchor)
        #expect(!out.contains("[body→]"))
    }

    @Test("element node with two component children → indexed paths, same indent level")
    func elementWithTwoComponentChildren() {
        let child0 = MountNode(
            handle: 2,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let child1 = MountNode(
            handle: 4,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: MountNode(handle: 5, vnode: .text(""))
        )
        // Non-component wrapper (simulates an element node)
        let element = MountNode(handle: 1, vnode: .text(""), children: [child0, child1])
        let lines = DevAPIFormatter.treeString(from: element).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Leaf "0""#)
        #expect(lines[1] == #"Outer "1""#)
    }

    @Test("deeper nesting produces correct indentation and paths")
    func deepNesting() {
        // Outer (path "") → element body → Leaf (path "0")
        let leafAnchor = MountNode(
            handle: 4,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 5, vnode: .text(""))
        )
        let elementBody = MountNode(handle: 3, vnode: .text(""), children: [leafAnchor])
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: elementBody
        )
        let lines = DevAPIFormatter.treeString(from: outerAnchor).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Outer """#)
        #expect(lines[1] == #"  Leaf "0""#)
    }
}

// MARK: - State values tests

@Suite("DevAPIFormatter: stateValues")
@MainActor
struct DevAPIFormatterStateTests {

    @Test("stateValues returns nil when path has no matching component")
    func unknownPathReturnsNil() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        #expect(DevAPIFormatter.stateValues(from: anchor, path: "99") == nil)
    }

    @Test("stateValues returns current @State values for the matching path")
    func matchingPathReturnsValues() {
        let c = Counted()
        c.count = 42
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Counted.self) { Counted() }),
            component: AnyComponent(c),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        let vals = DevAPIFormatter.stateValues(from: anchor, path: "")
        #expect((vals?["count"] as? Int) == 42)
    }

    @Test("stateValues finds a component at a nested path")
    func nestedPath() {
        let c = Counted()
        c.count = 7
        let nestedAnchor = MountNode(
            handle: 2,
            vnode: .component(.init(Counted.self) { Counted() }),
            component: AnyComponent(c),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let element = MountNode(handle: 1, vnode: .text(""), children: [nestedAnchor])
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: element
        )
        let vals = DevAPIFormatter.stateValues(from: outerAnchor, path: "0")
        #expect((vals?["count"] as? Int) == 7)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter DevAPIFormatterTests 2>&1 | tail -10
```

Expected: compile error — `DevAPIFormatter` doesn't exist yet.

- [ ] **Step 3: Create DevAPIFormatter.swift**

Create `Sources/Swiflow/DevAPIFormatter.swift`:

```swift
// Sources/Swiflow/DevAPIFormatter.swift
//
// Pure Swift formatting helpers for the Phase 9 devtools API.
// Lives in core (no JavaScriptKit) so the macOS test target can cover it.
// DevAPI.swift (SwiflowWeb) calls these and wraps results in JSValue.

/// Pure Swift helpers for the `window.__swiflow` devtools API.
/// All functions are `@MainActor` because they read `MountNode` trees
/// that are owned by the main-actor-isolated `Renderer`.
@MainActor
package enum DevAPIFormatter {

    // MARK: - tree()

    /// Builds an indented string representation of the component tree
    /// rooted at `root`. Only component-anchor nodes are emitted; element
    /// and text nodes are invisible. Each line reads:
    ///   `<indent><TypeName> "<path>"[ [body→]]`
    /// where `[body→]` appears when the component's direct body is itself
    /// a component (sharing the same path).
    package static func treeString(from root: MountNode) -> String {
        var lines: [String] = []
        walkTree(root, path: "", depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func walkTree(
        _ node: MountNode,
        path: String,
        depth: Int,
        into lines: inout [String]
    ) {
        if let anyC = node.component {
            // Emit this component anchor.
            let typeName = String(reflecting: type(of: anyC.instance))
            let shortName = typeName.split(separator: ".").last.map(String.init) ?? typeName
            let bodyMark = (node.componentBody?.component != nil) ? " [body→]" : ""
            lines.append(String(repeating: "  ", count: depth) + shortName + " \"\(path)\"" + bodyMark)
            // Recurse into the component's rendered body at depth + 1.
            if let body = node.componentBody {
                walkTree(body, path: path, depth: depth + 1, into: &lines)
            }
        } else {
            // Non-component node (element or text) — recurse into children
            // at the same depth, assigning indexed paths.
            for (i, child) in node.children.enumerated() {
                let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
                walkTree(child, path: childPath, depth: depth, into: &lines)
            }
        }
    }

    // MARK: - state(path)

    /// Returns the raw `@State` value map for the component at `path`,
    /// or `nil` if no component exists at that path.
    /// Keys are field names (leading `_` stripped by HMRWalker).
    /// Values are the current snapshot primitives (`Int`, `Double`, `String`,
    /// `Bool`, `Optional.none` as `nil`). Non-serialisable types are absent.
    package static func stateValues(from root: MountNode, path: String) -> [String: Any]? {
        let snapshots = HMRWalker.snapshot(from: root)
        return snapshots.first(where: { $0.path == path })?.state
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter DevAPIFormatterTests 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 5: Run full test suite for regressions**

```bash
swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/DevAPIFormatter.swift Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift
git commit -m "feat(devtools): DevAPIFormatter — treeString + stateValues"
```

---

### Task 5: DevAPI.swift — JS attachment + SwiflowWeb wiring

Attaches `tree`, `state`, `handlers`, and `perf` as `JSClosure` instances on the existing `window.__swiflow` namespace object. Gated on `window.SWIFLOW_DEV`. Wired into `Swiflow.render()` with one line.

**Files:**
- Create: `Sources/SwiflowWeb/DevAPI.swift`
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`

This file is WASM-only; there are no macOS unit tests for the JS attachment. Correctness is verified by `swift build` (no errors) and manual browser console inspection.

- [ ] **Step 1: Create DevAPI.swift**

Create `Sources/SwiflowWeb/DevAPI.swift`:

```swift
// Sources/SwiflowWeb/DevAPI.swift
//
// Phase 9 — Devtools JS bridge.
// Attaches window.__swiflow.tree / .state / .handlers / .perf
// when window.SWIFLOW_DEV is true (set by the CLI dev server).
// The `DevAPI.install(renderer:)` call in SwiflowWeb.swift is the
// only entry point; all closures are stored statically to prevent
// ARC reclaim while the page is live.

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

package enum DevAPI {

    // MARK: - Closure retention

    /// JSClosure instances must outlive every call. Stored statically,
    /// same pattern as HMRBridge.snapshotClosure.
    nonisolated(unsafe) private static var treeClosure: JSClosure?
    nonisolated(unsafe) private static var stateClosure: JSClosure?
    nonisolated(unsafe) private static var handlersClosure: JSClosure?
    nonisolated(unsafe) private static var perfClosure: JSClosure?

    // MARK: - Install

    /// Attaches devtools functions to `window.__swiflow` when
    /// `window.SWIFLOW_DEV === true`. No-op in production builds.
    @MainActor
    package static func install(renderer: Renderer) {
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }

        // Re-use the existing __swiflow namespace (created by HMRBridge).
        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }

        // tree() — indented component tree as a string
        let tree = JSClosure { [weak renderer] _ -> JSValue in
            guard let mountTree = renderer?.mountTree else {
                return .string("(no tree — renderer not mounted)")
            }
            return .string(DevAPIFormatter.treeString(from: mountTree))
        }
        ns.tree = .object(tree)
        treeClosure = tree

        // state(path) — @State values for the component at path
        let state = JSClosure { [weak renderer] args -> JSValue in
            guard let mountTree = renderer?.mountTree,
                  let path = args.first?.string else {
                return .null
            }
            guard let vals = DevAPIFormatter.stateValues(from: mountTree, path: path) else {
                return .null
            }
            return encodeStateForDisplay(vals)
        }
        ns.state = .object(state)
        stateClosure = state

        // handlers() — total + per-scope counts
        let handlers = JSClosure { [weak renderer] _ -> JSValue in
            guard let renderer else { return .null }
            let byScope = renderer.handlers.countPerScope()
            let total = byScope.values.reduce(0, +)
            let obj = JSObject.global.Object.function!.new()
            obj.total = .number(Double(total))
            let scopeObj = JSObject.global.Object.function!.new()
            for (path, count) in byScope {
                scopeObj[path] = .number(Double(count))
            }
            obj.byScope = .object(scopeObj)
            return .object(obj)
        }
        ns.handlers = .object(handlers)
        handlersClosure = handlers

        // perf() — render count, last patch count, last render ms
        let perf = JSClosure { [weak renderer] _ -> JSValue in
            guard let renderer else { return .null }
            let obj = JSObject.global.Object.function!.new()
            obj.renders = .number(Double(renderer.renderCount))
            obj.lastPatchCount = .number(Double(renderer.lastPatchCount))
            obj.lastRenderMs = .number(renderer.lastRenderMs)
            return .object(obj)
        }
        ns.perf = .object(perf)
        perfClosure = perf
    }

    // MARK: - State encoding

    /// Converts a `[String: Any]` snapshot map to a plain JS object.
    /// Mirrors HMRBridge.encodeStateMap — same type-coercion rules,
    /// same Optional handling. Kept private here to avoid making
    /// HMRBridge's private helper package-visible.
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
                // Other types (structs, enums, etc.) — omit silently.
            }
        }
        return .object(obj)
    }
}

#endif
```

- [ ] **Step 2: Wire DevAPI into Swiflow.render()**

Open `Sources/SwiflowWeb/SwiflowWeb.swift`. After the `renderer.renderOnce()` call and the HMR cleanup block (the `if pendingIndex != nil { HMRRestoreInstall.stateFor = nil }` block), add:

```swift
DevAPI.install(renderer: renderer)
```

The updated end of `Swiflow.render()` reads:

```swift
        renderer.renderOnce()

        // Phase 8: clear the install slot after the first render
        // completes. Subsequent reactivity-driven renders should
        // not re-restore.
        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }

        // Phase 9: install devtools API (no-op in production).
        DevAPI.install(renderer: renderer)
    }
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` with no errors.

- [ ] **Step 4: Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowWeb/DevAPI.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat(devtools): DevAPI.swift JS attachment + wire into Swiflow.render()"
```

---

### Task 6: docs/guides/devtools.md

**Files:**
- Create: `docs/guides/devtools.md`

- [ ] **Step 1: Create the guide**

```bash
mkdir -p docs/guides
```

Create `docs/guides/devtools.md`:

```markdown
# Swiflow Devtools

The `window.__swiflow` browser console API is available in dev-server builds
(started with `swiflow dev`). It is absent in production builds.

## Opening devtools

Open your browser's developer console (F12) while `swiflow dev` is running.
You'll see the live API on `window.__swiflow`.

## tree()

Prints an indented view of the live component tree.

```js
__swiflow.tree()
```

Example output:

```
App ""
  Sidebar ""
    NavItem "0"
    MainArea "1"
      Counter "1.0"
      Counter "1.1"
```

Each line shows the component's **short type name** and its **path** (the
dot-joined child-index string the framework uses internally). Components
whose direct rendered body is another component show `[body→]` to indicate
they share the same path.

Use `tree()` to find the path you need before calling `state()`.

## state(path)

Returns the current `@State` values for the component at `path`.

```js
__swiflow.state("1.0")
// → { count: 5, label: "clicks" }
```

Returns `null` if no component exists at the given path. The path is the
string shown in `tree()` output, including the quotes — but pass it without
quotes in the call: `state("1.0")` not `state('"1.0"')`.

Supported value types: `Int`, `Double`, `String`, `Bool`, `Optional` of those
types (`null` for `Optional.none`). Custom types are omitted.

## handlers()

Reports how many event handlers are currently registered, broken down by
component path scope.

```js
__swiflow.handlers()
// → { total: 14, byScope: { "": 2, "1.0": 6, "1.1": 4, "1.2": 2 } }
```

A scope whose count grows unboundedly across re-renders (visible if you call
`handlers()` several times) indicates a handler leak.

## perf()

Reports render performance metrics for the most recent render cycle.

```js
__swiflow.perf()
// → { renders: 7, lastPatchCount: 3, lastRenderMs: 1.2 }
```

- **renders**: total number of `renderOnce()` calls since page load.
- **lastPatchCount**: number of DOM patches applied in the last render.
- **lastRenderMs**: wall-clock duration of the last render, in milliseconds.

A high `lastPatchCount` on a simple state change usually points to a
missing key on a list of sibling components.
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/devtools.md
git commit -m "docs(devtools): devtools browser console guide"
```

---

## Verification checklist

After all tasks complete:

1. `swift test` passes with no regressions and the new named-scope and formatter tests all green.
2. `swift build` succeeds (covering the WASM-only files).
3. `__swiflow.tree()` returns a non-empty indented string when called in a dev-server browser session after mounting the Counter template.
4. `__swiflow.state("")` returns `{ count: 0 }` for a freshly mounted Counter.
5. `__swiflow.handlers()` returns `{ total: N, byScope: { ... } }` with non-zero totals after a click handler is registered.
6. `__swiflow.perf()` shows `renders: 1` on first load, incrementing on each state change.
7. All four functions return `undefined` (not installed) when loaded from a production build (no `SWIFLOW_DEV` in scope).
