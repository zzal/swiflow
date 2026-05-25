# Phase 13d — Macro Diagnostics & `@Component` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `@Component` attached macro that eliminates `: Component` and synthesizes `@MainActor` on stored properties, plus `@available(*, unavailable)` overloads on `ChildrenBuilder` that turn cryptic type errors into "Use text(…)" guidance.

**Architecture:** One new `.macro` SPM target (`SwiflowMacrosPlugin`) holds the compiler plugin; the `@Component` macro declaration lives inline in the `Swiflow` module (so `Component` is in scope for `conformances:`), re-exported automatically with `import Swiflow`. Builder diagnostics are pure `@resultBuilder` overload resolution — no macro package needed for that half.

**Tech Stack:** Swift 6, SwiftSyntax / SwiftSyntaxMacros 600.x, Swift Testing (all existing tests), XCTest (macro expansion tests only — `SwiftSyntaxMacrosTestSupport` uses XCTest assertions).

---

## File Structure

| File | Role |
|---|---|
| `Package.swift` | Add `swift-syntax` dep; `SwiflowMacrosPlugin` macro target; `SwiflowMacrosTests` test target; update `Swiflow` deps |
| `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` | `@main CompilerPlugin` entry point |
| `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` | `ComponentMacro: MemberAttributeMacro & ExtensionMacro` + diagnostic enum |
| `Sources/Swiflow/Macros.swift` | Public `@Component` macro declaration (inline so `Component` is in scope) |
| `Sources/Swiflow/DSL/Elements.swift` | `text(_:)` free-function overloads for `String`, `Int`, `Double`, `Bool` |
| `Sources/Swiflow/DSL/ResultBuilder.swift` | Four `@available(*, unavailable)` `buildExpression` overloads |
| `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` | 6 XCTest macro expansion tests |
| `Tests/SwiflowTests/DSL/TextBuilderTests.swift` | 4 Swift Testing tests for `text()` overloads |
| `Tests/SwiflowTests/ComponentMacroIntegrationTests.swift` | Compile-time integration test: `@Component` accessible via `import Swiflow` |
| `Sources/SwiflowCLI/Templates/Templates.swift` | Update 3 component declarations to `@Component final class` |
| `examples/HelloWorld/Sources/App/App.swift` | Update 3 component declarations; replace `VNode.text(…)` with `text(…)` |
| `README.md` | Status line → Phase 13d |

---

### Task 1: Package scaffold — add swift-syntax and new targets

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift` (stub)
- Create: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` (stub)
- Create: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift` (stub)

- [ ] **Step 1: Edit `Package.swift`** — add the `swift-syntax` dependency, the macro target, update `Swiflow`, and add the test target.

Replace the entire `Package.swift` content with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
        .library(name: "SwiflowRouter", targets: ["SwiflowRouter"]),
        .library(name: "SwiflowTesting", targets: ["SwiflowTesting"]),
        .executable(name: "swiflow", targets: ["SwiflowCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.6.0")),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", .upToNextMinor(from: "2.2.0")),
        // swift-syntax powers the @Component macro compiler plugin.
        // Pinned to upToNextMinor: 600.x covers Swift 6; 601+ may introduce breaking API changes.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMinor(from: "600.0.0")),
    ],
    targets: [
        // Compiler plugin — runs on the macOS HOST at build time; never in the WASM binary.
        .macro(
            name: "SwiflowMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/SwiflowMacrosPlugin",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Swiflow",
            dependencies: ["SwiflowMacrosPlugin"],
            path: "Sources/Swiflow",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SwiflowCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ],
            path: "Sources/SwiflowCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowRouter",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowRouter",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowTesting",
            dependencies: ["Swiflow"],
            path: "Sources/SwiflowTesting",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowCLITests",
            dependencies: [
                "SwiflowCLI",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            ],
            path: "Tests/SwiflowCLITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowRouterTests",
            dependencies: ["SwiflowRouter"],
            path: "Tests/SwiflowRouterTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTestingTests",
            dependencies: ["SwiflowTesting", "Swiflow"],
            path: "Tests/SwiflowTestingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowMacrosTests",
            dependencies: [
                "SwiflowMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/SwiflowMacrosTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
```

- [ ] **Step 2: Create stub plugin entry point** — `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift`:

```swift
// Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiflowMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = []
}
```

- [ ] **Step 3: Create stub macro** — `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`:

```swift
// Sources/SwiflowMacrosPlugin/ComponentMacro.swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro {}
```

- [ ] **Step 4: Create stub test file** — `Tests/SwiflowMacrosTests/ComponentMacroTests.swift`:

```swift
// Tests/SwiflowMacrosTests/ComponentMacroTests.swift
import XCTest

final class ComponentMacroTests: XCTestCase {}
```

- [ ] **Step 5: Resolve packages and verify build**

Run: `swift package resolve && swift build`
Expected: Build succeeds. `swift-syntax` resolves (~20 MB download on first run).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/SwiflowMacrosPlugin/ Tests/SwiflowMacrosTests/
git commit -m "feat(pkg): add SwiflowMacrosPlugin macro target and SwiflowMacrosTests"
```

---

### Task 2: `text()` free functions + `ChildrenBuilder` diagnostics

**Files:**
- Create: `Tests/SwiflowTests/DSL/TextBuilderTests.swift`
- Modify: `Sources/Swiflow/DSL/Elements.swift` (append at end of file)
- Modify: `Sources/Swiflow/DSL/ResultBuilder.swift` (append at end of ChildrenBuilder enum)

- [ ] **Step 1: Write the failing tests** — `Tests/SwiflowTests/DSL/TextBuilderTests.swift`:

```swift
// Tests/SwiflowTests/DSL/TextBuilderTests.swift
import Testing
@testable import Swiflow

@Suite("text() free-function overloads")
struct TextBuilderTests {
    @Test func textString() { #expect(text("hi") == .text("hi")) }
    @Test func textInt()    { #expect(text(42) == .text("42")) }
    @Test func textDouble() { #expect(text(3.14) == .text("3.14")) }
    @Test func textBool()   { #expect(text(true) == .text("true")) }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TextBuilderTests`
Expected: FAIL — "cannot find 'text' in scope" (compiler error; test won't even compile)

- [ ] **Step 3: Add `text()` overloads to `Elements.swift`**

Append to the end of `Sources/Swiflow/DSL/Elements.swift` (after the final `main` function):

```swift

// MARK: - Text node builders

/// Text node from a `String`. Equivalent to `VNode.text(string)` but
/// consistent with the element-builder calling convention (`div`, `span`, …).
public func text(_ string: String) -> VNode { .text(string) }

/// Text node from an `Int`.
public func text(_ value: Int) -> VNode { .text(String(value)) }

/// Text node from a `Double`.
public func text(_ value: Double) -> VNode { .text(String(value)) }

/// Text node from a `Bool`.
public func text(_ value: Bool) -> VNode { .text(String(value)) }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TextBuilderTests`
Expected: PASS (4/4)

- [ ] **Step 5: Add `@available(*, unavailable)` overloads to `ResultBuilder.swift`**

Append inside the `ChildrenBuilder` enum, after the `buildArray` method:

```swift

    // MARK: - Diagnostic overloads
    //
    // These overloads are more specific than the VNode/[VNode] ones above, so
    // the compiler selects them when the wrong type appears in a builder block
    // and emits the @available message as the error. They are never called.

    @available(*, unavailable, message: "Use text(\"...\") to display a String")
    public static func buildExpression(_ expression: String) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(n) to display an integer")
    public static func buildExpression<I: BinaryInteger>(_ expression: I) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(n) to display a floating-point number")
    public static func buildExpression<F: BinaryFloatingPoint>(_ expression: F) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(flag) to display a Bool")
    public static func buildExpression(_ expression: Bool) -> [VNode] { [] }
```

- [ ] **Step 6: Run the full Swift test suite to confirm zero regressions**

Run: `swift test`
Expected: All existing tests pass (506+4 = 510 total). The unavailable overloads produce compiler errors only when wrong types are used; the existing passing tests use `VNode`/`[VNode]` which are unaffected.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/DSL/Elements.swift Sources/Swiflow/DSL/ResultBuilder.swift Tests/SwiflowTests/DSL/TextBuilderTests.swift
git commit -m "feat(dsl): add text() free-function overloads and ChildrenBuilder diagnostic overloads"
```

---

### Task 3: Macro expansion tests (failing)

**Files:**
- Modify: `Tests/SwiflowMacrosTests/ComponentMacroTests.swift`

These tests use `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport` (XCTest-based, not Swift Testing). The test target depends on `SwiflowMacrosPlugin` to access `ComponentMacro.self` directly.

- [ ] **Step 1: Replace stub test file with 6 expansion tests**

```swift
// Tests/SwiflowMacrosTests/ComponentMacroTests.swift
import XCTest
import SwiftSyntaxMacrosTestSupport
@testable import SwiflowMacrosPlugin

final class ComponentMacroTests: XCTestCase {
    private let macros: [String: any Macro.Type] = ["Component": ComponentMacro.self]

    // Test 1: happy path — @MainActor added to stored var, not to computed var; extension generated
    func testHappyPath() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var count: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            final class Counter {
                @MainActor @State var count: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }

            extension Counter: Component {
            }
            """,
            macros: macros
        )
    }

    // Test 2: non-final class emits "@Component requires 'final'" error
    func testNonFinalEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Component
            class Counter {
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            class Counter {
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component requires 'final' — components cannot be subclassed",
                    line: 2,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    // Test 3: struct emits "@Component requires a class" error
    func testStructEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @Component
            struct Counter {
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            struct Counter {
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component requires a class — components are reference types in Swiflow",
                    line: 2,
                    column: 1
                )
            ],
            macros: macros
        )
    }

    // Test 4: computed property (var with accessor block) does NOT get @MainActor
    func testComputedPropertySkipped() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                var x: Int { 42 }
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int { 42 }
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }

            extension Foo: Component {
            }
            """,
            macros: macros
        )
    }

    // Test 5: property already carrying @MainActor does NOT get a duplicate
    func testAlreadyMainActorNotDuplicated() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                @MainActor var x: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            final class Foo {
                @MainActor var x: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }

            extension Foo: Component {
            }
            """,
            macros: macros
        )
    }

    // Test 6: nonisolated property is NOT given @MainActor
    func testNonisolatedRespected() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                nonisolated var x: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }
            """,
            expandedSource: """
            final class Foo {
                nonisolated var x: Int = 0
                var body: VNode { .element(Element(tag: "div", attributes: [], children: [])) }
            }

            extension Foo: Component {
            }
            """,
            macros: macros
        )
    }
}
```

**Note on whitespace:** `assertMacroExpansion` performs an exact string comparison of the expanded source. The expected strings above represent the intended expansion; the precise leading/trailing whitespace, blank lines between members, and newlines before/after the extension block are dictated by how SwiftSyntax formats the output. After running the tests for the first time in Step 2, read the failure output to see the exact actual expansion, and update the `expandedSource` strings to match. This is normal and expected for macro tests.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SwiflowMacrosTests`
Expected: FAIL — all 6 tests fail because `ComponentMacro` has no conformances and produces no expansion.

- [ ] **Step 3: Commit the failing tests**

```bash
git add Tests/SwiflowMacrosTests/ComponentMacroTests.swift
git commit -m "test(macros): add 6 failing ComponentMacro expansion tests"
```

---

### Task 4: Implement `ComponentMacro`

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/ComponentMacro.swift`
- Modify: `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift`

- [ ] **Step 1: Implement `ComponentMacro.swift`**

Replace the stub content of `Sources/SwiflowMacrosPlugin/ComponentMacro.swift` with:

```swift
// Sources/SwiflowMacrosPlugin/ComponentMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro: MemberAttributeMacro, ExtensionMacro {

    // MARK: - MemberAttributeMacro

    /// Prepends `@MainActor` to each stored (non-computed) variable declaration
    /// that does not already carry `@MainActor` or `nonisolated`.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let varDecl = member.as(VariableDeclSyntax.self) else { return [] }

        // Skip computed properties — any binding with an accessorBlock is computed.
        guard varDecl.bindings.allSatisfy({ $0.accessorBlock == nil }) else { return [] }

        // Skip if already annotated with @MainActor.
        let hasMainActor = varDecl.attributes.contains {
            guard case .attribute(let attr) = $0,
                  let id = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return id.name.text == "MainActor"
        }
        guard !hasMainActor else { return [] }

        // Skip if explicitly nonisolated — respect the author's choice.
        let hasNonisolated = varDecl.modifiers.contains { $0.name.text == "nonisolated" }
        guard !hasNonisolated else { return [] }

        return [AttributeSyntax(
            attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
        )]
    }

    // MARK: - ExtensionMacro

    /// Emits `extension TypeName: Component {}` after validating class shape.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: ComponentMacroDiagnostic.requiresClass
            ))
            return []
        }

        guard classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            context.diagnose(Diagnostic(
                node: Syntax(classDecl.classKeyword),
                message: ComponentMacroDiagnostic.requiresFinal
            ))
            return []
        }

        return [try ExtensionDeclSyntax("extension \(type): Component {}")]
    }
}

// MARK: - Diagnostics

enum ComponentMacroDiagnostic: DiagnosticMessage {
    case requiresClass
    case requiresFinal

    var message: String {
        switch self {
        case .requiresClass:
            return "@Component requires a class — components are reference types in Swiflow"
        case .requiresFinal:
            return "@Component requires 'final' — components cannot be subclassed"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiflowMacros", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 2: Register `ComponentMacro` in the plugin entry point**

Replace `Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift`:

```swift
// Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiflowMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [ComponentMacro.self]
}
```

- [ ] **Step 3: Run macro tests**

Run: `swift test --filter SwiflowMacrosTests`
Expected: 6 tests pass. If any fail due to whitespace differences in `expandedSource`, read the failure output for the exact actual expansion and update the expected string to match, then re-run.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowMacrosPlugin/ComponentMacro.swift Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift
git commit -m "feat(macros): implement ComponentMacro — MemberAttributeMacro + ExtensionMacro"
```

---

### Task 5: Declare `@Component` in `Swiflow` and write integration test

**Files:**
- Create: `Sources/Swiflow/Macros.swift`
- Create: `Tests/SwiflowTests/ComponentMacroIntegrationTests.swift`

- [ ] **Step 1: Create `Sources/Swiflow/Macros.swift`**

The declaration is in `Swiflow` (not a separate module) so that `Component` is in scope for `conformances: Component`. Users get `@Component` automatically with `import Swiflow`.

```swift
// Sources/Swiflow/Macros.swift

/// Reduces component declaration boilerplate.
///
/// Attach to a `final class` to automatically:
/// 1. Add `@MainActor` to each stored (non-computed, non-`nonisolated`) property.
/// 2. Add `: Component` conformance via a synthesised extension.
///
/// ```swift
/// @Component
/// final class Counter {
///     @State var count: Int = 0
///     var body: VNode { p("Count: \(count)") }
/// }
/// ```
///
/// - Note: `final` is still required; the macro enforces this with a compile-time error.
///   Explicit `nonisolated` annotations are preserved — the macro never overrides them.
/// - Note: The macro name shares the identifier `Component` with the protocol, identical to
///   how `@Observable` coexists with `Observable` in Apple's Observation framework.
@attached(memberAttribute)
@attached(extension, conformances: Component)
public macro Component() = #externalMacro(module: "SwiflowMacrosPlugin", type: "ComponentMacro")
```

- [ ] **Step 2: Create integration test** — `Tests/SwiflowTests/ComponentMacroIntegrationTests.swift`:

This file defines a component using `@Component` at module scope. If the macro isn't exported from `Swiflow`, or if the expansion is wrong, this file will not compile.

```swift
// Tests/SwiflowTests/ComponentMacroIntegrationTests.swift
import Testing
import Swiflow

// Module-scope declaration — extension must be at top level, so the component
// cannot be nested inside a function body.
@Component
private final class _IntegrationView {
    var body: VNode { div() }
}

@Suite("@Component macro integration")
struct ComponentMacroIntegrationTests {
    @Test @MainActor func componentMacroConformsToProtocol() {
        // If @Component failed to synthesise the conformance, this cast fails to compile.
        let _: any Component = _IntegrationView()
    }
}
```

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: All tests pass (510 from Task 2 + 1 new integration test = 511 total). The macro test suite (6 tests, XCTest) is also counted.

- [ ] **Step 4: Commit**

```bash
git add Sources/Swiflow/Macros.swift Tests/SwiflowTests/ComponentMacroIntegrationTests.swift
git commit -m "feat(swiflow): declare @Component macro; add integration test"
```

---

### Task 6: Update templates, example, and README

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `README.md`

- [ ] **Step 1: Update `Templates.swift`**

There are three component declarations in the `rawAppSwift` template string. Find and replace each one.

In `Sources/SwiflowCLI/Templates/Templates.swift`, make these three replacements (the exact indentation inside the multi-line string literal uses 8 spaces):

Replacement 1 — Counter class declaration:
```
// OLD (around line 107):
        final class Counter: Component {

// NEW:
        @Component
        final class Counter {
```

Replacement 2 — Toast class declaration:
```
// OLD (around line 190):
        final class Toast: Component {

// NEW:
        @Component
        final class Toast {
```

Replacement 3 — SignIn class declaration:
```
// OLD (around line 235):
        final class SignIn: Component {

// NEW:
        @Component
        final class SignIn {
```

Also replace `VNode.text` calls in the template with `text`:

```
// OLD (around line 161):
                        VNode.text(" Celebrate")

// NEW:
                        text(" Celebrate")
```

```
// OLD (around line 223):
                    VNode.text(message)

// NEW:
                    text(message)
```

- [ ] **Step 2: Update `examples/HelloWorld/Sources/App/App.swift`**

The template and the example file must stay byte-identical (the `DriverEmbedderTests.embeddedDriverIsFresh` test doesn't cover App.swift, but keeping them in sync is the project convention — see `project-js-driver-embedded-sync` memory for the rationale on consistency).

Make these replacements in `examples/HelloWorld/Sources/App/App.swift`:

```
// OLD (line 15):
final class Counter: Component {

// NEW:
@Component
final class Counter {
```

```
// OLD (line 98):
final class Toast: Component {

// NEW:
@Component
final class Toast {
```

```
// OLD (line 143):
final class SignIn: Component {

// NEW:
@Component
final class SignIn {
```

Replace `VNode.text` calls:

```
// OLD (line 69):
                VNode.text(" Celebrate")

// NEW:
                text(" Celebrate")
```

```
// OLD (line 131):
            VNode.text(message)

// NEW:
            text(message)
```

- [ ] **Step 3: Update the README status line**

In `README.md`, find the line containing `Phase 13c (Multi-Root & Unmount)` in the `**Status:**` paragraph and update it:

```
// OLD:
**Status:** Phase 13c (Multi-Root & Unmount) — Multiple component trees can be mounted…

// NEW:
**Status:** Phase 13d (Macro Diagnostics & @Component) — `@Component` macro eliminates `@MainActor` + `: Component` boilerplate; `ChildrenBuilder` emits actionable "Use text(…)" errors for wrong-typed children; `text()` free-function overloads added for `String`, `Int`, `Double`, `Bool`.
```

Also update the "What works today" section heading (around line 18) from:
```
**What works today (Phase 13c):**
```
to:
```
**What works today (Phase 13d):**
```

And the status summary line (around line 63) from:
```
**Status:** Phase 13c (Multi-Root & Unmount) complete.
```
to:
```
**Status:** Phase 13d (Macro Diagnostics & @Component) complete.
```

- [ ] **Step 4: Run the full test suite one final time**

Run: `swift test`
Expected: All 512 tests pass (506 original + 4 `text()` overload tests + 1 integration test + 6 macro expansion tests — note the CLI integration tests exercise the updated template). Zero regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift examples/HelloWorld/Sources/App/App.swift README.md
git commit -m "feat(template): update to @Component; add text() calls; update README to Phase 13d"
```

---

## Exit Criteria Checklist

- [ ] `swift test` — 512 tests green, zero failures
- [ ] `@Component final class Counter { @State var count: Int = 0; var body: VNode { div() } }` compiles with zero warnings
- [ ] `@Component class Counter { … }` (non-final) emits "@Component requires 'final' — components cannot be subclassed"
- [ ] `@Component struct Counter { … }` emits "@Component requires a class — components are reference types in Swiflow"
- [ ] `text(42)`, `text(3.14)`, `text(true)`, `text("hi")` all compile and produce `VNode.text("…")`
- [ ] A bare `String` in a `ChildrenBuilder` block emits "Use text(\"...\") to display a String"
- [ ] `swiflow init` template generates `@Component final class`-shaped components
- [ ] `DriverEmbedderTests.embeddedDriverIsFresh` passes (no JS changes)
- [ ] README status line reads "Phase 13d (Macro Diagnostics & @Component)"
