# Swiflow Phase 10 — Effects, Context & @Environment Design

**Date:** 2026-05-21
**Status:** Approved

---

## Goal

Give components a first-class dependency-injection mechanism (`@Environment`) and a deps-aware lifecycle hook (`onChange(of:)`). Components stop needing global singletons or constructor prop-drilling for cross-tree concerns like locale and color scheme.

`task { }` (async lifecycle blocks) is explicitly deferred — Swift Concurrency in the WASM target is unverified. It will be revisited as a standalone proof-of-concept before Phase 13.

---

## Scope

- `@Environment(\.keyPath)` property wrapper — reads the in-tree environment during `body`
- `EnvironmentValues` struct + `EnvironmentKey` protocol — extensible value store
- Built-in keys: `locale: String`, `colorScheme: ColorScheme`
- `withEnvironment(\.key, value) { child }` DSL function — overrides values for a subtree
- `onChange(of: value, key:perform:)` — extension helper on `Component`, fires only when value changes
- `docs/guides/environment.md`

---

## Architecture

### Key decision: `@Environment` reads from an ambient global

`@Environment` stores a `KeyPath<EnvironmentValues, Value>`. Its `wrappedValue` reads from `AmbientEnvironment.current` — a `nonisolated(unsafe) static var` set by the diff immediately before calling any `instance.body`. Everything on `@MainActor`, fully synchronous, no concurrency risk.

Consequence: `@Environment` is only valid during `body` evaluation. Components that need env values in `onAppear` or `onChange` capture them into stored properties during `body`.

### Key decision: `withEnvironment` produces a new VNode case

Using an internal component type for `withEnvironment` runs into a stale-instance problem: the diff reuses component instances across renders, so stored override values would go stale. A new VNode case `.environmentOverride(EnvironmentValues, VNode)` sidesteps this — the diff handles it by merging and threading, with no instance to stale.

The new case is structural-only (like component anchors): the diff allocates a handle but never sends a `create*` patch for it, and `destroy()` skips emitting `destroyNode` for it.

### Key decision: `onChange(of:)` uses a side table

`onChange<T: Equatable>(of value: T, key: String, perform: (T) -> Void)` is an extension method on `Component`. It reads/writes a `[ObjectIdentifier: [String: Any]]` side table (`OnChangeStorage`) keyed by component-instance identity and a caller-supplied string key (defaulting to `#function`). The diff's `destroy()` clears the entry on unmount. No new protocol requirements, no Mirror walk.

---

## File Layout

### New files

| File | Purpose |
|------|---------|
| `Sources/Swiflow/Reactivity/Environment.swift` | `EnvironmentKey`, `EnvironmentValues`, `AmbientEnvironment`, `@Environment`, `ColorScheme`, built-in key extensions |
| `Sources/Swiflow/DSL/EnvironmentDSL.swift` | `withEnvironment(_:_:content:)` free function |
| `Sources/Swiflow/Reactivity/OnChangeStorage.swift` | `OnChangeStorage` side table + `Component.onChange(of:key:perform:)` extension |
| `docs/guides/environment.md` | User guide |
| `Tests/SwiflowTests/Environment/EnvironmentValuesTests.swift` | Value store unit tests |
| `Tests/SwiflowTests/Environment/EnvironmentThreadingTests.swift` | Diff threading tests |
| `Tests/SwiflowTests/OnChange/OnChangeStorageTests.swift` | Side table tests |

### Modified files

| File | Change |
|------|--------|
| `Sources/Swiflow/VNode.swift` | Add `.environmentOverride(EnvironmentValues, VNode)` case |
| `Sources/Swiflow/Diff/Diff.swift` | Thread `environment: EnvironmentValues` through `mount()`/`update()`; add `.environmentOverride` arms; set `AmbientEnvironment.current` before body calls; call `OnChangeStorage.remove(for:)` in `destroy()` |
| `Sources/SwiflowWeb/Renderer.swift` | Pass `environment: .init()` to `diff()` |
| `Sources/Swiflow/DevAPIFormatter.swift` | Add `.environmentOverride` pass-through in `walkTree()` |

---

## API Surface

### `EnvironmentKey` + `EnvironmentValues`

```swift
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
```

### Built-in keys

```swift
public enum ColorScheme { case light, dark }

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
```

### `AmbientEnvironment` + `@Environment`

```swift
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

### `withEnvironment` DSL

```swift
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

Multiple overrides require nesting:
```swift
withEnvironment(\.locale, "fr") {
    withEnvironment(\.colorScheme, .dark) {
        embed { Sidebar() }
    }
}
```

### Custom environment keys

Users extend `EnvironmentValues` following the same pattern:
```swift
enum ThemeKey: EnvironmentKey { static let defaultValue = Theme.default }
extension EnvironmentValues {
    var theme: Theme { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
}
```

### `onChange(of:)` extension

```swift
public extension Component {
    /// Fires `perform` when `value` changes between renders. Call from `onChange()`.
    /// `key` disambiguates multiple calls in the same `onChange()` body — defaults
    /// to `#function` which is unique per override method but identical across
    /// calls if you have two `onChange(of:)` in one override; supply explicit
    /// string keys in that case.
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

Usage:
```swift
final class Counter: Component {
    @State var count = 0
    var body: VNode { button(.on("click") { self.count += 1 }) { text("\(count)") } }

    override func onChange() {
        onChange(of: count, key: "count") { newCount in
            print("count changed to \(newCount)")
        }
    }
}
```

Multiple watched values need explicit `key:` strings:
```swift
override func onChange() {
    onChange(of: count, key: "count") { ... }
    onChange(of: label, key: "label") { ... }
}
```

### `OnChangeStorage`

```swift
enum OnChangeStorage {
    nonisolated(unsafe) private static var table: [ObjectIdentifier: [String: Any]] = [:]

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
```

---

## Diff Threading

### `mount()` signature change

```swift
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    depth: Int = 0,
    path: String = "",
    environment: EnvironmentValues = .init()   // NEW
) -> MountNode
```

### `.environmentOverride` arm in `mount()`

```swift
case .environmentOverride(let overrides, let child):
    let h = handles.next()   // structural handle, never sent to driver
    let merged = environment.merging(overrides)
    let childMount = mount(child, into: &patches, handles: handles,
                           handlers: handlers, scheduler: scheduler,
                           depth: depth, path: path, environment: merged)
    return MountNode(handle: h, vnode: vnode, componentBody: childMount)
```

### `.component` arm in `mount()` — one line added

```swift
case .component(let desc):
    let instance = desc.instantiate()
    // ... existing wireStateAndRestore call unchanged ...
    AmbientEnvironment.current = environment    // NEW: set before body
    handlers.openScope(name: path)
    let bodyVNode = instance.instance.body      // @Environment reads happen here
    let bodyMount = mount(bodyVNode, ..., environment: environment)
    return MountNode(handle: h, vnode: vnode, component: instance, componentBody: bodyMount)
```

### `.environmentOverride` arm in `update()`

```swift
case (.environmentOverride(_, _), .environmentOverride(let nextOverrides, let nextChild)):
    let merged = environment.merging(nextOverrides)
    let updatedBody = update(mounted: node.componentBody!, next: nextChild,
                             ..., environment: merged)
    return MountNode(handle: node.handle, vnode: next, componentBody: updatedBody)
```

Type mismatch (one side is `.environmentOverride`, the other isn't) → destroy + remount, same as element-tag mismatch today.

### `destroy()` changes

```swift
// Clean up onChange side table on component unmount
if let any = node.component {
    any.instance.onDisappear()
    OnChangeStorage.remove(for: ObjectIdentifier(any.instance))   // NEW
    handlers.closeScope()
    // ...
}

// Skip destroyNode for structural .environmentOverride handles
if node.component == nil {
    if case .environmentOverride = node.vnode {
        // structural handle — no destroyNode patch
    } else {
        patches.append(.destroyNode(handle: node.handle))
    }
}
```

### `Renderer.renderOnce()` change

```swift
let result = diff(
    mounted: mountTree,
    next: nextVNode,
    handles: handles,
    handlers: handlers,
    scheduler: _schedulerBox.value,
    environment: .init()    // NEW
)
```

---

## Testing

### `EnvironmentValuesTests`

- `defaultLocaleIsEn` — `EnvironmentValues().locale == "en"`
- `defaultColorSchemeIsLight` — `EnvironmentValues().colorScheme == .light`
- `customKeyRoundTrips` — set via subscript, read back via subscript
- `mergingOverridesOverlappingKeys` — merge preserves non-overridden keys
- `mergingLeafWins` — later `merging` call wins on conflicting keys

### `EnvironmentThreadingTests`

Builds small `MountNode` trees by calling `mount()` directly (no JavaScriptKit required):

- `environmentPassedToComponentBody` — component reads `@Environment(\.locale)` during body; verify `AmbientEnvironment.current` is set correctly before call
- `environmentOverrideNodeMerges` — `.environmentOverride` in tree, child sees overridden value, sibling without override sees parent value
- `siblingsDontBleedEnvironment` — two sibling subtrees with different `withEnvironment` overrides don't cross-contaminate `AmbientEnvironment.current`

### `OnChangeStorageTests`

- `firstCallDoesNotFire` — `perform` not called on first call (no previous value)
- `sameValueDoesNotFire` — `perform` not called when value unchanged
- `changedValueFires` — `perform` called with new value when value changes
- `multipleKeysTrackedIndependently` — two `onChange(of:key:)` calls with different keys don't interfere
- `removeForClearsAllKeys` — `OnChangeStorage.remove(for:)` leaves no entries

---

## Out of Scope (Phase 10)

- `task { }` async lifecycle blocks — deferred until Swift Concurrency in WASM is verified
- `@Environment` reads outside of `body` (in `onAppear`, `onChange`) — components capture into stored properties
- `withEnvironment` multi-key overrides in a single call — nest `withEnvironment` calls instead
- Router environment keys (`\.router`, `\.navigate`) — declared in Phase 11 alongside `SwiflowRouter`
- `@EnvironmentObject` (reference-type shared objects) — out of scope for 1.0
