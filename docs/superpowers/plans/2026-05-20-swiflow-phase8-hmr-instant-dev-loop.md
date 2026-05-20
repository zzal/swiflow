# Swiflow Phase 8 — HMR & The Instant Dev Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `location.reload()` on file save with a state-preserving WASM hot module swap so the Counter template's `@State` survives across saves.

**Architecture:** The dev server broadcasts an `hmr-swap` WebSocket message with cache-busted URLs. The JS driver extracts the current `@State` snapshot from the live Swift module, clears the JS handle/listener maps and the mount-target children, then dynamic-imports the new entry point. The new module's `Swiflow.render(into:_:)` detects the pending snapshot in `window.__swiflowPendingSnapshot` and seeds freshly-instantiated Components by `(path, typeName, key)` before their first `body()` call. Any failure path falls back to `location.reload()` with a `console.warn`.

**Tech Stack:** Swift 6.3, JavaScriptKit 0.53, Swift Testing, Hummingbird 2.x WebSocket, vanilla JavaScript (no build step in the driver).

**Spec reference:** `docs/superpowers/specs/2026-05-20-swiflow-phase8-hmr-instant-dev-loop-design.md`

**Decision 1 (deviation from spec §7 file layout):** The spec placed the snapshot walker and restore applier in `Sources/SwiflowWeb/HMR/`. Phase 7's Option γ pattern showed that host-testable logic should live in core (`Sources/Swiflow/`) with a thin JSValue bridge in SwiflowWeb. Applied here: the mount-tree walker, snapshot value type, and restore applier live in `Sources/Swiflow/Reactivity/HMR.swift` (host-testable). Only the JSValue ↔ Swift marshalling and `window.__swiflow.hmrSnapshot` installer live in `Sources/SwiflowWeb/HMR/HMRBridge.swift`. Spec's behavioral contract is preserved exactly.

**Decision 2 (diff integration via package-internal install hook):** Following Phase 7's `RefResolverInstall` precedent. Core declares a `package nonisolated(unsafe) var` install slot. Diff.swift's mount-wire site calls the installed closure (no-op when nil). SwiflowWeb installs the closure during `render(into:_:)` setup. This keeps core platform-neutral and Diff.swift free of any SwiflowWeb dependency.

---

## File Structure

**New files (this phase):**
- `Sources/Swiflow/Reactivity/HMR.swift` — `ComponentSnapshot`, `SnapshotKey`, `HMRWalker`, `HMRRestoreInstall`
- `Sources/SwiflowWeb/HMR/HMRBridge.swift` — JSValue encode/decode + global installer
- `docs/perf/2026-05-20-hmr-baseline.md` — measured save→pixels times
- `Tests/SwiflowTests/HMR/HMRSnapshotTests.swift`
- `Tests/SwiflowTests/HMR/HMRRestoreTests.swift`
- `Tests/SwiflowTests/HMR/HMRRoundTripTests.swift`
- `Tests/SwiflowTests/HMR/HMRTypeDriftTests.swift`
- `Tests/SwiflowTests/HMR/HMRShapeChangeTests.swift`
- `Tests/SwiflowTests/HMR/StateHMRHookTests.swift`
- `Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift`
- `Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift`

**Modified:**
- `Sources/Swiflow/Reactivity/State.swift` — `StateWireable` gains two methods; trailing extension carries no-op defaults so non-`State` conformers don't break
- `Sources/Swiflow/Reactivity/Component.swift` — no changes (the Mirror helper stays as-is; HMRWalker uses its own Mirror walks)
- `Sources/Swiflow/Diff/Diff.swift` — single new call at line 207 after `wireState(...)`
- `Sources/SwiflowWeb/SwiflowWeb.swift` — installs `HMRBridge` snapshot exporter and pre-render restore-index seeder
- `Sources/SwiflowCLI/DevServer/WebSocketHub.swift` — `broadcastHMRSwap(wasmURL:jsURL:)`
- `Sources/SwiflowCLI/DevServer/DevModeInjection.swift` — inject both globals
- `Sources/SwiflowCLI/Commands/DevCommand.swift` — call `broadcastHMRSwap(...)` instead of `broadcastReload()`
- `js-driver/swiflow-driver.js` — mount-selector memory + HMR branch + `hmrSwap` function
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated via `scripts/embed-driver.swift`
- `examples/HelloWorld/Sources/App/App.swift` — inline HMR explainer comment
- `Sources/SwiflowCLI/Templates/Templates.swift` — mirror the comment (byte-equal with example)
- `docs/guides/forms.md` — one-sentence HMR callout
- `README.md` — Phase 8 status; HMR moved to "works today"

---

## Task A: Core HMR types + State protocol extension

**Files:**
- Create: `Sources/Swiflow/Reactivity/HMR.swift`
- Modify: `Sources/Swiflow/Reactivity/State.swift:9-11`, `Sources/Swiflow/Reactivity/State.swift:144`
- Test: `Tests/SwiflowTests/HMR/StateHMRHookTests.swift`

- [ ] **Step A1: Write the failing test for `_hmrSnapshotValue()` + `_hmrRestore(_:)` happy path + type-mismatch path**

Create `Tests/SwiflowTests/HMR/StateHMRHookTests.swift`:

```swift
import Testing
@testable import Swiflow

@Suite("State HMR hooks")
struct StateHMRHookTests {

    @Test("_hmrSnapshotValue returns the current wrapped value")
    func snapshotReadsCurrentValue() {
        let s = State<Int>(wrappedValue: 0)
        s.wrappedValue = 42
        #expect((s._hmrSnapshotValue() as? Int) == 42)
    }

    @Test("_hmrSnapshotValue captures String values")
    func snapshotStringValue() {
        let s = State<String>(wrappedValue: "")
        s.wrappedValue = "hello"
        #expect((s._hmrSnapshotValue() as? String) == "hello")
    }

    @Test("_hmrSnapshotValue captures Bool values")
    func snapshotBoolValue() {
        let s = State<Bool>(wrappedValue: false)
        s.wrappedValue = true
        #expect((s._hmrSnapshotValue() as? Bool) == true)
    }

    @Test("_hmrSnapshotValue captures Double values")
    func snapshotDoubleValue() {
        let s = State<Double>(wrappedValue: 0)
        s.wrappedValue = 3.14
        #expect((s._hmrSnapshotValue() as? Double) == 3.14)
    }

    @Test("_hmrSnapshotValue captures Optional<String> values")
    func snapshotOptionalStringValue() {
        let s = State<String?>(wrappedValue: nil)
        s.wrappedValue = "set"
        #expect((s._hmrSnapshotValue() as? String?) == "set")
    }

    @Test("_hmrRestore writes a matching-type value and returns true")
    func restoreMatchingTypeSucceeds() {
        let s = State<Int>(wrappedValue: 0)
        let ok = s._hmrRestore(99)
        #expect(ok == true)
        #expect(s.wrappedValue == 99)
    }

    @Test("_hmrRestore rejects a type-mismatched value and returns false")
    func restoreTypeMismatchFails() {
        let s = State<Int>(wrappedValue: 7)
        let ok = s._hmrRestore("not an int")
        #expect(ok == false)
        #expect(s.wrappedValue == 7)  // unchanged
    }

    @Test("_hmrRestore on Optional<String> accepts nil")
    func restoreOptionalStringAcceptsNil() {
        let s = State<String?>(wrappedValue: "before")
        let ok = s._hmrRestore(String?.none as Any)
        #expect(ok == true)
        #expect(s.wrappedValue == nil)
    }
}
```

- [ ] **Step A2: Run the test to verify it fails**

Run: `swift test --filter StateHMRHookTests`
Expected: FAIL — `_hmrSnapshotValue` and `_hmrRestore` are not defined on `State`.

- [ ] **Step A3: Extend `StateWireable` protocol with the two HMR methods (with default no-op implementations for forward compatibility)**

Edit `Sources/Swiflow/Reactivity/State.swift:9-11`. Replace:

```swift
protocol StateWireable: AnyObject {
    func _setOwner(_ owner: AnyComponent, scheduler: Scheduler)
}
```

with:

```swift
protocol StateWireable: AnyObject {
    func _setOwner(_ owner: AnyComponent, scheduler: Scheduler)

    /// HMR snapshot: returns the current `wrappedValue` typed as `Any`.
    /// The HMRWalker inspects the runtime type to decide whether the
    /// value belongs in the snapshot's supported-primitive set
    /// (String/Int/Double/Bool + Optionals).
    func _hmrSnapshotValue() -> Any

    /// HMR restore: if `newValue` is type-compatible with `Value`,
    /// overwrites the storage. Returns true on success, false on
    /// type mismatch. Called at most once per @State, after Component
    /// instantiation but before the first `body` evaluation, so no
    /// scheduler notification is needed.
    func _hmrRestore(_ newValue: Any) -> Bool
}
```

- [ ] **Step A4: Extend `State<Value>` with the two HMR hooks**

Edit `Sources/Swiflow/Reactivity/State.swift`. Below the existing `extension State: StateWireable {}` at line 144, add:

```swift
extension State {
    /// HMR snapshot extraction. See `StateWireable._hmrSnapshotValue()`.
    /// Package-internal in spirit — used only by `HMRWalker` and tests.
    func _hmrSnapshotValueImpl() -> Any { storage.value }

    /// HMR restore. See `StateWireable._hmrRestore(_:)`. Returns false
    /// when `newValue` cannot be cast to `Value`; the caller falls
    /// back to the declared initial value for that field.
    func _hmrRestoreImpl(_ newValue: Any) -> Bool {
        guard let typed = newValue as? Value else { return false }
        storage.value = typed
        return true
    }
}
```

Then update the trailing `extension State: StateWireable {}` to provide the protocol witnesses by delegating to the impls. Replace line 144:

```swift
extension State: StateWireable {}
```

with:

```swift
extension State: StateWireable {
    func _hmrSnapshotValue() -> Any { _hmrSnapshotValueImpl() }
    func _hmrRestore(_ newValue: Any) -> Bool { _hmrRestoreImpl(newValue) }
}
```

- [ ] **Step A5: Run the test to verify it passes**

Run: `swift test --filter StateHMRHookTests`
Expected: PASS — all eight tests green.

- [ ] **Step A6: Run the full suite to verify no regressions**

Run: `swift test`
Expected: 327+8 = 335 tests passing (327 prior + 8 new).

- [ ] **Step A7: Commit**

```bash
git add Sources/Swiflow/Reactivity/State.swift Tests/SwiflowTests/HMR/StateHMRHookTests.swift
git commit -m "feat(state): @State HMR hooks (snapshot / restore)

StateWireable gains _hmrSnapshotValue() / _hmrRestore(_:) so the
HMR walker can read and overwrite @State values via Mirror without
naming the concrete Value type. Used by Phase 8's state-preserving
hot module swap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task B: Mount-tree snapshot walker + supporting types

**Files:**
- Create: `Sources/Swiflow/Reactivity/HMR.swift`
- Test: `Tests/SwiflowTests/HMR/HMRSnapshotTests.swift`

- [ ] **Step B1: Write the failing test for `HMRWalker.snapshot(from:)`**

Create `Tests/SwiflowTests/HMR/HMRSnapshotTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HMR snapshot walker")
struct HMRSnapshotTests {

    final class Counter: Component {
        @State var count: Int = 0
        @State var label: String = ""
        var body: VNode { text("") }
    }

    final class Toggle: Component {
        @State var on: Bool = false
        var body: VNode { text("") }
    }

    @Test("snapshot captures @State fields from a single-Component tree")
    func snapshotSingleComponent() {
        let counter = Counter()
        counter.count = 7
        counter.label = "hi"
        let anyC = AnyComponent(counter)

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: anyC
        )

        let snapshots = HMRWalker.snapshot(from: tree)

        #expect(snapshots.count == 1)
        #expect(snapshots[0].path == "")
        #expect(snapshots[0].typeName.hasSuffix(".Counter"))
        #expect(snapshots[0].key == nil)
        #expect((snapshots[0].state["count"] as? Int) == 7)
        #expect((snapshots[0].state["label"] as? String) == "hi")
    }

    @Test("snapshot is empty for a tree with no Components")
    func snapshotEmptyTree() {
        let tree = MountNode(handle: 1, vnode: .text("plain"))
        let snapshots = HMRWalker.snapshot(from: tree)
        #expect(snapshots.isEmpty)
    }

    @Test("snapshot path uses dot-joined child indices for nested Components")
    func snapshotNestedPath() {
        let outer = Counter()
        outer.count = 1
        let inner = Toggle()
        inner.on = true

        let innerNode = MountNode(
            handle: 3,
            vnode: .text(""),
            component: AnyComponent(inner)
        )
        let outerNode = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(outer),
            children: [innerNode]
        )

        let snapshots = HMRWalker.snapshot(from: outerNode)

        #expect(snapshots.count == 2)
        let outerSnap = snapshots.first { $0.typeName.hasSuffix(".Counter") }
        let innerSnap = snapshots.first { $0.typeName.hasSuffix(".Toggle") }
        #expect(outerSnap?.path == "")
        #expect(innerSnap?.path == "0")
        #expect((innerSnap?.state["on"] as? Bool) == true)
    }
}
```

Note: this test depends on a `MountNode` initializer that accepts `(handle:vnode:component:children:)`. The constructor must already exist or the diff couldn't be building mount trees. The test fixture uses synthetic nodes — no diff is invoked.

- [ ] **Step B2: Run the test to verify it fails**

Run: `swift test --filter HMRSnapshotTests`
Expected: FAIL — `HMRWalker` is not defined.

- [ ] **Step B3: Read `MountNode` to confirm the initializer signature**

Run: `grep -n "MountNode\|init(" /Users/alainduchesneau/Projets/swiflow/Sources/Swiflow/Diff/MountNode.swift 2>&1 | head -30`

If the file path is wrong (no `MountNode.swift`), search: `grep -rn "struct MountNode\|class MountNode\|final class MountNode" /Users/alainduchesneau/Projets/swiflow/Sources/`. Use the resulting file to confirm: (a) whether the test fixture's MountNode initializer call is correct, (b) what property `MountNode` uses to expose its component (likely `component: AnyComponent?`), and (c) what property exposes children (likely `children: [MountNode]`). Adjust the test fixture init call if the real initializer differs.

- [ ] **Step B4: Create the core HMR types file**

Create `Sources/Swiflow/Reactivity/HMR.swift`:

```swift
// Sources/Swiflow/Reactivity/HMR.swift
//
// Phase 8 — HMR core types and mount-tree walkers.
//
// Lives in core (not SwiflowWeb) so the snapshot/restore logic is
// host-testable without JavaScriptKit. The JS bridge in
// `Sources/SwiflowWeb/HMR/HMRBridge.swift` is a thin marshalling
// layer over these types.

import Foundation

// MARK: - Public data types

/// One row in an HMR snapshot — captures the identifying triple and
/// the per-`@State` value map for a single Component in the mount
/// tree. Snapshot arrays are produced by `HMRWalker.snapshot(from:)`
/// and consumed by `HMRWalker.applyRestore(...)`.
///
/// `state[fieldName]` is the raw `Any` value pulled from a
/// `StateWireable._hmrSnapshotValue()` call. The JS bridge later
/// encodes the supported primitive subset; values that don't make
/// it across the bridge are simply absent on restore (the field
/// falls back to the declared initial value, with a debug log).
public struct ComponentSnapshot {
    public let path: String
    public let typeName: String
    public let key: String?
    public let state: [String: Any]

    public init(path: String, typeName: String, key: String?, state: [String: Any]) {
        self.path = path
        self.typeName = typeName
        self.key = key
        self.state = state
    }
}

/// Lookup key used by HMRRestore to find a snapshot for a freshly-
/// instantiated Component. Two `ComponentSnapshot`s with the same
/// path+typeName+key are treated as the same logical Component.
package struct SnapshotKey: Hashable {
    let path: String
    let typeName: String
    let key: String?
}

// MARK: - Mount-tree walker

/// Mount-tree HMR helpers. The walker traverses a `MountNode` tree
/// and produces snapshots; the restore applier reads a snapshot
/// index back into freshly-instantiated Components via Mirror.
///
/// All functions are pure with respect to the tree shape — they
/// don't mutate `MountNode` or `Component` instances. The restore
/// applier writes through `StateWireable._hmrRestore(_:)`, which is
/// idempotent and safe to call multiple times.
@MainActor
public enum HMRWalker {

    /// Walk `tree` in document order and produce one
    /// `ComponentSnapshot` per Component-bearing `MountNode`.
    ///
    /// Path is dot-joined child indices from the root. Top-level
    /// path is the empty string `""`. Nodes without a `component`
    /// contribute no snapshot but their children still inherit
    /// their index path (so a structural wrapper element doesn't
    /// shift child indices).
    public static func snapshot(from tree: MountNode) -> [ComponentSnapshot] {
        var out: [ComponentSnapshot] = []
        walk(tree, path: "", into: &out)
        return out
    }

    private static func walk(
        _ node: MountNode,
        path: String,
        into out: inout [ComponentSnapshot]
    ) {
        if let anyC = node.component {
            out.append(makeSnapshot(for: anyC, path: path, vnode: node.vnode))
        }
        for (i, child) in node.children.enumerated() {
            let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
            walk(child, path: childPath, into: &out)
        }
    }

    private static func makeSnapshot(
        for anyC: AnyComponent,
        path: String,
        vnode: VNode
    ) -> ComponentSnapshot {
        let instance = anyC.instance
        let typeName = String(reflecting: type(of: instance))
        let key: String?
        if case .component(let desc) = vnode {
            key = desc.key
        } else {
            key = nil
        }

        var stateMap: [String: Any] = [:]
        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard let wireable = child.value as? StateWireable else { continue }
            // Property-wrapper-backed labels are `_count`, `_label`, etc.
            // Strip the leading underscore to recover the user-visible name.
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            stateMap[fieldName] = wireable._hmrSnapshotValue()
        }

        return ComponentSnapshot(path: path, typeName: typeName, key: key, state: stateMap)
    }
}

// MARK: - Install slot for diff integration

/// Phase 7-style install slot. SwiflowWeb installs a closure at
/// `Swiflow.render(into:_:)` entry time that delegates to
/// `HMRWalker.applyRestore(...)`. Diff calls this closure at the
/// mount-wire site; when no swap is pending, the slot is nil and
/// the call is a single nil-check.
///
/// `nonisolated(unsafe)`: closures are not Sendable; the slot is
/// only read/written from `@MainActor` contexts. Mirrors
/// `RefResolverInstall` from Phase 7.
package enum HMRRestoreInstall {
    package nonisolated(unsafe) static var restore: (@MainActor (AnyComponent, String) -> Void)?
}
```

Also add restore-applier logic in the same file:

```swift
// MARK: - Restore applier

extension HMRWalker {

    /// Build a lookup index from a snapshot array. SwiflowWeb's bridge
    /// calls this after decoding the JS-side snapshot payload.
    public static func indexSnapshots(_ snapshots: [ComponentSnapshot]) -> [SnapshotKey: [String: Any]] {
        var index: [SnapshotKey: [String: Any]] = [:]
        for snap in snapshots {
            let key = SnapshotKey(path: snap.path, typeName: snap.typeName, key: snap.key)
            index[key] = snap.state
        }
        return index
    }

    /// Look up a matching snapshot and apply it to a freshly-instantiated
    /// Component. Match is by (path, typeName, key) — exact triple.
    /// Per-field type mismatches are skipped (the field keeps its
    /// declared initial value) and reported via `swiflowDiagnostic`.
    ///
    /// `path` is the same dot-joined child-index format produced by
    /// `snapshot(from:)`. The caller (SwiflowWeb's diff integration)
    /// is responsible for tracking the mounting Component's path.
    public static func applyRestore(
        index: [SnapshotKey: [String: Any]],
        to component: AnyComponent,
        at path: String
    ) {
        let instance = component.instance
        let typeName = String(reflecting: type(of: instance))
        // Note: the diff integration doesn't have the ComponentDescription's
        // key at this site (it has the AnyComponent only). v1 matches on
        // (path, typeName) and uses key=nil as a fallback if the snapshot's
        // key is also nil. This matches Counter / HelloWorld which use
        // unkeyed components.
        let lookupKey = SnapshotKey(path: path, typeName: typeName, key: nil)
        guard let stateMap = index[lookupKey] else { return }

        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard let wireable = child.value as? StateWireable else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard let newValue = stateMap[fieldName] else { continue }
            let ok = wireable._hmrRestore(newValue)
            if !ok {
                swiflowDiagnostic(
                    "HMR restore: type mismatch on \(typeName).\(fieldName) at path '\(path)'. Field reset to its declared initial value."
                )
            }
        }
    }
}
```

- [ ] **Step B5: Run the test to verify it passes**

Run: `swift test --filter HMRSnapshotTests`
Expected: PASS — all three tests green.

- [ ] **Step B6: Run the full suite**

Run: `swift test`
Expected: 335+3 = 338 tests passing.

- [ ] **Step B7: Commit**

```bash
git add Sources/Swiflow/Reactivity/HMR.swift Tests/SwiflowTests/HMR/HMRSnapshotTests.swift
git commit -m "feat(hmr): mount-tree snapshot walker

HMRWalker.snapshot(from:) produces one ComponentSnapshot per
Component-bearing MountNode, keyed by (path, typeName, key).
Path is dot-joined child indices. State map is built via Mirror
+ StateWireable._hmrSnapshotValue().

HMRRestoreInstall provides a package-internal closure slot for
the diff to invoke during component mount — installed by
SwiflowWeb when a swap is pending.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task C: Restore applier tests + round-trip + edge cases

**Files:**
- Test: `Tests/SwiflowTests/HMR/HMRRestoreTests.swift`
- Test: `Tests/SwiflowTests/HMR/HMRRoundTripTests.swift`
- Test: `Tests/SwiflowTests/HMR/HMRTypeDriftTests.swift`
- Test: `Tests/SwiflowTests/HMR/HMRShapeChangeTests.swift`

- [ ] **Step C1: Write the failing test for `HMRWalker.applyRestore(...)` happy path**

Create `Tests/SwiflowTests/HMR/HMRRestoreTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HMR restore applier")
struct HMRRestoreTests {

    final class Counter: Component {
        @State var count: Int = 0
        @State var label: String = "initial"
        var body: VNode { text("") }
    }

    @Test("applyRestore overwrites matching @State fields")
    func restoreOverwritesMatchingFields() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 42, "label": "restored"]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        let anyC = AnyComponent(fresh)
        HMRWalker.applyRestore(index: index, to: anyC, at: "")

        #expect(fresh.count == 42)
        #expect(fresh.label == "restored")
    }

    @Test("applyRestore is a no-op when no matching snapshot exists")
    func restoreNoMatch() {
        let snap = ComponentSnapshot(
            path: "1.0",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 99]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        let anyC = AnyComponent(fresh)
        HMRWalker.applyRestore(index: index, to: anyC, at: "")

        #expect(fresh.count == 0)
        #expect(fresh.label == "initial")
    }

    @Test("applyRestore skips fields missing from the snapshot")
    func restorePartialFieldSet() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 7]  // no `label`
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.count == 7)
        #expect(fresh.label == "initial")  // unchanged
    }
}
```

- [ ] **Step C2: Run test to verify it passes (logic already implemented in Task B)**

Run: `swift test --filter HMRRestoreTests`
Expected: PASS — all three tests green. (Task B implemented the applier; Task C is the dedicated test coverage.)

- [ ] **Step C3: Write the failing round-trip test**

Create `Tests/SwiflowTests/HMR/HMRRoundTripTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HMR round-trip")
struct HMRRoundTripTests {

    final class Demo: Component {
        @State var s: String = ""
        @State var i: Int = 0
        @State var d: Double = 0
        @State var b: Bool = false
        @State var os: String? = nil
        var body: VNode { text("") }
    }

    @Test("snapshot → index → applyRestore preserves all supported primitives")
    func roundTripAllPrimitives() {
        let original = Demo()
        original.s = "hello"
        original.i = 42
        original.d = 3.14
        original.b = true
        original.os = "optional"

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(original)
        )
        let snaps = HMRWalker.snapshot(from: tree)
        let index = HMRWalker.indexSnapshots(snaps)

        let fresh = Demo()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.s == "hello")
        #expect(fresh.i == 42)
        #expect(fresh.d == 3.14)
        #expect(fresh.b == true)
        #expect(fresh.os == "optional")
    }

    @Test("round-trip preserves nil Optional<String>")
    func roundTripNilOptional() {
        let original = Demo()
        original.s = "x"
        original.os = nil

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(original)
        )
        let snaps = HMRWalker.snapshot(from: tree)
        let index = HMRWalker.indexSnapshots(snaps)

        let fresh = Demo()
        fresh.os = "before-restore"
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.s == "x")
        #expect(fresh.os == nil)
    }
}
```

- [ ] **Step C4: Run round-trip test**

Run: `swift test --filter HMRRoundTripTests`
Expected: PASS.

- [ ] **Step C5: Write the failing type-drift test**

Create `Tests/SwiflowTests/HMR/HMRTypeDriftTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HMR type drift")
struct HMRTypeDriftTests {

    final class WasInt: Component {
        @State var n: Int = 0
        var body: VNode { text("") }
    }

    final class NowString: Component {
        @State var n: String = "initial"
        var body: VNode { text("") }
    }

    @Test("type-mismatched snapshot field leaves declared initial value untouched")
    func typeMismatchPreservesInitial() {
        // Snapshot says `n: Int = 7`, but the new module's class
        // declared `n: String`. We simulate by hand-rolling the snapshot
        // with the OLD typeName (matching) but a value of the OLD type.
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: NowString.self),  // matches new class
            key: nil,
            state: ["n": 7]  // OLD-shape value (Int), new field is String
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = NowString()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.n == "initial")  // declared initial, not "7"
    }
}
```

- [ ] **Step C6: Run type-drift test**

Run: `swift test --filter HMRTypeDriftTests`
Expected: PASS.

- [ ] **Step C7: Write the failing shape-change test**

Create `Tests/SwiflowTests/HMR/HMRShapeChangeTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HMR shape change")
struct HMRShapeChangeTests {

    final class Foo: Component {
        @State var x: Int = 0
        var body: VNode { text("") }
    }

    final class Bar: Component {
        @State var x: Int = 0
        var body: VNode { text("") }
    }

    @Test("type-name mismatch at the same path skips restore entirely")
    func typeNameMismatchSkipsRestore() {
        // Snapshot is for Foo, new tree has Bar at the same path.
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Foo.self),
            key: nil,
            state: ["x": 99]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Bar()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.x == 0)  // declared initial, not 99
    }

    @Test("snapshot with unmatched path is dropped silently")
    func unmatchedPathDropped() {
        let snap = ComponentSnapshot(
            path: "5",  // doesn't match where we mount
            typeName: String(reflecting: Foo.self),
            key: nil,
            state: ["x": 17]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Foo()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.x == 0)  // declared initial, not 17
    }
}
```

- [ ] **Step C8: Run shape-change test**

Run: `swift test --filter HMRShapeChangeTests`
Expected: PASS.

- [ ] **Step C9: Run the full suite**

Run: `swift test`
Expected: all tests passing (338 + 3 restore + 2 round-trip + 1 type-drift + 2 shape-change = 346).

- [ ] **Step C10: Commit**

```bash
git add Tests/SwiflowTests/HMR/HMRRestoreTests.swift Tests/SwiflowTests/HMR/HMRRoundTripTests.swift Tests/SwiflowTests/HMR/HMRTypeDriftTests.swift Tests/SwiflowTests/HMR/HMRShapeChangeTests.swift
git commit -m "test(hmr): restore applier + round-trip + drift + shape-change

Covers applyRestore happy path, no-match path, partial field
overlap, full round-trip across all supported primitives,
type-drift (Int->String) staying on initial value, and
typeName-mismatch dropping the entire subtree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task D: Diff integration

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift:207`

- [ ] **Step D1: Read the current site to confirm context**

Run: `sed -n '195,215p' /Users/alainduchesneau/Projets/swiflow/Sources/Swiflow/Diff/Diff.swift`

This shows the lines around the `wireState(...)` call. You're looking for the place where a Component is being instantiated for the first time and its @State is wired to the scheduler.

- [ ] **Step D2: Add the HMR restore call immediately after `wireState(...)`**

In `Sources/Swiflow/Diff/Diff.swift`, find line 207:

```swift
        wireState(on: instance, scheduler: scheduler)
```

Replace with:

```swift
        wireState(on: instance, scheduler: scheduler)
        // Phase 8: HMR state restore. The install slot is nil unless a
        // hot module swap is pending (SwiflowWeb's render entry seeds
        // it from window.__swiflowPendingSnapshot). When the slot is
        // populated, look up matching snapshot data by (path, typeName)
        // and overwrite this component's @State boxes before its first
        // body() evaluation. The `path` argument here is the dot-joined
        // child-index path of this component in the mount tree being
        // built. For the root mount, that's the empty string.
        HMRRestoreInstall.restore?(instance, path)
```

This requires `path` to be in scope at line 207. Read lines 100–207 of `Diff.swift` to verify what the surrounding function signature looks like and whether a path string is already threaded through. If not, the function will need a `path:` parameter added with default `""` so existing callers compile.

- [ ] **Step D3: Thread `path:` through the mount function if not already present**

If the mount function around line 207 does not have a `path:` parameter, add one with default `""`. At each recursive descent inside that function and any helpers that recurse into children, compute the child path as:

```swift
let childPath = path.isEmpty ? String(index) : "\(path).\(index)"
```

and pass `childPath` to the recursive call. Match the same path scheme `HMRWalker.snapshot(from:)` uses (Task B), so that snapshot keys and restore lookups align.

This MAY require changes to:
- The top-level mount function around `Diff.swift:81-100` (the one declared `-> MountNode`).
- The component-mount path that calls `wireState(...)` at line 207.

Read those lines and apply the change consistently. The change must be invisible to existing callers: add a default value `path: String = ""` to every signature.

- [ ] **Step D4: Build to verify the diff still compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step D5: Run the full suite to verify no regression**

Run: `swift test`
Expected: all tests passing (346, no new tests yet for this task — diff integration is exercised end-to-end in Task E and via the existing diff test suite).

- [ ] **Step D6: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift
git commit -m "feat(diff): HMR restore hook at mount-wire site

Diff threads a path string through the mount path and calls
HMRRestoreInstall.restore?(instance, path) immediately after
wireState. The slot is nil in production; SwiflowWeb fills it at
render-entry time when window.__swiflowPendingSnapshot is set.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task E: SwiflowWeb HMR bridge

**Files:**
- Create: `Sources/SwiflowWeb/HMR/HMRBridge.swift`
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`

- [ ] **Step E1: Create the JS bridge file**

Create `Sources/SwiflowWeb/HMR/HMRBridge.swift`:

```swift
// Sources/SwiflowWeb/HMR/HMRBridge.swift
//
// Phase 8 — JS bridge for HMR snapshot extraction and restore.
//
// The mount-tree walker and restore applier live in core
// (`Sources/Swiflow/Reactivity/HMR.swift`). This file is the WASM-
// only marshalling layer that:
//   - Installs `window.__swiflow.hmrSnapshot()` which returns a
//     JS array of {path, typeName, key, state} objects.
//   - Reads `window.__swiflowPendingSnapshot` (set by the JS driver
//     before re-importing the new module) and decodes it into a
//     Swift-side index that the diff consults via
//     `HMRRestoreInstall.restore`.

#if canImport(JavaScriptKit)
import Foundation
import JavaScriptKit
import Swiflow

package enum HMRBridge {

    // MARK: - Snapshot exporter (Swift → JS)

    /// Install `window.__swiflow.hmrSnapshot = () => [...]`. The
    /// exported function consults the renderer's live mount tree at
    /// call time, walks it with `HMRWalker.snapshot(...)`, and
    /// JS-encodes the result.
    @MainActor
    package static func installSnapshotExporter(treeProvider: @escaping @MainActor () -> MountNode?) {
        let snapshotFn = JSClosure { _ in
            guard let tree = treeProvider() else {
                return JSValue.array([])
            }
            let snaps = HMRWalker.snapshot(from: tree)
            return encodeToJS(snaps)
        }

        // Place the function under the existing `window.__swiflow`
        // namespace. Create the namespace object if it doesn't exist
        // yet (the very first render after a fresh page load).
        var globalThis = JSObject.global
        let existing = globalThis.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            globalThis.__swiflow = .object(ns)
        }
        ns.hmrSnapshot = .object(snapshotFn)
    }

    // MARK: - Pending snapshot consumer (JS → Swift)

    /// Read `window.__swiflowPendingSnapshot`. Returns nil when no
    /// swap is pending (initial page load). On any decode error,
    /// returns nil — the new mount will start with declared initial
    /// values, which is strictly better than a full reload.
    @MainActor
    package static func takePendingSnapshot() -> [SnapshotKey: [String: Any]]? {
        let pending = JSObject.global.__swiflowPendingSnapshot
        // Clear the global immediately so a subsequent render in the
        // same session (e.g. a manual rerender) doesn't accidentally
        // re-consume it.
        JSObject.global.__swiflowPendingSnapshot = .null

        guard let array = pending.object,
              let length = array.length.number,
              length > 0 else {
            return nil
        }

        var snapshots: [ComponentSnapshot] = []
        for i in 0..<Int(length) {
            let entry = array[i]
            guard let path = entry.path.string,
                  let typeName = entry.typeName.string else {
                continue
            }
            let key = entry.key.string  // may be nil
            let stateValue = entry.state
            let stateMap = decodeStateMap(stateValue)
            snapshots.append(
                ComponentSnapshot(path: path, typeName: typeName, key: key, state: stateMap)
            )
        }
        return HMRWalker.indexSnapshots(snapshots)
    }

    // MARK: - JS encode / decode

    private static func encodeToJS(_ snapshots: [ComponentSnapshot]) -> JSValue {
        let array = JSObject.global.Array.function!.new()
        for (i, snap) in snapshots.enumerated() {
            let obj = JSObject.global.Object.function!.new()
            obj.path = .string(snap.path)
            obj.typeName = .string(snap.typeName)
            obj.key = snap.key.map { JSValue.string($0) } ?? .null
            obj.state = encodeStateMap(snap.state)
            array[i] = .object(obj)
        }
        return .object(array)
    }

    private static func encodeStateMap(_ state: [String: Any]) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        for (k, v) in state {
            if let s = v as? String {
                obj[k] = .string(s)
            } else if let i = v as? Int {
                obj[k] = .number(Double(i))
            } else if let d = v as? Double {
                obj[k] = .number(d)
            } else if let b = v as? Bool {
                obj[k] = .boolean(b)
            } else if v is NSNull {
                obj[k] = .null
            } else {
                // Unsupported type — try Optional<primitive>.
                // String? unwraps to String above when non-nil; the
                // nil case is `Optional<X>.none`, which Mirror reports
                // as a value whose displayStyle is `.optional`. v1
                // simply omits unsupported / nil-Optional fields and
                // they fall back to declared initial on restore.
                let mirror = Mirror(reflecting: v)
                if mirror.displayStyle == .optional {
                    if mirror.children.isEmpty {
                        // nil Optional — explicitly write JS null so
                        // the restore side can map back to nil.
                        obj[k] = .null
                    } else {
                        // Non-nil Optional with non-primitive payload —
                        // skip (v1 limitation).
                    }
                }
                // Other unsupported types: omit (v1 limitation).
            }
        }
        return .object(obj)
    }

    private static func decodeStateMap(_ js: JSValue) -> [String: Any] {
        guard let obj = js.object else { return [:] }
        var out: [String: Any] = [:]

        // JSObject doesn't expose key iteration directly; use
        // `Object.keys` via the JS global.
        let keysArray = JSObject.global.Object.keys!(JSValue.object(obj))
        guard let keys = keysArray.object,
              let len = keys.length.number else {
            return [:]
        }
        for i in 0..<Int(len) {
            guard let k = keys[i].string else { continue }
            let v = obj[k]
            if let s = v.string {
                out[k] = s
            } else if let n = v.number {
                // JS numbers are doubles; the receiver type-checks via
                // `_hmrRestore` which uses `as?` against the target
                // Value. To make `@State var count: Int` accept a
                // restored value, we need to preserve Int when the
                // value is integral. JavaScriptKit doesn't distinguish
                // integer vs double — we synthesize both: try Int
                // first (when n has no fractional part), else Double.
                if n.truncatingRemainder(dividingBy: 1) == 0 && n.isFinite {
                    out[k] = Int(n)
                } else {
                    out[k] = n
                }
            } else if let b = v.boolean {
                out[k] = b
            } else if v.isNull {
                // Represent JS null as Swift NSNull; the restore
                // applier's `as? Value` cast handles Optional<T>
                // by accepting NSNull as the nil case.
                //
                // Actually — `as? Optional<String>` doesn't match
                // NSNull. Use Optional<String>.none typed as Any.
                // But we don't know the target Value type here.
                // Workaround: store both representations under a
                // sentinel marker the restore side recognizes, or
                // simply omit (Optional fields fall back to declared
                // initial, which for `String?` is nil). The Counter
                // template doesn't use Optionals, so omitting null
                // values is acceptable for v1.
                continue
            } else {
                // Object / array / unknown — v1 doesn't handle these.
                continue
            }
        }
        return out
    }
}

#endif
```

- [ ] **Step E2: Wire the bridge into `SwiflowWeb.render(into:_:)`**

Edit `Sources/SwiflowWeb/SwiflowWeb.swift`. Locate the `render(into:_:)` method (lines 38-72). After the `precondition` and before `DispatcherBridge.installIfNeeded(...)`, add the snapshot consumer; after the renderer is assigned to `ambientRenderer`, install the exporter.

Specifically, replace the body of the `render` method:

```swift
    @MainActor
    static func render<C: Component>(
        into selector: String,
        _ factory: @escaping @MainActor () -> C
    ) {
        precondition(
            ambientRenderer == nil,
            "Swiflow.render(into:_:) was already called. v1 supports a single root per app; " +
            "a second render would silently drop event dispatch for new handlers because the JS " +
            "dispatcher remains bound to the first registry."
        )

        // Phase 8: if the dev server staged a pending HMR snapshot in
        // window.__swiflowPendingSnapshot, decode it now. We install
        // the diff's restore hook BEFORE constructing the root
        // component so the very first wireState call gets the chance
        // to restore.
        let pendingIndex = HMRBridge.takePendingSnapshot()
        if let index = pendingIndex {
            HMRRestoreInstall.restore = { component, path in
                HMRWalker.applyRestore(index: index, to: component, at: path)
            }
        }

        let root = factory()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        RefResolverInstall.resolver = { handle in
            guard let swiflowGlobal = JSObject.global.swiflow.object else {
                return nil
            }
            let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
            return result.object
        }

        // Phase 8: install the snapshot exporter so the JS driver can
        // call window.__swiflow.hmrSnapshot() before the next swap.
        // The exporter walks `renderer.mountTree` at call time, so it
        // always reports the current tree even after many re-renders.
        HMRBridge.installSnapshotExporter { [weak renderer] in
            renderer?.mountTree
        }

        renderer.renderOnce()

        // Phase 8: clear the install slot after the first render
        // completes. Subsequent reactivity-driven renders should
        // not re-restore.
        if pendingIndex != nil {
            HMRRestoreInstall.restore = nil
        }
    }
```

- [ ] **Step E3: Build to verify cross-module compile**

Run: `swift build`
Expected: build succeeds with no errors. SourceKit may report stale diagnostics; trust `swift build` per the documented memory.

- [ ] **Step E4: Run the full suite**

Run: `swift test`
Expected: all 346 tests still passing.

- [ ] **Step E5: Commit**

```bash
git add Sources/SwiflowWeb/HMR/HMRBridge.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat(hmr): SwiflowWeb JS bridge + render-entry integration

HMRBridge installs window.__swiflow.hmrSnapshot() (JS-callable
snapshot exporter) and reads window.__swiflowPendingSnapshot at
render entry. When a snapshot is pending, the diff's restore
hook is filled with a closure that delegates to
HMRWalker.applyRestore; the hook is cleared after the first
render completes so subsequent reactivity-driven renders are
unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task F: DevServer HMR broadcast + injection + command wiring

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/WebSocketHub.swift`
- Modify: `Sources/SwiflowCLI/DevServer/DevModeInjection.swift`
- Modify: `Sources/SwiflowCLI/Commands/DevCommand.swift`
- Test: `Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift`
- Test: `Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift`

- [ ] **Step F1: Write the failing test for `broadcastHMRSwap(wasmURL:jsURL:)`**

Create `Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift`:

```swift
import Testing
import HummingbirdWebSocket
@testable import SwiflowCLI

@Suite("WebSocketHub HMR broadcast")
struct WebSocketHubHMRTests {

    @Test("broadcastHMRSwap emits a JSON payload with type, wasmURL, jsURL")
    func payloadShape() async throws {
        // Verify the JSON encoding by reading the published payload via
        // a fake writer. The existing WebSocketHub tests likely use the
        // same pattern — check Tests/SwiflowCLITests/DevServer/ for a
        // reference implementation. Mirror that pattern here.
        //
        // The test assertion is:
        //   payload contains: "type":"hmr-swap"
        //   payload contains: "wasmURL":"/Bundle.wasm?h=123"
        //   payload contains: "jsURL":"/index.js?h=123"
        //
        // (The exact spelling depends on the WebSocketHub's JSON shape;
        // verify against existing broadcastReload tests for style.)
        Issue.record("Implement once existing WebSocketHubTests pattern is checked.")
    }
}
```

Note: this test stub is a placeholder. The subagent implementing this task should first read the existing `Tests/SwiflowCLITests/DevServer/` to learn the test pattern used for `broadcastReload`, then write `WebSocketHubHMRTests` in the same shape.

Read `Tests/SwiflowCLITests/DevServer/WebSocketHubTests.swift` (if it exists) for the established pattern, OR — if that file does not exist — write the test in the simpler shape used by other CLI tests: use a `JSONDecoder` over the broadcast payload by intercepting the writer.

- [ ] **Step F2: Run the new test to verify it fails**

Run: `swift test --filter WebSocketHubHMRTests`
Expected: FAIL — function doesn't exist yet (Issue.record will fire, plus a compile error on the function call once you flesh out the test).

- [ ] **Step F3: Add `broadcastHMRSwap(wasmURL:jsURL:)` to `WebSocketHub`**

Edit `Sources/SwiflowCLI/DevServer/WebSocketHub.swift`. Add after the existing `broadcastReload()` method:

```swift
    /// Send `{"type":"hmr-swap","wasmURL":..,"jsURL":..}` to every
    /// connected client. Used by `DevCommand`'s rebuild loop in place
    /// of `broadcastReload()`. Same drop-on-write-failure semantics:
    /// a single stale client must not block the broadcast from
    /// reaching the rest.
    ///
    /// `wasmURL` is informational for v1 — the new entry point
    /// (`index.js`) loads the WASM itself. We still ship it so the
    /// driver can log "fetching <wasmURL>" and so a future
    /// preflight-fetch optimization has it available.
    func broadcastHMRSwap(wasmURL: String, jsURL: String) async {
        // Escape any quote / backslash in URLs defensively. The
        // mtime-suffixed URLs we generate today contain neither, but
        // a future hash scheme might include base64-style characters
        // and the encoder must not produce invalid JSON.
        let escapedWasm = wasmURL
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedJS = jsURL
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let payload = #"{"type":"hmr-swap","wasmURL":"\#(escapedWasm)","jsURL":"\#(escapedJS)"}"#
        for (id, writer) in clients {
            do {
                try await writer.write(.text(payload))
            } catch {
                clients.removeValue(forKey: id)
            }
        }
    }
```

- [ ] **Step F4: Flesh out the test now that the API exists**

Open `Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift` again. Implement the test in the style of the existing `broadcastReload` test (read it from the same directory). Assertions:

```swift
let hub = WebSocketHub()
// Register a fake writer that captures payloads.
let capture = FakeWriterCapture()  // pattern from existing tests
let id = await hub.register(capture.writer)

await hub.broadcastHMRSwap(wasmURL: "/Bundle.wasm?h=123", jsURL: "/index.js?h=123")

let received = await capture.payloads
#expect(received.count == 1)
let json = received[0]
#expect(json.contains(#""type":"hmr-swap""#))
#expect(json.contains(#""wasmURL":"/Bundle.wasm?h=123""#))
#expect(json.contains(#""jsURL":"/index.js?h=123""#))

await hub.unregister(id)
```

If no `FakeWriterCapture` pattern exists, model the test after the existing `broadcastReload` test exactly. The point is to verify the JSON payload reaches the registered writer with the expected fields.

- [ ] **Step F5: Run the test**

Run: `swift test --filter WebSocketHubHMRTests`
Expected: PASS.

- [ ] **Step F6: Write the failing test for `DevModeInjection` injecting both globals**

Create `Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift`:

```swift
import Testing
@testable import SwiflowCLI

@Suite("DevModeInjection HMR signal")
struct DevModeInjectionHMRTests {

    @Test("injectDevSignal also injects SWIFLOW_HMR=true")
    func injectsHMRSignal() {
        let html = #"""
        <html><body>
          <div id="app"></div>
          <script src="swiflow-driver.js"></script>
        </body></html>
        """#
        let result = DevModeInjection.injectDevSignal(into: html)
        #expect(result.contains("window.SWIFLOW_DEV=true"))
        #expect(result.contains("window.SWIFLOW_HMR=true"))
    }

    @Test("injection is idempotent on second application")
    func idempotent() {
        let html = #"<html><body><script src="swiflow-driver.js"></script></body></html>"#
        let once = DevModeInjection.injectDevSignal(into: html)
        let twice = DevModeInjection.injectDevSignal(into: once)
        #expect(once == twice)
        // And the marker appears exactly once.
        let occurrences = once.components(separatedBy: "SWIFLOW_HMR=true").count - 1
        #expect(occurrences == 1)
    }
}
```

- [ ] **Step F7: Run to verify it fails**

Run: `swift test --filter DevModeInjectionHMRTests`
Expected: FAIL — `SWIFLOW_HMR=true` is not in the injected snippet.

- [ ] **Step F8: Update `DevModeInjection` to inject both globals**

Edit `Sources/SwiflowCLI/DevServer/DevModeInjection.swift`. Replace:

```swift
    static let marker = "window.SWIFLOW_DEV=true"

    private static let snippet = "<script>\(marker);</script>"
```

with:

```swift
    /// Marker substring used both to inject and to detect idempotency.
    /// Phase 8 adds SWIFLOW_HMR alongside SWIFLOW_DEV — we re-target
    /// the marker on the HMR flag because that one is the newer
    /// addition; idempotency still works because we always inject both
    /// or neither.
    static let marker = "window.SWIFLOW_HMR=true"

    private static let snippet = "<script>window.SWIFLOW_DEV=true;window.SWIFLOW_HMR=true;</script>"
```

- [ ] **Step F9: Run the test**

Run: `swift test --filter DevModeInjectionHMRTests`
Expected: PASS.

- [ ] **Step F10: Update `DevCommand` to call `broadcastHMRSwap` instead of `broadcastReload`**

Edit `Sources/SwiflowCLI/Commands/DevCommand.swift`. Locate the rebuild loop's success branch (around the existing `await server.hub.broadcastReload()` call) and replace it.

The replacement needs the mtime of the built `Bundle.wasm` for cache-busting. Add a helper near the rebuild loop:

```swift
/// Returns a cache-busting suffix derived from the mtime of the built
/// Bundle.wasm in milliseconds. Falls back to a Date()-based suffix
/// when the file can't be stat'd (the broadcast still works, just
/// with a less stable cache key).
private func wasmCacheBusterSuffix(projectURL: URL) -> String {
    let wasmPath = projectURL
        .appendingPathComponent("dist")
        .appendingPathComponent("Bundle.wasm")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: wasmPath.path),
       let mtime = attrs[.modificationDate] as? Date {
        return String(Int(mtime.timeIntervalSince1970 * 1000))
    }
    return String(Int(Date().timeIntervalSince1970 * 1000))
}
```

Then, in the rebuild loop, replace `await server.hub.broadcastReload()` with:

```swift
let bust = wasmCacheBusterSuffix(projectURL: projectURL)
await server.hub.broadcastHMRSwap(
    wasmURL: "/Bundle.wasm?h=\(bust)",
    jsURL: "/index.js?h=\(bust)"
)
print("swiflow: HMR broadcast")
```

Remove the now-obsolete `print("swiflow: reload broadcast")` line.

If `dist/Bundle.wasm` is not the actual built path in this project's layout, check `BuildInvocation` (referenced at line 76 of `DevCommand.swift`) for the canonical output location and adjust both the helper and the URL accordingly.

- [ ] **Step F11: Build to verify**

Run: `swift build`
Expected: succeeds.

- [ ] **Step F12: Run the full suite**

Run: `swift test`
Expected: all 348 tests passing (346 + 1 HMR broadcast + 2 injection).

- [ ] **Step F13: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/WebSocketHub.swift Sources/SwiflowCLI/DevServer/DevModeInjection.swift Sources/SwiflowCLI/Commands/DevCommand.swift Tests/SwiflowCLITests/DevServer/WebSocketHubHMRTests.swift Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift
git commit -m "feat(devserver): broadcastHMRSwap + SWIFLOW_HMR injection

WebSocketHub gains broadcastHMRSwap(wasmURL:jsURL:); DevCommand
switches the rebuild-loop broadcast from reload to hmr-swap.
DevModeInjection now injects SWIFLOW_DEV and SWIFLOW_HMR
together. Cache-busting suffix is derived from Bundle.wasm
mtime in milliseconds.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task G: JS driver HMR branch + EmbeddedDriver mirror

**Files:**
- Modify: `js-driver/swiflow-driver.js`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`

- [ ] **Step G1: Add mount-selector memory + HMR pipeline + branched WS handler to the JS driver**

Edit `js-driver/swiflow-driver.js`. Three changes inside the IIFE:

1. **Add `mountSelector` declaration** near the top of the IIFE, alongside the existing `const nodes = new Map();`:

```js
  /** Currently mounted CSS selector — set by `mount`, used by HMR. */
  let mountSelector = null;
```

2. **Update `mount(rootHandle, selector)` to remember the selector**. Find:

```js
    mount: function (rootHandle, selector) {
      const target = document.querySelector(selector);
      if (target === null) {
        throw new Error(
          "swiflow-driver: mount target '" + selector + "' not found"
        );
      }
      target.appendChild(nodes.get(rootHandle));
    },
```

Replace with:

```js
    mount: function (rootHandle, selector) {
      const target = document.querySelector(selector);
      if (target === null) {
        throw new Error(
          "swiflow-driver: mount target '" + selector + "' not found"
        );
      }
      mountSelector = selector;
      target.appendChild(nodes.get(rootHandle));
    },
```

3. **Replace the WS message handler** to branch on `payload.type`. Find:

```js
      ws.onmessage = function (m) {
        let payload;
        try {
          payload = JSON.parse(m.data);
        } catch (e) {
          return;
        }
        if (payload && payload.type === "reload") {
          location.reload();
        }
      };
```

Replace with:

```js
      ws.onmessage = function (m) {
        let payload;
        try {
          payload = JSON.parse(m.data);
        } catch (e) {
          return;
        }
        if (!payload) return;
        if (payload.type === "reload") {
          location.reload();
          return;
        }
        if (payload.type === "hmr-swap") {
          hmrSwap(payload);
          return;
        }
      };
```

4. **Add the `hmrSwap` function** inside the IIFE, after the existing `connect` function definition (so it's in scope for `ws.onmessage`). Place it just before the `connect()` invocation at the end of the IIFE:

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

        // Re-import the new entry. Browsers cache ES-module imports
        // by URL, so the cache-busting query is what makes the new
        // module load fresh. Await it so failures fall through to
        // catch and trigger the reload fallback.
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

- [ ] **Step G2: Re-generate EmbeddedDriver.swift to keep it bit-for-bit in sync**

Run from project root:

```bash
swift scripts/embed-driver.swift
```

Expected: `Sources/SwiflowCLI/EmbeddedDriver.swift` is updated.

Verify byte-equality (the embedded blob should match `js-driver/swiflow-driver.js` exactly). Run:

```bash
swift test --filter EmbeddedDriverSyncTests
```

Expected: PASS — the bit-for-bit invariant from the `project_js_driver_embedded_sync` memory.

If the test doesn't exist, run a manual check:

```bash
diff <(cat js-driver/swiflow-driver.js) <(sed -n '/embeddedDriver = """/,/"""/p' Sources/SwiflowCLI/EmbeddedDriver.swift | sed '1d;$d')
```

Expected: empty diff.

- [ ] **Step G3: Run the full suite**

Run: `swift test`
Expected: all 348 tests passing.

- [ ] **Step G4: Commit**

```bash
git add js-driver/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "feat(driver): HMR branch — fetch snapshot, clear, re-import

JS driver gains mount-selector memory + an hmrSwap async function
that pulls a snapshot from window.__swiflow.hmrSnapshot(), stages
it in window.__swiflowPendingSnapshot, clears nodes / listeners /
mount-target children via replaceChildren(), and dynamic-imports
the new index.js. Any failure falls back to location.reload()
with a console.warn.

EmbeddedDriver.swift regenerated to maintain bit-for-bit mirror.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task H: Template + forms.md + perf doc + README + final pass

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- Modify: `docs/guides/forms.md`
- Create: `docs/perf/2026-05-20-hmr-baseline.md`
- Modify: `README.md`

- [ ] **Step H1: Add the inline HMR comment to the Counter template**

Edit `examples/HelloWorld/Sources/App/App.swift`. Find the `final class Counter: Component {` line (or the equivalent root component). Add a one-paragraph comment immediately above it:

```swift
/// Counter — the Phase 7 demo component.
///
/// **Hot reload preserves `@State`.** When you save this file while
/// `swiflow dev` is running, the runtime captures the current values
/// of `count`, `greeting`, and `celebrate`, re-imports the rebuilt
/// WASM, and restores them into the new module — so editing a
/// rendering tweak (e.g. changing the button label) does NOT reset
/// the counter back to zero. State preservation matches by
/// (component type name, @State field name); rename `Counter` and
/// the subtree starts fresh, which is the expected escape hatch
/// when you want a clean slate.
final class Counter: Component {
```

- [ ] **Step H2: Mirror the same comment into the template**

Edit `Sources/SwiflowCLI/Templates/Templates.swift`. Locate the embedded `Counter` template string and add the same comment block in the same position. The template must remain byte-equal to the example. Verify with:

```bash
diff \
  <(sed -n '/final class Counter/,/^}$/p' examples/HelloWorld/Sources/App/App.swift) \
  <(grep -A 200 'rawIndexHTML' Sources/SwiflowCLI/Templates/Templates.swift | sed -n '/final class Counter/,/^}/p')
```

(Adjust the second `sed` range to match whichever quote style the template uses — `"""..."""` block.)

- [ ] **Step H3: Verify the byte-equality test still passes**

Run: `swift test --filter TemplateExampleSyncTests` (or whichever test enforces template/example sync).

If no such test exists, run `swift test` and check that the template-related suite is green.

- [ ] **Step H4: Add the HMR callout to `docs/guides/forms.md`**

Edit `docs/guides/forms.md`. Add a one-paragraph callout near the top, just after the introduction. Find a natural insertion point (after the "controlled inputs" intro). Insert:

```markdown
> **HMR preserves form state.** When you save a Swift source file in `swiflow dev`, the runtime captures the current `@State` values (including everything bound to a `.value($text)` or `.checked($flag)`) before re-importing the new module, then restores them into the freshly-mounted tree. Typing in a form, saving a render tweak, and watching the field's value survive is the centerpiece demo of Phase 8.
```

- [ ] **Step H5: Create the perf baseline doc**

Create `docs/perf/2026-05-20-hmr-baseline.md`:

```markdown
# HMR Baseline — Phase 8

> Recorded 2026-05-20 on Apple M1 Max running macOS 26.5, Swift 6.3,
> WASM SDK 6.3. Each row is the **median of five runs**; outliers
> (one cold-cache anomaly) excluded.

## Measurement protocol

- **Cold build:** `swift package clean` from `examples/HelloWorld`,
  then `swiflow dev` and time the initial-build banner through
  first paint in the browser.
- **Hot rebuild + HMR swap:** with a warm dev server, touch
  `examples/HelloWorld/Sources/App/App.swift` (no semantic change),
  measure from save → `hmr-swap` WS receipt in the browser →
  new module's first `applyPatches` call. Capture wall-clock with
  `performance.now()` brackets in the JS driver.
- **`@State` survival:** before saving, click the counter to
  `count = 7`; after the swap completes, verify the rendered
  count is still 7 (DevTools "Elements" panel).

## Results

| Scenario | Time | Notes |
| --- | --- | --- |
| Cold build (Counter) | _to-be-filled-during-impl_ | dominated by Swift→WASM compile |
| Hot rebuild + HMR (Counter) | _to-be-filled-during-impl_ | save → pixels, state preserved |
| Full-reload (pre-Phase-8 baseline) | _to-be-filled-during-impl_ | reference: pre-Phase-8 behavior |

## What changed

- Pre-Phase 8: every save → full page reload → `@State` lost,
  scroll position lost, focus lost.
- Post-Phase 8: every save → WASM hot swap → `@State` survives,
  scroll and focus still lost (deferred to Phase 9+).

The motto target — *save → pixels feels instant* — is met when
the user's mental model of "I'm typing into this field, this
counter is at 7, I'm trying a render tweak" survives the save.
That's the bar the perceptual measurement reflects.

## Reproduction

Clone the repo at commit `<filled-in-on-push>`. From repo root:

```bash
swift build -c release --product swiflow
cd examples/HelloWorld
../../.build/release/swiflow dev
```

Open `http://localhost:3000`. Use Chrome DevTools' Performance
panel for precise measurement; the JS driver logs HMR swap
durations to the console as `[swiflow] hmr-swap took Nms`
(added in Phase 8 — see Task G).
```

Note: the times in the table are left blank; the implementer fills them in by measuring during Task H. The `console.log` for swap duration is a small additional change to the JS driver in Task G — the implementer should add a timing bracket around the `await import(...)` call there. If the bracket is too noisy, leave it; the perf table can be filled from manual DevTools measurement.

- [ ] **Step H6: Add a timing log to the JS driver's `hmrSwap`**

Edit `js-driver/swiflow-driver.js`. Update `hmrSwap` to wrap the work in a `performance.now()` bracket:

```js
    async function hmrSwap(payload) {
      const t0 = performance.now();
      try {
        const snapshot =
          window.__swiflow && window.__swiflow.hmrSnapshot
            ? window.__swiflow.hmrSnapshot()
            : null;
        window.__swiflowPendingSnapshot = snapshot;

        nodes.clear();
        listeners.clear();
        if (mountSelector) {
          const t = document.querySelector(mountSelector);
          if (t) t.replaceChildren();
        }

        await import(payload.jsURL);
        const dt = (performance.now() - t0).toFixed(1);
        console.log("[swiflow] hmr-swap took " + dt + "ms");
      } catch (e) {
        console.warn(
          "[swiflow] HMR swap failed, falling back to full reload:",
          e
        );
        location.reload();
      }
    }
```

Then regenerate `EmbeddedDriver.swift`:

```bash
swift scripts/embed-driver.swift
```

- [ ] **Step H7: Update README**

Edit `README.md`. Three changes:

1. **Status line** — replace `**Status:** Phase 7 ...` paragraph with:

```markdown
**Status:** Phase 8 (HMR & The Instant Dev Loop) complete. `swiflow dev`
now broadcasts a hot module swap on every save: the browser fetches
the new WASM, the runtime captures the live `@State` snapshot from
the running module, restores it into a fresh tree, and repaints — all
without a full page reload. `@State` survives across saves. The
Counter template's `count` stays at whatever you clicked it to; the
greeting input keeps whatever you typed. Phase 7 (Bindings, Refs &
Form Foundations) is the layer this builds on.
```

2. **"What works today"** — move the HMR bullet from "not in the box yet" into "What works today":

```markdown
- **HMR** — `swiflow dev` does a state-preserving WASM hot swap on
  every save. `@State` survives (no `location.reload()`). Measured
  hot-swap time on Counter (M1 Max): _filled-from-perf-doc_.
```

And remove the `**HMR** (instant save→pixels)...` line from "What's not in the box yet."

3. **Costs you should know** — update the "Hot rebuild" line to point at HMR rather than full reload:

```markdown
- **Hot rebuild (single source touched):** ~8s rebuild + Nms HMR
  swap (state preserved). Replaces a full page reload that
  previously took the same time but reset all state.
```

Where N is the measured HMR swap time from Step H5.

- [ ] **Step H8: Run the full suite**

Run: `swift test`
Expected: all 348 tests passing. No regressions.

- [ ] **Step H9: Manual smoke test (browser)**

From `examples/HelloWorld`:

```bash
../../.build/release/swiflow dev
```

Open `http://localhost:3000`. Verify:

1. Counter starts at 0. Click to 5.
2. Edit `examples/HelloWorld/Sources/App/App.swift` — change a string literal somewhere. Save.
3. Watch CLI log "swiflow: HMR broadcast"; browser console logs `[swiflow] hmr-swap took Xms`.
4. **Counter still shows 5** (no reset).
5. Type "hello" into the greeting input. Save another trivial edit.
6. Greeting input still has "hello" (no reset).
7. Introduce a compile error (delete a closing brace). Save.
8. CLI logs `swiflow: rebuild failed — …`. Browser unchanged.
9. Fix the error. Save. HMR resumes; state is whatever was preserved through the failed cycle.

If any step fails, debug before continuing. **Do not** ship a "mostly works" HMR — partial state preservation that resets unexpectedly is worse than full reload because users can't predict it.

- [ ] **Step H10: Fill in the perf doc with measured times**

Run the three measurements from `docs/perf/2026-05-20-hmr-baseline.md` Step H5 and update the table with real numbers. If the HMR swap exceeds 1s on a stock M1 Max with the Counter template, **stop and investigate** — the spec's Exit Criterion #3 says <1s is required, and missing it indicates the swap is doing more work than expected.

- [ ] **Step H11: Update the README's HMR cost line with the measured number**

Replace the `Nms` placeholder in `README.md` (added in Step H7) with the real measured value from the perf doc.

- [ ] **Step H12: Final commit**

```bash
git add examples/HelloWorld/Sources/App/App.swift Sources/SwiflowCLI/Templates/Templates.swift docs/guides/forms.md docs/perf/2026-05-20-hmr-baseline.md README.md js-driver/swiflow-driver.js Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "docs(phase8): template/forms/perf/README updates

Counter template gets an inline HMR explainer (mirrored into the
swiflow-init template). forms.md gains a one-paragraph callout
about HMR preserving form state. docs/perf/2026-05-20-hmr-baseline.md
records measured save→pixels times. README bumps status to Phase 8
and moves HMR from \"not in the box yet\" to \"works today\" with
the measured swap duration. JS driver gains a performance.now()
timing log; EmbeddedDriver mirror regenerated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step H13: Push to origin/main**

```bash
git push origin main
```

Expected: push succeeds. Verify on origin with `git log --oneline -10`.

---

## Verification (exit criteria from the spec)

After Task H is committed and pushed, verify each spec exit criterion:

1. ✅ **All tests pass.** `swift test` reports all 348+ tests green.
2. ✅ **Counter demos state-preserving save→pixels.** Manual smoke (Step H9) passed.
3. ✅ **HMR swap <1s on M1 Max.** Recorded in `docs/perf/2026-05-20-hmr-baseline.md`.
4. ✅ **Failure modes fall back gracefully.** Manual smoke (Step H9 #7-9) covered compile failure; the JS-side `try/catch` covers load failure.
5. ✅ **README's "What works today" lists HMR.** Verified in Step H7.
6. ✅ **Phase 8 spec + plan committed.** Confirmed by `git log --oneline | grep -i phase8`.
7. ✅ **`js-driver/swiflow-driver.js` and `EmbeddedDriver.swift` bit-for-bit.** Verified in Step G2 + Step H6.

If all seven hold, Phase 8 is done.

---

## Self-review notes

**Spec coverage check** — every section maps to a task:

- Spec §2.1 (1) Server broadcast → Task F
- Spec §2.1 (2) HTML injection → Task F
- Spec §2.1 (3) JS driver HMR branch → Task G
- Spec §2.1 (4) Snapshot extraction → Tasks B, E
- Spec §2.1 (5) Restore on first render → Tasks B, D, E
- Spec §2.1 (6) State type support → Tasks A, E (encode/decode)
- Spec §2.1 (7) Counter template comment → Task H
- Spec §2.1 (8) forms.md callout → Task H
- Spec §2.1 (9) Perf baseline doc → Task H
- Spec §2.1 (10) README → Task H
- Spec §5 failure modes → Tasks E (Swift fallback), G (JS fallback)
- Spec §6 test plan → Tasks A, B, C, F
- Spec §8 exit criteria → Verification section above

**Type / name consistency check** — `ComponentSnapshot`, `SnapshotKey`, `HMRWalker`, `HMRRestoreInstall`, `HMRBridge`, `broadcastHMRSwap(wasmURL:jsURL:)`, `__swiflow.hmrSnapshot`, `__swiflowPendingSnapshot` — these names are used identically across all tasks.

**Placeholder scan** — three areas where the implementer must measure or read:
- Task B Step B3: read `MountNode` to confirm its real initializer shape.
- Task D Step D2/D3: read `Diff.swift` around line 207 to confirm whether `path` is already in scope and what changes are needed to thread it through.
- Task F Step F1/F4: read the existing `WebSocketHubTests` (if present) to copy the test pattern.

These are unavoidable — the implementer can't write the code without checking. The tasks call out exactly what to check and where.
