# Swiflow Phase 10 — Effects, Context & @Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `@Environment` dependency injection and a deps-aware `onChange(of:)` hook to Swiflow components.

**Architecture:** `@Environment` reads from a `nonisolated(unsafe) static var AmbientEnvironment.current` set by the diff immediately before calling any `instance.body`. A new `VNode.environmentOverride` case carries env overrides through the tree; the diff intercepts it, merges the override values, and passes the merged env to child mounts. `onChange(of:)` is an extension method on `Component` backed by a module-internal side table (`OnChangeStorage`) keyed by component identity, cleaned up in `destroy()`.

**Tech Stack:** Swift 6, Swift Testing framework (`import Testing`), no JavaScriptKit (all new code is macOS-testable).

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `Sources/Swiflow/Reactivity/Environment.swift` | `EnvironmentKey`, `EnvironmentValues`, `AmbientEnvironment`, `@Environment`, `ColorScheme`, built-in keys |
| Create | `Sources/Swiflow/DSL/EnvironmentDSL.swift` | `withEnvironment(_:_:content:)` free function |
| Create | `Sources/Swiflow/Reactivity/OnChangeStorage.swift` | `OnChangeStorage` side table + `Component.onChange(of:key:perform:)` |
| Create | `docs/guides/environment.md` | User guide |
| Create | `Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift` | EnvironmentValues unit tests |
| Create | `Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift` | Diff threading integration tests |
| Create | `Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift` | onChange(of:) unit tests |
| Modify | `Sources/Swiflow/VNode.swift` | Add `.environmentOverride(EnvironmentValues, VNode)` case |
| Modify | `Sources/Swiflow/Diff/Diff.swift` | Thread `environment`, add `.environmentOverride` arms, set `AmbientEnvironment.current`, `OnChangeStorage.remove` in `destroy()` |
| Modify | `Sources/Swiflow/Diff/IndexedChildrenDiff.swift` | Thread `environment` through all `mount()`/`update()` calls |
| Modify | `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` | Thread `environment` through all `mount()`/`update()` calls |
| Modify | `Sources/SwiflowWeb/Renderer.swift` | Pass `environment: .init()` to `diff()` |
| Modify | `Sources/Swiflow/DevAPIFormatter.swift` | Add `.environmentOverride` pass-through in `walkTree()` |

---

## Task 1: `EnvironmentValues`, `EnvironmentKey`, `@Environment`, `ColorScheme`, built-in keys

**Files:**
- Create: `Sources/Swiflow/Reactivity/Environment.swift`
- Create: `Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift`:

```swift
// Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift
import Testing
@testable import Swiflow

@Suite("EnvironmentValues")
struct EnvironmentValuesTests {

    @Test("default locale is en")
    func defaultLocale() {
        #expect(EnvironmentValues().locale == "en")
    }

    @Test("default colorScheme is light")
    func defaultColorScheme() {
        #expect(EnvironmentValues().colorScheme == .light)
    }

    @Test("custom key round-trips through subscript")
    func customKeyRoundTrip() {
        enum MyKey: EnvironmentKey { static let defaultValue = 42 }
        var env = EnvironmentValues()
        env[MyKey.self] = 99
        #expect(env[MyKey.self] == 99)
    }

    @Test("unset custom key returns defaultValue")
    func unsetKeyReturnsDefault() {
        enum MyKey: EnvironmentKey { static let defaultValue = "hello" }
        #expect(EnvironmentValues()[MyKey.self] == "hello")
    }

    @Test("merging overlays overridden keys and preserves others")
    func mergingOverlaysAndPreserves() {
        var base = EnvironmentValues()
        base.locale = "en"
        base.colorScheme = .light
        var overrides = EnvironmentValues()
        overrides.locale = "fr"
        let merged = base.merging(overrides)
        #expect(merged.locale == "fr")
        #expect(merged.colorScheme == .light)
    }

    @Test("later merging wins on conflicting keys")
    func mergingLeafWins() {
        var first = EnvironmentValues()
        first.locale = "en"
        var second = EnvironmentValues()
        second.locale = "de"
        var third = EnvironmentValues()
        third.locale = "fr"
        let merged = first.merging(second).merging(third)
        #expect(merged.locale == "fr")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```
swift test --filter "EnvironmentValuesTests"
```

Expected: compile error — `EnvironmentValues`, `EnvironmentKey`, `ColorScheme` not found.

- [ ] **Step 3: Implement `Sources/Swiflow/Reactivity/Environment.swift`**

```swift
// Sources/Swiflow/Reactivity/Environment.swift

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    var storage: [ObjectIdentifier: Any] = [:]

    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(K.self)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(K.self)] = newValue }
    }

    func merging(_ overrides: EnvironmentValues) -> EnvironmentValues {
        var result = self
        for (id, val) in overrides.storage { result.storage[id] = val }
        return result
    }
}

extension EnvironmentValues: Equatable {
    public static func == (lhs: EnvironmentValues, rhs: EnvironmentValues) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        return lhs.storage.keys.allSatisfy { rhs.storage[$0] != nil }
    }
}

public enum ColorScheme: Equatable { case light, dark }

private enum LocaleKey: EnvironmentKey { static let defaultValue = "en" }
private enum ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }

extension EnvironmentValues {
    public var locale: String {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

enum AmbientEnvironment {
    nonisolated(unsafe) static var current: EnvironmentValues = .init()
}

@propertyWrapper
public struct Environment<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    public var wrappedValue: Value { AmbientEnvironment.current[keyPath: keyPath] }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
swift test --filter "EnvironmentValuesTests"
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/Environment.swift Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift
git commit -m "feat(env): EnvironmentValues, EnvironmentKey, @Environment, ColorScheme"
```

---

## Task 2: `OnChangeStorage` + `Component.onChange(of:)` extension

**Files:**
- Create: `Sources/Swiflow/Reactivity/OnChangeStorage.swift`
- Create: `Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift`:

```swift
// Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("onChange(of:)")
struct OnChangeStorageTests {

    final class Holder: Component {
        @State var count = 0
        @State var label = ""
        var body: VNode { .text("") }
    }

    @Test("first call does not fire perform")
    func firstCallDoesNotFire() {
        let c = Holder()
        var fired = false
        c.onChange(of: 1, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("same value does not fire perform")
    func sameValueDoesNotFire() {
        let c = Holder()
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }

    @Test("changed value fires with new value")
    func changedValueFires() {
        let c = Holder()
        c.onChange(of: 5, key: "k") { _ in }  // seed
        var received: Int? = nil
        c.onChange(of: 10, key: "k") { received = $0 }
        #expect(received == 10)
    }

    @Test("multiple keys tracked independently")
    func multipleKeysTrackedIndependently() {
        let c = Holder()
        c.onChange(of: 1, key: "count") { _ in }   // seed count
        c.onChange(of: "x", key: "label") { _ in } // seed label
        var countFired = false
        var labelFired = false
        c.onChange(of: 2, key: "count") { _ in countFired = true }
        c.onChange(of: "x", key: "label") { _ in labelFired = true }
        #expect(countFired == true)
        #expect(labelFired == false)
    }

    @Test("remove clears all entries for component")
    func removeClearsAllEntries() {
        let c = Holder()
        c.onChange(of: 5, key: "k") { _ in }  // seed
        OnChangeStorage.remove(for: ObjectIdentifier(c))
        // After remove, next call is treated as first → no fire even if value is same
        var fired = false
        c.onChange(of: 5, key: "k") { _ in fired = true }
        #expect(!fired)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```
swift test --filter "OnChangeStorageTests"
```

Expected: compile error — `OnChangeStorage`, `onChange(of:key:)` not found.

- [ ] **Step 3: Implement `Sources/Swiflow/Reactivity/OnChangeStorage.swift`**

```swift
// Sources/Swiflow/Reactivity/OnChangeStorage.swift

@MainActor
enum OnChangeStorage {
    private static var table: [ObjectIdentifier: [String: Any]] = [:]

    static func get(for id: ObjectIdentifier, key: String) -> Any? {
        table[id]?[key]
    }

    static func set(for id: ObjectIdentifier, key: String, value: Any) {
        if table[id] == nil { table[id] = [:] }
        table[id]![key] = value
    }

    static func remove(for id: ObjectIdentifier) {
        table.removeValue(forKey: id)
    }
}

public extension Component {
    /// Fires `perform(newValue)` only when `value` has changed since the last
    /// call with the same `key`. Call this from `onChange()`. Supply an
    /// explicit `key:` string when making multiple `onChange(of:)` calls in
    /// the same `onChange()` override — the default `#function` is identical
    /// for every call site in the same method.
    func onChange<T: Equatable>(
        of value: T,
        key: String = #function,
        perform: (T) -> Void
    ) {
        let id = ObjectIdentifier(self)
        let prev = OnChangeStorage.get(for: id, key: key) as? T
        OnChangeStorage.set(for: id, key: key, value: value)
        if let prev, prev != value { perform(value) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
swift test --filter "OnChangeStorageTests"
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/OnChangeStorage.swift Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift
git commit -m "feat(env): OnChangeStorage + Component.onChange(of:key:perform:)"
```

---

## Task 3: `VNode.environmentOverride` case + `withEnvironment` DSL

**Files:**
- Modify: `Sources/Swiflow/VNode.swift`
- Create: `Sources/Swiflow/DSL/EnvironmentDSL.swift`

- [ ] **Step 1: Write a failing test**

Add `Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift`:

```swift
// Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift
import Testing
@testable import Swiflow

@Suite("withEnvironment DSL")
struct EnvironmentDSLTests {

    @Test("withEnvironment produces an environmentOverride VNode")
    func producesEnvironmentOverride() {
        let vnode = withEnvironment(\.locale, "fr") { VNode.text("hello") }
        guard case let .environmentOverride(env, child) = vnode else {
            Issue.record("Expected .environmentOverride, got \(vnode)")
            return
        }
        #expect(env.locale == "fr")
        if case .text(let t) = child {
            #expect(t == "hello")
        } else {
            Issue.record("Expected .text child, got \(child)")
        }
    }

    @Test("nested withEnvironment merges overrides")
    func nestedWithEnvironment() {
        let inner = withEnvironment(\.colorScheme, .dark) { VNode.text("x") }
        let outer = withEnvironment(\.locale, "ja") { inner }
        guard case let .environmentOverride(outerEnv, outerChild) = outer else {
            Issue.record("Expected outer .environmentOverride")
            return
        }
        #expect(outerEnv.locale == "ja")
        guard case let .environmentOverride(innerEnv, _) = outerChild else {
            Issue.record("Expected inner .environmentOverride")
            return
        }
        #expect(innerEnv.colorScheme == .dark)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```
swift test --filter "EnvironmentDSLTests"
```

Expected: compile error — `.environmentOverride` case and `withEnvironment` not found.

- [ ] **Step 3: Add `.environmentOverride` case to `VNode`**

In `Sources/Swiflow/VNode.swift`, replace lines 24–33 (the enum declaration):

```swift
public indirect enum VNode: Equatable {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
    /// A component anchor. Carries identity (`typeID` + `key`) and a factory
    /// closure consumed at first mount. Subsequent renders with an equal
    /// description at the same child position reuse the existing instance
    /// (Phase 3+ — see `Component` and `ComponentDescription`).
    case component(ComponentDescription)
    /// An environment-override anchor. Carries a set of `EnvironmentValues`
    /// overrides and a single child VNode. Structural-only: the diff allocates
    /// a handle for it but never sends a `create*` patch. The diff merges the
    /// overrides into the current `EnvironmentValues` before recursing into
    /// the child. Produced by `withEnvironment(_:_:content:)`.
    case environmentOverride(EnvironmentValues, VNode)
}
```

- [ ] **Step 4: Create `Sources/Swiflow/DSL/EnvironmentDSL.swift`**

```swift
// Sources/Swiflow/DSL/EnvironmentDSL.swift

/// Overrides an environment value for a subtree.
///
/// ```swift
/// var body: VNode {
///     withEnvironment(\.locale, "fr") {
///         embed { Sidebar() }
///     }
/// }
/// ```
///
/// For multiple overrides, nest calls:
/// ```swift
/// withEnvironment(\.locale, "fr") {
///     withEnvironment(\.colorScheme, .dark) {
///         embed { Sidebar() }
///     }
/// }
/// ```
public func withEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    _ value: Value,
    content: () -> VNode
) -> VNode {
    var overrides = EnvironmentValues()
    overrides[keyPath: keyPath] = value
    return .environmentOverride(overrides, content())
}
```

- [ ] **Step 5: Run tests to verify they pass**

```
swift test --filter "EnvironmentDSLTests"
```

Expected: 2 tests pass. Also run the full suite to catch any regressions from the VNode change:

```
swift test
```

Expected: all existing tests pass plus the new 2.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/VNode.swift Sources/Swiflow/DSL/EnvironmentDSL.swift Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift
git commit -m "feat(env): VNode.environmentOverride case + withEnvironment DSL"
```

---

## Task 4: Thread environment through diff + implement all arms

This is the core task. It touches six files and wires everything together.

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Modify: `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`
- Modify: `Sources/SwiflowWeb/Renderer.swift`
- Modify: `Sources/Swiflow/DevAPIFormatter.swift`
- Create: `Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift`

- [ ] **Step 1: Write the failing threading tests**

Create `Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift`:

```swift
// Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("Environment threading through diff")
struct EnvironmentThreadingTests {

    final class LocaleReader: Component {
        @Environment(\.locale) var locale
        var capturedLocale: String = ""
        var body: VNode {
            capturedLocale = locale
            return .text(locale)
        }
    }

    @Test("component reads default locale when no override")
    func defaultLocale() {
        let reader = LocaleReader()
        let desc = ComponentDescription(LocaleReader.self, key: nil) { reader }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(.component(desc), into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedLocale == "en")
    }

    @Test("environmentOverride node sets locale for wrapped component")
    func overrideReachesComponent() {
        let reader = LocaleReader()
        let desc = ComponentDescription(LocaleReader.self, key: nil) { reader }
        var overrides = EnvironmentValues()
        overrides.locale = "fr"
        let vnode = VNode.environmentOverride(overrides, .component(desc))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedLocale == "fr")
    }

    @Test("sibling outside override reads default locale")
    func siblingOutsideOverrideReadsDefault() {
        let readerA = LocaleReader()
        let readerB = LocaleReader()
        let descA = ComponentDescription(LocaleReader.self, key: "a") { readerA }
        let descB = ComponentDescription(LocaleReader.self, key: "b") { readerB }
        var overrides = EnvironmentValues()
        overrides.locale = "ja"
        let vnode = VNode.element(ElementData(
            tag: "div",
            children: [
                .environmentOverride(overrides, .component(descA)),
                .component(descB)
            ]
        ))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(readerA.capturedLocale == "ja")
        #expect(readerB.capturedLocale == "en")
    }

    @Test("nested overrides merge correctly")
    func nestedOverridesMerge() {
        final class SchemeReader: Component {
            @Environment(\.colorScheme) var colorScheme
            var capturedScheme: ColorScheme = .light
            var body: VNode {
                capturedScheme = colorScheme
                return .text("")
            }
        }
        let reader = SchemeReader()
        let desc = ComponentDescription(SchemeReader.self, key: nil) { reader }
        var outer = EnvironmentValues()
        outer.locale = "de"
        var inner = EnvironmentValues()
        inner.colorScheme = .dark
        let vnode = VNode.environmentOverride(outer, .environmentOverride(inner, .component(desc)))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        _ = mount(vnode, into: &patches, handles: handles, handlers: handlers)
        #expect(reader.capturedScheme == .dark)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```
swift test --filter "EnvironmentThreadingTests"
```

Expected: 4 tests fail — `@Environment` reads default values even with overrides (threading not wired yet).

- [ ] **Step 3: Update `Diff.swift` — add `environment` to signatures and implement new arms**

**3a. Update `diff()` signature** (line ~30):

```swift
@MainActor
package func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    environment: EnvironmentValues = .init()
) -> DiffResult {
    var patches: [Patch] = []
    let root: MountNode
    if let mounted = mounted {
        root = update(
            mounted: mounted,
            next: next,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            environment: environment
        )
    } else {
        root = mount(
            next,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: "",
            environment: environment
        )
    }
    return DiffResult(patches: patches, newMountTree: root)
}
```

**3b. Update `mount()` signature** — add `environment: EnvironmentValues = .init()` to the parameter list after `path: String = ""`. The full updated signature:

```swift
@MainActor
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    depth: Int = 0,
    path: String = "",
    environment: EnvironmentValues = .init()
) -> MountNode {
```

**3c. Add `.environmentOverride` arm in `mount()`** — insert this case BEFORE the `.element` case:

```swift
case .environmentOverride(let overrides, let child):
    let h = handles.next()
    let merged = environment.merging(overrides)
    let childMount = mount(
        child,
        into: &patches,
        handles: handles,
        handlers: handlers,
        scheduler: scheduler,
        depth: depth,
        path: path,
        environment: merged
    )
    return MountNode(handle: h, vnode: vnode, componentBody: childMount)
```

**3d. In the `.component` arm of `mount()`** — add `AmbientEnvironment.current = environment` immediately before the `instance.instance.body` call. The arm currently reads:

```swift
wireStateAndRestore(on: instance, scheduler: scheduler, stateMap: stateMap, path: path)
let anchorHandle = handles.next()
handlers.openScope(name: path)
let bodyVNode = instance.instance.body
```

Change to:

```swift
wireStateAndRestore(on: instance, scheduler: scheduler, stateMap: stateMap, path: path)
let anchorHandle = handles.next()
handlers.openScope(name: path)
AmbientEnvironment.current = environment
let bodyVNode = instance.instance.body
```

**3e. Pass `environment` to recursive `mount()` calls inside the `.element` arm** — the child loop currently calls:

```swift
let childMount = mount(
    childVNode,
    into: &patches,
    handles: handles,
    handlers: handlers,
    scheduler: scheduler,
    depth: depth,
    path: childPath
)
```

Add `environment: environment` to this call.

**3f. Pass `environment` to the body mount inside `.component` arm**:

```swift
let bodyMount = mount(
    bodyVNode,
    into: &patches,
    handles: handles,
    handlers: handlers,
    scheduler: scheduler,
    depth: depth + 1,
    path: path,
    environment: environment   // ADD THIS
)
```

**3g. Update `destroy()` — add `OnChangeStorage.remove` and `.environmentOverride` guard**

In the `if let any = node.component` block, add one line after `handlers.closeScope()`:

```swift
if let any = node.component {
    any.instance.onDisappear()
    handlers.closeScope()
    OnChangeStorage.remove(for: ObjectIdentifier(any.instance))   // NEW
    #if DEBUG
    MountedInstances.unregister(any.instance)
    #endif
}
```

At the bottom of `destroy()`, where `destroyNode` is emitted, replace:

```swift
if node.component == nil {
    patches.append(.destroyNode(handle: node.handle))
}
```

with:

```swift
if node.component == nil {
    if case .environmentOverride = node.vnode {
        // Structural-only handle — no destroyNode patch.
    } else {
        patches.append(.destroyNode(handle: node.handle))
    }
}
```

**3h. Update `update()` signature** (line ~250):

```swift
@MainActor
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    path: String = "",
    environment: EnvironmentValues = .init()
) -> MountNode {
```

**3i. Add `.environmentOverride` arm in `update()`** — insert before the `default:` arm:

```swift
case (.environmentOverride(_, _), .environmentOverride(let nextOverrides, let nextChild)):
    let merged = environment.merging(nextOverrides)
    let updatedBody = update(
        mounted: mounted.componentBody!,
        next: nextChild,
        into: &patches,
        handles: handles,
        handlers: handlers,
        scheduler: scheduler,
        path: path,
        environment: merged
    )
    mounted.componentBody = updatedBody
    mounted.vnode = next
    return mounted
```

**3j. In the `.component` reuse arm of `update()`** — add `AmbientEnvironment.current = environment` before the body re-render call and pass `environment` to the recursive `update()`:

```swift
guard let instance = mounted.component, let oldBody = mounted.componentBody else {
    destroy(mounted, into: &patches, handlers: handlers)
    return mount(next, into: &patches, handles: handles, handlers: handlers,
                 scheduler: scheduler, path: path, environment: environment)
}
AmbientEnvironment.current = environment    // NEW: set before body re-call
let newBodyVNode = instance.instance.body
let newBodyMount = update(
    mounted: oldBody,
    next: newBodyVNode,
    into: &patches,
    handles: handles,
    handlers: handlers,
    scheduler: scheduler,
    path: path,
    environment: environment               // NEW
)
```

**3k. In the `default:` arm of `update()`** — pass `environment` to `mount()`:

```swift
default:
    destroy(mounted, into: &patches, handlers: handlers)
    return mount(next, into: &patches, handles: handles, handlers: handlers,
                 scheduler: scheduler, path: path, environment: environment)
```

**3l. Update `diffChildren()` signature** — add `environment: EnvironmentValues = .init()` after `parentPath`:

```swift
@MainActor
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch],
    scheduler: Scheduler? = nil,
    parentPath: String = "",
    environment: EnvironmentValues = .init()
) {
```

Pass `environment: environment` to both `diffChildrenKeyed(...)` and `diffChildrenIndexed(...)` calls inside `diffChildren()`.

**3m. In the `.element` arm of `update()`** — pass `environment` to `diffChildren()`:

```swift
diffChildren(
    mounted: mounted,
    newChildren: newData.children,
    handles: handles,
    handlers: handlers,
    into: &patches,
    scheduler: scheduler,
    parentPath: path,
    environment: environment        // NEW
)
```

- [ ] **Step 4: Update `IndexedChildrenDiff.swift`**

**4a. Update `diffChildrenIndexed()` signature** — add `environment: EnvironmentValues = .init()` after `parentPath`.

**4b. Pass `environment` to every `update()` call** (the common-prefix loop, line ~27):

```swift
let newChild = update(
    mounted: oldChild,
    next: newChildren[i],
    into: &patches,
    handles: handles,
    handlers: handlers,
    scheduler: scheduler,
    path: childPath,
    environment: environment   // NEW
)
```

**4c. Pass `environment` to `mount()` call** (surplus-new loop, line ~70):

```swift
let childMount = mount(
    newChildren[i],
    into: &patches,
    handles: handles,
    handlers: handlers,
    scheduler: scheduler,
    path: childPath,
    environment: environment   // NEW
)
```

- [ ] **Step 5: Update `KeyedChildrenDiff.swift`**

**5a. Update `diffChildrenKeyed()` signature** — add `environment: EnvironmentValues = .init()` after `parentPath`.

**5b. Pass `environment` to every `update()` call in the file** — there are three:
  - Stable prefix loop (line ~64)
  - Stable suffix loop (line ~114)
  - Map-based middle reuse (line ~223)

Each call gets `environment: environment` appended.

**5c. Pass `environment` to every `mount()` call in the file** — there are two:
  - Pure-inserts loop (line ~166)
  - Map-based middle fresh mount (line ~260)

Each call gets `environment: environment` appended.

- [ ] **Step 6: Update `Renderer.swift`**

In `renderOnce()`, find the `diff(...)` call and add `environment: .init()`:

```swift
let result = diff(
    mounted: mountTree,
    next: nextVNode,
    handles: handles,
    handlers: handlers,
    scheduler: _schedulerBox.value,
    environment: .init()
)
```

- [ ] **Step 7: Update `DevAPIFormatter.swift` — add `.environmentOverride` pass-through**

In `walkTree(_:path:depth:into:)`, the current logic is:

```swift
if let anyC = node.component {
    // emit line ...
} else {
    for (i, child) in node.children.enumerated() {
        ...
    }
}
```

Change the `else` branch to handle `.environmentOverride` before the children loop:

```swift
if let anyC = node.component {
    let typeName = String(reflecting: type(of: anyC.instance))
    let shortName = typeName.split(separator: ".").last.map(String.init) ?? typeName
    let bodyMark = (node.componentBody?.component != nil) ? " [body→]" : ""
    lines.append(String(repeating: "  ", count: depth) + shortName + " \"\(path)\"" + bodyMark)
    if let body = node.componentBody {
        walkTree(body, path: path, depth: depth + 1, into: &lines)
    }
} else if case .environmentOverride = node.vnode, let body = node.componentBody {
    walkTree(body, path: path, depth: depth, into: &lines)
} else {
    for (i, child) in node.children.enumerated() {
        let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
        walkTree(child, path: childPath, depth: depth, into: &lines)
    }
}
```

- [ ] **Step 8: Run tests**

```
swift test
```

Expected: all previous tests pass plus the 4 new `EnvironmentThreadingTests` tests — 375 + new count total.

- [ ] **Step 9: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift \
        Sources/Swiflow/Diff/IndexedChildrenDiff.swift \
        Sources/Swiflow/Diff/KeyedChildrenDiff.swift \
        Sources/SwiflowWeb/Renderer.swift \
        Sources/Swiflow/DevAPIFormatter.swift \
        Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift
git commit -m "feat(env): thread EnvironmentValues through diff + environmentOverride arms + AmbientEnvironment wiring"
```

---

## Task 5: `docs/guides/environment.md`

**Files:**
- Create: `docs/guides/environment.md`

- [ ] **Step 1: Create the guide**

```markdown
# Swiflow Devtools — Environment & @Environment

Available in all builds (not dev-only).

---

## Declaring an environment value

```swift
@Environment(\.locale) var locale
```

`@Environment` reads from the in-tree environment during `body`. Access it like any stored property:

```swift
final class LocaleLabel: Component {
    @Environment(\.locale) var locale
    var body: VNode { p("Locale: \(locale)") }
}
```

**Important:** `@Environment` is only valid during `body`. If you need the value in `onAppear` or `onChange`, capture it into a stored property:

```swift
final class LocaleLabel: Component {
    @Environment(\.locale) var locale
    private var currentLocale = ""

    var body: VNode {
        currentLocale = locale   // capture
        return p(currentLocale)
    }

    func onAppear() {
        print("Locale at mount: \(currentLocale)")
    }
}
```

---

## Overriding environment for a subtree

```swift
var body: VNode {
    div {
        withEnvironment(\.locale, "fr") {
            embed { Sidebar() }
        }
    }
}
```

For multiple overrides, nest calls:

```swift
withEnvironment(\.locale, "fr") {
    withEnvironment(\.colorScheme, .dark) {
        embed { Sidebar() }
    }
}
```

---

## Built-in keys

| Key | Type | Default |
|-----|------|---------|
| `\.locale` | `String` | `"en"` |
| `\.colorScheme` | `ColorScheme` | `.light` |

`ColorScheme` is `enum ColorScheme { case light, dark }`.

---

## Adding a custom key

```swift
// 1. Declare a key type
private enum ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

// 2. Add a computed property to EnvironmentValues
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// 3. Read in a component
final class ThemedCard: Component {
    @Environment(\.theme) var theme
    var body: VNode { div(.attr("class", theme.cardClass)) }
}

// 4. Override for a subtree
withEnvironment(\.theme, Theme.dark) {
    embed { ThemedCard() }
}
```

---

## `onChange(of:)` — deps-aware lifecycle hook

Call from your `onChange()` override to react only when a specific value changes:

```swift
final class Counter: Component {
    @State var count = 0

    var body: VNode {
        button(.on("click") { self.count += 1 }) { text("\(count)") }
    }

    override func onChange() {
        onChange(of: count, key: "count") { newCount in
            print("Count changed to \(newCount)")
        }
    }
}
```

**Multiple watched values** require explicit `key:` strings:

```swift
override func onChange() {
    onChange(of: count, key: "count") { ... }
    onChange(of: label, key: "label") { ... }
}
```

The `key:` defaults to `#function` which is unique per-method but identical across multiple calls within the same method — always supply explicit keys when watching more than one value.

The side table is cleared automatically when the component unmounts.
```

- [ ] **Step 2: Run the full test suite one final time**

```
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add docs/guides/environment.md
git commit -m "docs(env): environment and onChange(of:) user guide"
```
