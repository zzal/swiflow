# Swiflow Phase 5 — API Polish Design

**Date:** 2026-05-19
**Status:** Spec
**Origin:** Taylor Otwell review (`docs/reviews/taylor-otwell-reviewer/2026-05-19-swiflow-and-cli-api-dx.md`)
**Predecessor:** Phase 4 — Hardening (complete)

## Goal

Address the five highest-priority API/DX concerns from the Taylor Otwell review, plus a public-surface audit, in one phase. Collapse the Hello World template from 12 lines of ceremony to a single readable component. Align lifecycle hooks and modifiers with SwiftUI muscle memory. Unify component instantiation around a single factory contract.

Pre-1.0 framework with no published users — breaking changes are made directly with no deprecation aliases.

## End-state target

```swift
final class Counter: Component {
    @State var count: Int = 0
    var body: VNode {
        div {
            h1("Hello, Swiflow!")
            p("Count: \(count)")
            button("Increment").on(.click) { self.count += 1 }
        }.class("container")
    }
}

Swiflow.render(into: "#app") { Counter() }
```

This is the template a new user will see. Every line below the class name should be idiomatic Swift that a SwiftUI developer can read at first glance.

## Out of scope

- Backwards compatibility shims, typealias deprecations, dual API surfaces
- Renaming `swiflowDiagnostic` (already effectively internal under `#if DEBUG`)
- Element factory tag-name rationalization beyond `a` → `link` and `main_` → `mainElement`
- Performance work, source maps, additional E2E coverage (Phase 5+ if needed)
- CLI changes (`--path` positional rework deferred — review nit, not in the top-5)

## Architecture

Three layers of change:

1. **Foundation**: `Component` becomes `@MainActor`-isolated, and a typed `Event` enum lands. These two changes enable everything else — the actor isolation removes the need for `@unchecked Sendable` and `MainActor.assumeIsolated` in user code, and the `Event` enum gives `.on` and the new postfix `.on` a typed API.

2. **API surface rework**: Five renames/restructurings, one per Taylor priority. Each is independently committable; tests are updated alongside.

3. **Public-surface audit**: Tighten visibility on types and members that leak internals (`HandlerRegistry`, `applyAttributes`, `AnyComponent` fields, `ComponentDescription` fields). Small renames that don't fit a priority (`a` → `link`, `main_` → `mainElement`, `InProcessScheduler` → `SyncScheduler`, `buildBlock` parameter).

## Detailed design

### Foundation A — `Component` is `@MainActor`-isolated

`Sources/Swiflow/Reactivity/Component.swift`:

```swift
@MainActor
public protocol Component: AnyObject {
    var body: VNode { get }
    func onAppear()
    func onChange()
    func onDisappear()
}

public extension Component {
    func onAppear() {}
    func onChange() {}
    func onDisappear() {}
}
```

Consequences:
- User-side `Counter` drops `, @unchecked Sendable` and the apologetic comment block.
- The renderer's call sites that invoke `onAppear`/`onChange`/`onDisappear` are already on `MainActor` (the renderer is `@MainActor`-isolated), so the actor hop disappears.
- The 18-line doc comment on the current `onUpdate(prev:)` explaining the existential-dispatch trampoline is deleted.
- `@State` mutations are already implicitly `@MainActor` once `Component` is — the `MainActor.assumeIsolated` in the Counter handler is unnecessary.

### Foundation B — Typed `Event` enum

New file `Sources/Swiflow/DSL/Event.swift`:

```swift
public enum Event: Sendable, Hashable {
    case click, input, change, submit
    case keydown, keyup, keypress
    case focus, blur
    case mousedown, mouseup, mousemove, mouseenter, mouseleave
    case custom(String)

    internal var domName: String {
        switch self {
        case .custom(let name): return name
        default: return String(describing: self)
        }
    }
}
```

The `.custom(_:)` escape hatch keeps the door open for events the enum doesn't ship. Default `String(describing:)` on simple cases yields `"click"`, `"input"`, etc. — exact DOM names. (One spelling check at design time: ensure case spellings match DOM event names verbatim; `keypress` is canonical.)

### Priority #1 — Clean handler API

**Change in `Sources/Swiflow/DSL/Modifiers.swift`**: replace the current `static func on(_ name: String, _ handlerID: ...)` API with:

```swift
public extension Attribute {
    static func on(_ event: Event, perform: @escaping @MainActor () -> Void) -> Attribute
    static func on(_ event: Event, perform: @escaping @MainActor (Event) -> Void) -> Attribute
}
```

Both variants:
- Register the closure with `HandlerRegistry` internally (user never touches the registry).
- Capture `self` strongly when needed — the framework guarantees handlers cannot outlive the owning component (see "Handler lifetime" below).
- Emit the same internal `Attribute` payload the renderer expects.

**`HandlerRegistry`** becomes `internal`. Callers that previously did `Swiflow.handlers.register { ... }` no longer have a public way in — they call `.on(.click) { ... }` instead.

**Handler lifetime:** the registry already maps IDs → closures, but eviction is currently scattered. We introduce a per-Component scope: when a `Component` mounts, its `onAppear` opens a new scope on the registry; when it unmounts (just before `onDisappear`), all handler IDs registered during that scope are evicted. This means closures can capture `self` strongly: the closure is dead before the component instance is.

### Priority #2 — `embed { Counter() }`

**Change in `Sources/Swiflow/DSL/ComponentDSL.swift`**: rename `component(_:key:)` → `embed`. Trailing-closure factory:

```swift
@MainActor
public func embed<C: Component>(_ factory: @escaping @MainActor () -> C) -> VNode

@MainActor
public func embed<C: Component>(_ key: String, _ factory: @escaping @MainActor () -> C) -> VNode
```

Call sites:

```swift
embed { Counter() }
embed("row-\(id)") { RowItem(id: id) }
```

The old `component({ Counter() })` form is deleted. The case-collision between `component` (function) and `Component` (protocol) evaporates.

### Priority #3 — Modifiers (variadic stays, postfix chaining added)

**Variadic at declaration is unchanged:**

```swift
div(.class("row"), .id("hero")) { ... }
```

**New postfix chaining via VNode extensions** in `Sources/Swiflow/DSL/VNode+Modifiers.swift`:

```swift
public extension VNode {
    func `class`(_ name: String) -> VNode
    func id(_ name: String) -> VNode
    func style(_ property: String, _ value: String) -> VNode

    func attr(_ name: String, _ value: String) -> VNode
    func attr(_ name: String, _ value: Int) -> VNode
    func attr(_ name: String, _ value: Bool) -> VNode
    func attr(_ name: String, _ value: Double) -> VNode

    func data(_ name: String, _ value: String) -> VNode

    func on(_ event: Event, perform: @escaping @MainActor () -> Void) -> VNode
    func on(_ event: Event, perform: @escaping @MainActor (Event) -> Void) -> VNode
}
```

**Implementation:**
- For `.element(tag, attrs, children)` cases, return a new `.element` with the new attribute appended to the bag.
- For non-element cases (`.text`, `.component`, `.rawHTML`), invoke `swiflowDiagnostic` in DEBUG (programmer error — modifying a text node) and return the node unchanged. Release builds silently no-op.

**Both styles coexist** so callers can mix declaration-time variadic with postfix when chains read better:

```swift
div(.id("hero")) { ... }.class("container").on(.click) { ... }
```

### Priority #4 — Unified factory for `Swiflow.render`

**Change in `Sources/SwiflowWeb/SwiflowWeb.swift`**:

```swift
@MainActor
public func render<C: Component>(
    into selector: String,
    _ factory: @escaping @MainActor () -> C
)
```

Call site:

```swift
Swiflow.render(into: "#app") { Counter() }
```

The old `render(_ component: Component, into selector:)` instance-taking form is deleted. Internally, `render` wraps the factory in a `ComponentDescription` — root and embedded components now share one mental model.

### Priority #5 — Lifecycle rename

Already shown in Foundation A. To restate:

- `onMount` → `onAppear`
- `onUpdate(prev:)` → `onChange()` (zero-arg; `prev:` parameter dropped from default surface)
- `onUnmount` → `onDisappear`
- The existential-dispatch trampoline doc-comment is deleted along with the `prev:` parameter.
- Authors who need pre-change state stash it themselves before mutation (or via a side field). `onChange()` fires *after* the change; it does not provide the prior value. The rare diffing use-case is no longer subsidized by the default protocol surface.

### Public-surface audit + smaller renames

**Visibility tightening:**
| Symbol | Was | Becomes |
|---|---|---|
| `applyAttributes(tag:_:children:)` in `Modifiers.swift` | `public` | `internal` |
| `HandlerRegistry` type + methods | `public` | `internal` |
| `AnyComponent.typeID`, `.instance` fields | `public` | `internal` (type stays `public`) |
| `ComponentDescription.factory`, `.typeID` fields | `public` | `internal` (type stays `public`) |

**Renames:**
| Old | New | Why |
|---|---|---|
| `a(_ text:)` in `Elements.swift` | `link(_ text:)` | one-letter free function shadows local bindings |
| `main_` in `Elements.swift` | `mainElement` | trailing-underscore sigil is the universal "gave up" mark |
| `InProcessScheduler` in `Scheduler.swift` | `SyncScheduler` | no `OutOfProcessScheduler` sibling exists; `In` prefix misleads |
| `ChildrenBuilder.buildBlock(_ components:)` | `buildBlock(_ children:)` | `component` is a thing in this framework — name collides |

**Type ergonomics:**
- `PropertyValue` adopts `ExpressibleByStringLiteral`, `ExpressibleByBooleanLiteral`, `ExpressibleByIntegerLiteral`, so `.prop("value", "hi")` works without `.string("hi")` wrappers.

## File structure

### Created
- `Sources/Swiflow/DSL/Event.swift` — typed `Event` enum
- `Sources/Swiflow/DSL/VNode+Modifiers.swift` — postfix chaining extensions
- `Tests/SwiflowTests/DSL/EventTests.swift`
- `Tests/SwiflowTests/DSL/VNodeModifiersTests.swift`
- `Tests/SwiflowTests/Reactivity/ComponentLifecycleTests.swift` (renamed; covers `onAppear`/`onChange`/`onDisappear`)

### Modified
- `Sources/Swiflow/Reactivity/Component.swift` — `@MainActor`, lifecycle rename, drop `prev:`
- `Sources/Swiflow/DSL/Modifiers.swift` — new `.on(_:perform:)` overloads; `applyAttributes` → `internal`; `PropertyValue` literal conformances
- `Sources/Swiflow/DSL/ComponentDSL.swift` — `component` → `embed`
- `Sources/Swiflow/DSL/Elements.swift` — `a` → `link`, `main_` → `mainElement`
- `Sources/Swiflow/DSL/ResultBuilder.swift` — `buildBlock` parameter rename
- `Sources/Swiflow/Reactivity/Scheduler.swift` — `InProcessScheduler` → `SyncScheduler`
- `Sources/Swiflow/Reactivity/HandlerRegistry.swift` — visibility to `internal`; per-Component scope
- `Sources/SwiflowWeb/SwiflowWeb.swift` — new factory-taking `render`
- `Sources/SwiflowWeb/Renderer.swift` — lifecycle hook call-site renames; per-Component handler scope hookup
- `Sources/SwiflowCLI/Templates.swift` — Counter rewrite (no `@unchecked Sendable`, postfix chain, new render)
- `README.md` — update "What's in the box" lifecycle names; update Counter snippet
- `tests/playwright/counter.spec.ts` — should still pass against the new template (same DOM); no change expected but verify
- All existing Swift tests that reference renamed symbols

### Deleted
- Old `component({...})` overloads from `ComponentDSL.swift`
- Old `render(_:into:)` instance-taking overload from `SwiflowWeb.swift`
- Old string-based `.on("click", handlerID)` `Attribute` static (replaced by `Event`-taking overloads)

## Task ordering

Same as Section A — eight tasks, each independently committable:

1. Foundation: `Component` is `@MainActor` + `Event` enum
2. Priority #1: clean handler API; `HandlerRegistry` → internal
3. Priority #5: lifecycle rename; drop `prev:`
4. Priority #2: `embed { ... }`
5. Priority #4: `Swiflow.render(into:) { ... }`
6. Priority #3: postfix chaining + `.attr` overloads + `.data`
7. Surface audit + smaller renames + `PropertyValue` literal conformances
8. Update Counter template + README snippets

Natural pause points after Task 2 (template gets cleanest line in the framework) and after Task 6 (modifier system change is the biggest visual diff).

## Testing strategy

- **Swift Testing suite** — every renamed/removed symbol gets a compile-time check. Tests are updated in the same PR as the rename.
- **JS driver `node:test`** — unchanged (no DOM behavior changes).
- **Playwright happy-path** — should pass without modification; the Counter renders the same DOM. Run it as the final acceptance gate before merging Task 8.

## Risk + mitigation

- **`Component` becoming `@MainActor` ripples to every existing component.** Mitigation: this is a one-time pre-1.0 change; all current components live in templates and tests under our control. Sweep all `Component`-conforming types in the same PR.
- **`[weak self]` removal in user handlers assumes lifetime guarantees.** Mitigation: Task 2 includes the per-Component handler scope (eviction on `onDisappear`). Without that, the safety story doesn't hold. Treat it as a hard requirement of Task 2, not optional polish.
- **Postfix chaining on non-element VNodes is a programmer error.** Mitigation: `swiflowDiagnostic` in DEBUG; silent pass-through in release. Tests cover both code paths.
- **`.custom(String)` Event escape hatch is a string foothold.** Mitigation: documented as the escape valve; nothing prevents users from typing it correctly. Adding common cases to the enum over time reduces reach for `.custom`.
