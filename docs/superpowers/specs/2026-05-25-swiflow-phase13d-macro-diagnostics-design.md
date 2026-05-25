# Phase 13d — Macro Diagnostics & `@Component`

**Date:** 2026-05-25
**Phase:** 13d (Maturity & 1.0 Readiness — Macro DX)
**Status:** Approved

---

## Goal

Reduce component authoring boilerplate via a `@Component` attached macro, and improve
`@ChildrenBuilder` error messages via `@available(*, unavailable)` overloads. No JS
changes. No WASM protocol changes.

---

## Context

Every Swiflow component today requires three annotations on its declaration line:

```swift
@MainActor
final class Counter: Component { ... }
```

`@MainActor` — main-actor isolation for stored properties  
`final` — prevents subclassing (required by the diff)  
`: Component` — protocol conformance

The `@ChildrenBuilder` result-builder error messages are generic Swift type errors
("Cannot convert value of type 'String' to expected element type '[VNode]'") rather
than actionable guidance.

Text nodes today require the full enum case path: `VNode.text("Hello")`. There is no
free `text()` builder function, making the scalar rendering ceremony inconsistent with
every other element builder (`div`, `span`, `p`, …).

This phase eliminates all three friction points without runtime cost.

---

## Architecture

### Package structure

One new target added to `Package.swift`:

```
SwiflowMacrosPlugin  (.macro target)
  SwiftSyntaxMacros + SwiftCompilerPlugin (swift-syntax ~600.0.0)
  ComponentMacro.swift
  SwiflowMacrosPlugin.swift

Swiflow  (.target) — gains dep on SwiflowMacrosPlugin
  Macros.swift  (public @Component macro declaration — inline in Swiflow)

SwiflowMacrosTests  (.testTarget)
  Swiflow + SwiflowMacrosPlugin + SwiftSyntaxMacrosTestSupport
```

**Why inline in `Swiflow`, not a separate `SwiflowMacros` library:**
`@attached(extension, conformances: Component)` requires `Component` to be in scope at
the macro declaration site. Since `Component` is defined in `Swiflow`, declaring the
macro in a separate module would either require that module to import `Swiflow` (creating
a circular dependency) or drop the `conformances:` hint (losing compiler tooling info).
Declaring the macro directly in `Sources/Swiflow/Macros.swift` sidesteps both problems:
`Component` is already in scope, and `import Swiflow` gives users `@Component` with no
extra import.

**On the name `@Component`:** the macro and the protocol share the same identifier,
identical to the `@Observable` / `Observable` pairing in Apple's Observation framework.
Swift's attribute namespace (`@`) is distinct from the type namespace, so there is no
ambiguity. Developers who know `@Observable` will recognise the pattern immediately.

`swift-syntax` pinned to `.upToNextMinor(from: "600.0.0")`. The compiler plugin compiles
to the macOS HOST architecture only — never included in the WASM binary.

### Net ergonomic delta

```swift
// Before
@MainActor
final class Counter: Component {
    @State var count: Int = 0
    var body: VNode { ... }
}

// After
@Component
final class Counter {
    @State var count: Int = 0
    var body: VNode { ... }
}
```

---

## Component-Level Changes

### `Package.swift`

- Add `swift-syntax` dependency: `.package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMinor(from: "600.0.0"))`
- Add `.macro(name: "SwiflowMacrosPlugin", dependencies: [SwiftSyntaxMacros, SwiftCompilerPlugin], path: "Sources/SwiflowMacrosPlugin", swiftSettings: [.swiftLanguageMode(.v6)])`
- Update `Swiflow` target dependencies to include `"SwiflowMacrosPlugin"`
- Add `.testTarget(name: "SwiflowMacrosTests", dependencies: ["Swiflow", "SwiflowMacrosPlugin", SwiftSyntaxMacrosTestSupport], path: "Tests/SwiflowMacrosTests", swiftSettings: [.swiftLanguageMode(.v6)])`

### `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` (new)

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiflowMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ComponentMacro.self]
}
```

### `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` (new)

`ComponentMacro` conforms to `MemberAttributeMacro` and `ExtensionMacro`.

**`MemberAttributeMacro` expansion** — receives each member in turn, returns attributes to prepend:
- `VariableDeclSyntax` whose first binding has no `accessorBlock` → stored property →
  return `[@MainActor]`
- `VariableDeclSyntax` with an `accessorBlock` (computed property, e.g. `body`) →
  return `[]`
- Member already carries `@MainActor` in its attribute list → return `[]` (no duplication)
- Member carries `nonisolated` → return `[]` (explicit isolation choice is respected;
  the macro never overrides an explicit `nonisolated` annotation)
- Any other member kind (functions, nested types) → return `[]`

**`ExtensionMacro` expansion** — returns the conformance extension and enforces class shape:
- `declaration` is not a `ClassDeclSyntax` → `context.diagnose` error:
  `"@Component requires a class — components are reference types in Swiflow"`
- Class lacks `final` modifier → `context.diagnose` error:
  `"@Component requires 'final' — components cannot be subclassed"`
- Return `extension <TypeName>: Component {}`

All diagnostic messages follow the `"@Component requires X — Y"` template: the first
clause states the requirement; the second, after the em-dash, explains why.

### `Sources/Swiflow/Macros.swift` (new)

Declared inline in `Swiflow` so that `Component` is in scope for the `conformances:` hint:

```swift
@attached(memberAttribute)
@attached(extension, conformances: Component)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")
```

### `Sources/Swiflow/DSL/Elements.swift`

Add free `text()` builder overloads alongside the existing element builders (`div`, `span`,
`p`, …). `text` is currently only accessible as `VNode.text("…")` (enum case); these
overloads make it consistent with the rest of the DSL and are the calling convention
the builder diagnostics point users toward:

```swift
public func text(_ string: String) -> VNode { .text(string) }
public func text(_ value: Int) -> VNode { .text(String(value)) }
public func text(_ value: Double) -> VNode { .text(String(value)) }
public func text(_ value: Bool) -> VNode { .text(String(value)) }
```

### `Sources/Swiflow/DSL/ResultBuilder.swift`

Add four `@available(*, unavailable)` overloads to `ChildrenBuilder`. These are more
specific than the existing `VNode`/`[VNode]` overloads so the compiler selects them when
the wrong type appears in a builder block and emits the message as the error.

All messages start with `"Use text(…)"`, matching the free-function overloads added
above and teaching a single rule: *non-VNode scalars belong in `text()`*.

```swift
@available(*, unavailable, message: "Use text(\"...\") to display a String")
public static func buildExpression(_ expression: String) -> [VNode] { [] }

@available(*, unavailable, message: "Use text(n) to display an integer")
public static func buildExpression<I: BinaryInteger>(_ expression: I) -> [VNode] { [] }

@available(*, unavailable, message: "Use text(n) to display a floating-point number")
public static func buildExpression<F: BinaryFloatingPoint>(_ expression: F) -> [VNode] { [] }

@available(*, unavailable, message: "Use text(flag) to display a Bool")
public static func buildExpression(_ expression: Bool) -> [VNode] { [] }
```

### `Sources/SwiflowCLI/Templates/Templates.swift`

Update the generated component template from:
```swift
@MainActor
final class \(name): Component {
```
to:
```swift
@Component
final class \(name) {
```

### `examples/HelloWorld/Sources/App/App.swift`

Update all components: `@MainActor final class App: Component` → `@Component final class App`.
Replace `VNode.text(…)` call-sites with the new free `text(…)` function.

---

## Data Flow

### Macro expansion (compile time)

```
User writes:
  @Component final class Counter { @State var count: Int = 0; var body: VNode { ... } }

MemberAttributeMacro fires per member:
  count  (stored, no accessor, no nonisolated) → prepend @MainActor
  body   (computed, has accessor)              → skip

ExtensionMacro fires:
  class is final ✓ → emit: extension Counter: Component {}

Effective result (shown in Xcode macro expansion):
  @MainActor @State var count: Int = 0
  var body: VNode { ... }
  extension Counter: Component {}
```

### Builder diagnostic (compile time)

```
User writes: div { "Hello" }

Compiler resolves buildExpression(_ expression: String)
→ finds @available(*, unavailable) overload
→ emits: 'buildExpression' is unavailable: Use text("...") to display a String
```

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `@Component struct Foo` | Compile error: "@Component requires a class — components are reference types in Swiflow" |
| `@Component class Foo` (not final) | Compile error: "@Component requires 'final' — components cannot be subclassed" |
| `@Component final class Foo` missing `body` | Existing compiler error from unmet protocol requirement (stretch: macro-level diagnostic) |
| Explicit `nonisolated var x` inside `@Component` class | `@MainActor` not added — explicit isolation choice is preserved |
| `String` in `ChildrenBuilder` block | Compile error: "Use text(\"...\") to display a String" |
| `Int` / `Float` / `Bool` in `ChildrenBuilder` block | Compile error with matching `"Use text(…)"` guidance message |

---

## Testing

### New: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift`

Six tests using `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`:

1. **Happy path** — `@Component final class Counter { @State var count: Int = 0; var body: VNode { ... } }` → `@MainActor` added to `count`, NOT to `body`; `extension Counter: Component {}` generated
2. **Non-final diagnostic** — `@Component class Counter { var body: VNode { ... } }` → error: "@Component requires 'final' — components cannot be subclassed"
3. **Struct diagnostic** — `@Component struct Counter { var body: VNode { ... } }` → error: "@Component requires a class — components are reference types in Swiflow"
4. **Computed property skipped** — `@Component final class Foo { var x: Int { 42 }; var body: VNode { ... } }` → `x` (computed) receives no `@MainActor`
5. **Already-isolated property** — `@Component final class Foo { @MainActor var x: Int = 0; var body: VNode { ... } }` → `@MainActor` not duplicated on `x`
6. **`nonisolated` respected** — `@Component final class Foo { nonisolated var x: Int = 0; var body: VNode { ... } }` → `@MainActor` NOT added to `x`

**Stretch goal (test 7):** `@Component final class Foo { }` (missing `body`) → macro-level error: "@Component requires a 'body' property returning VNode". Implement if `ExtensionMacro` expansion can scan members for `body` before emitting the conformance extension.

### Existing tests — no regressions expected

- `SwiflowTests`, `SwiflowTestingTests`, `SwiflowRouterTests` — no macro involvement
- `SwiflowCLITests` — template string change exercised by `swiflow init` integration test
- `DriverEmbedderTests.embeddedDriverIsFresh` — passes unchanged (no JS changes)

---

## File Map

| File | Change |
|---|---|
| `Package.swift` | Add `swift-syntax` dep; add `SwiflowMacrosPlugin` target + `SwiflowMacrosTests` test target; update `Swiflow` deps |
| `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` | New — `ComponentMacro: MemberAttributeMacro & ExtensionMacro` |
| `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` | New — `@main CompilerPlugin` |
| `Sources/Swiflow/Macros.swift` | New — `@Component` macro declaration (inline in `Swiflow`) |
| `Sources/Swiflow/DSL/Elements.swift` | Add `text(_:)` free builder overloads for `String`, `Int`, `Double`, `Bool` |
| `Sources/Swiflow/DSL/ResultBuilder.swift` | Add 4 `@available(*, unavailable)` `buildExpression` overloads |
| `Sources/SwiflowCLI/Templates/Templates.swift` | Update template to `@Component final class` |
| `examples/HelloWorld/Sources/App/App.swift` | Update to `@Component final class`; replace `VNode.text(…)` with `text(…)` |
| `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` | New — 6 macro expansion tests (+ stretch goal test 7) |

---

## Exit Criteria

1. `swift test` — all 506 existing tests pass + 6 new `SwiflowMacrosTests` = 512 green.
2. `@Component final class Counter { @State var count: Int = 0; var body: VNode { ... } }` compiles with zero warnings.
3. `@Component class Counter { ... }` (non-final) emits "@Component requires 'final' — components cannot be subclassed" on the `class` keyword.
4. A bare `String` in a `ChildrenBuilder` block emits "Use text(\"...\") to display a String".
5. `text(42)`, `text(3.14)`, `text(true)` compile and produce the expected `VNode.text(…)`.
6. `swiflow init` generates `@Component final class`-shaped components.
7. `DriverEmbedderTests.embeddedDriverIsFresh` passes unchanged.
8. README status line updated to "Phase 13d (Macro Diagnostics & @Component)".
