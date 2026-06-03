# SwiflowUI Foundation v0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `SwiflowUI` module's styling foundation (a `--sw-*` design-token contract + a once-injected base sheet) and prove it with `VStack`/`HStack`.

**Architecture:** Layout primitives are capitalized free functions returning `VNode` (no parallel `View` tree). Dynamic axes (gap/align/justify/padding) lower to **inline styles referencing token vars**; the `:root` token block is injected **once** via a new host-testable `StyleInjectionRegistry` in core `Swiflow` (which `CSSInjector` is also migrated onto, for DRY). Injection auto-fires on first primitive render.

**Tech Stack:** Swift 6 (language mode v6), Swiflow `VNode`/`CSSSheet`/DSL, JavaScriptKit (WASM, guarded), Swift Testing.

**Source spec:** `docs/superpowers/specs/2026-06-03-swiflowui-foundation-design.md`

---

## Constraints for implementers (read first)

- **Git:** You may `git add`/`git commit` on the CURRENT branch only. Do **NOT** run `git checkout`/`switch`/`branch`/`stash`/`reset`/`restore` — the working tree is shared and switching strands the controller.
- **Diagnostics:** IDE/SourceKit "No such module" / "cannot find type" errors are frequently **stale**. Trust only `swift build` / `swift test` output.
- **Known flake:** `OnChangeStorageTests` fails ~1/3 under parallel `swift test` and passes in isolation. It is **not** a regression from this work — ignore it if it's the only failure.
- **Global-static test hygiene:** `StyleInjectionRegistry` holds process-global state. Every test that touches it MUST call `StyleInjectionRegistry.reset()` at the top, or sibling tests will pollute each other (see the OnChangeStorage flake for why this matters).
- **Verify before done:** run the exact commands shown; paste real output.

## File structure

| File | Responsibility |
|------|----------------|
| `Sources/Swiflow/DSL/Elements.swift` (modify) | Add public `element(_:attributes:children:)` — array-attribute factory over `applyAttributes`. |
| `Sources/Swiflow/CSS/StyleInjectionRegistry.swift` (create) | Pure, host-testable once-injection guard + emit hook. |
| `Sources/SwiflowWeb/CSS/CSSInjector.swift` (modify) | Route through `StyleInjectionRegistry`; register the DOM emit hook. |
| `Sources/SwiflowWeb/SwiflowWeb.swift` (modify) | Wire emit hook at `CSSInjector.setup()` call site (already present). |
| `Sources/SwiflowUI/Tokens.swift` (create) | `Spacing` / `CrossAlign` / `MainAlign` enums + `.css` mappings. |
| `Sources/SwiflowUI/Theme.swift` (create) | `SwiflowUI.baseStyleSheet` + `installBaseStyles()` + internal `ensureBaseStyles()`. |
| `Sources/SwiflowUI/Stack.swift` (create) | `VStack` / `HStack` + private `stack(...)` helper. |
| `Sources/SwiflowUI/Modifiers.swift` (create) | `.padding(_:)` / `.gap(_:)` `VNode` extensions. |
| `Package.swift` (modify) | `SwiflowUI` library target + product, `SwiflowUITests` test target. |
| `Tests/SwiflowTests/ElementFactoryTests.swift` (create) | Cover `element(...)`. |
| `Tests/SwiflowTests/StyleInjectionRegistryTests.swift` (create) | Cover the registry. |
| `Tests/SwiflowUITests/{Tokens,Theme,Stack,Modifier}Tests.swift` (create) | Cover SwiflowUI. |
| `examples/SwiflowUIDemo/**` (create) | Browser proof + documented usage; triggers `EmbeddedTemplates` regen. |

---

## Task 1: Public `element(_:attributes:children:)` factory

SwiflowUI needs to build a `div` from an `[Attribute]` array (it can't splat into the variadic `div(...)`), and `applyAttributes` is `internal`. Add a thin public wrapper.

**Files:**
- Modify: `Sources/Swiflow/DSL/Elements.swift` (append at end, before the `// MARK: - Text node builders` section is fine; place after `hr`)
- Test: `Tests/SwiflowTests/ElementFactoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/ElementFactoryTests.swift
import Testing
@testable import Swiflow

@Suite("element(_:attributes:children:)")
struct ElementFactoryTests {
    @Test func buildsElementWithAttributesAndChildren() {
        let node = element("div",
                           attributes: [.class("row"), .style("display", "flex")],
                           children: [text("hi")])
        guard case .element(let data) = node else { Issue.record("not an element"); return }
        #expect(data.tag == "div")
        #expect(data.attributes["class"] == "row")
        #expect(data.style["display"] == "flex")
        #expect(data.children.count == 1)
    }

    @Test func defaultsAreEmpty() {
        let node = element("span")
        guard case .element(let data) = node else { Issue.record("not an element"); return }
        #expect(data.tag == "span")
        #expect(data.attributes.isEmpty)
        #expect(data.children.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ElementFactoryTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'element' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Append to Sources/Swiflow/DSL/Elements.swift (after `hr`)

/// Programmatic element factory taking an `[Attribute]` array (the variadic
/// element factories like `div(...)` can't be called with a spliced array).
/// Folds attributes through the same `applyAttributes` path as every other
/// factory, so URL sanitization, `.compound` flattening, and key extraction
/// all behave identically. Used by SwiflowUI primitives and any caller that
/// assembles attributes dynamically.
public func element(
    _ tag: String,
    attributes: [Attribute] = [],
    children: [VNode] = []
) -> VNode {
    .element(applyAttributes(tag: tag, attributes, children: children))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ElementFactoryTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/Elements.swift Tests/SwiflowTests/ElementFactoryTests.swift
git commit -m "feat(dsl): public element(_:attributes:children:) array factory"
```

---

## Task 2: `StyleInjectionRegistry` (pure, host-testable once-injection)

The guard + emit seam. Lives in core `Swiflow` so it compiles on host and WASM and is unit-testable without a DOM.

**Files:**
- Create: `Sources/Swiflow/CSS/StyleInjectionRegistry.swift`
- Test: `Tests/SwiflowTests/StyleInjectionRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/StyleInjectionRegistryTests.swift
import Testing
@testable import Swiflow

@Suite("StyleInjectionRegistry")
@MainActor
struct StyleInjectionRegistryTests {
    @Test func emitsOncePerID() {
        StyleInjectionRegistry.reset()
        var emitted: [(String, String)] = []
        StyleInjectionRegistry.emit = { id, css in emitted.append((id, css)) }
        defer { StyleInjectionRegistry.emit = nil }

        StyleInjectionRegistry.injectOnce(id: "a") { "x{}" }
        StyleInjectionRegistry.injectOnce(id: "a") { "x{}" }   // guarded — no second emit
        #expect(emitted.count == 1)
        #expect(emitted.first?.0 == "a")
        #expect(emitted.first?.1 == "x{}")
    }

    @Test func cssClosureNotEvaluatedWhenGuarded() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = { _, _ in }
        defer { StyleInjectionRegistry.emit = nil }
        var builds = 0
        StyleInjectionRegistry.injectOnce(id: "b") { builds += 1; return "y{}" }
        StyleInjectionRegistry.injectOnce(id: "b") { builds += 1; return "y{}" }
        #expect(builds == 1)   // second call short-circuits before building css
    }

    @Test func resetReArms() {
        StyleInjectionRegistry.reset()
        var count = 0
        StyleInjectionRegistry.emit = { _, _ in count += 1 }
        defer { StyleInjectionRegistry.emit = nil }
        StyleInjectionRegistry.injectOnce(id: "c") { "z{}" }
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.injectOnce(id: "c") { "z{}" }
        #expect(count == 2)
    }

    @Test func injectOnceReturnsWhetherItEmitted() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = { _, _ in }
        defer { StyleInjectionRegistry.emit = nil }
        #expect(StyleInjectionRegistry.injectOnce(id: "d") { "" } == true)
        #expect(StyleInjectionRegistry.injectOnce(id: "d") { "" } == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StyleInjectionRegistryTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'StyleInjectionRegistry' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Swiflow/CSS/StyleInjectionRegistry.swift
//
// Process-global "inject this stylesheet exactly once" guard, shared by
// CSSInjector (per-component scoped sheets) and SwiflowUI (its base token
// sheet). The guard + once-semantics live here in pure Swiflow so they're
// host-testable; the actual DOM emit is a closure SwiflowWeb registers at
// startup (mirrors the `onComponentTypeMount` / CSSMountHook pattern).

/// Tracks which style ids have been injected and routes the emit through a
/// swappable sink. `@MainActor` because all rendering — and therefore all
/// injection — happens on the main actor (single-threaded WASM).
@MainActor
public enum StyleInjectionRegistry {
    /// Ids already injected this session.
    private static var injectedIDs: Set<String> = []

    /// The emit sink. SwiflowWeb sets this to append a `<style>` to `<head>`.
    /// `nil` on a host with no DOM (tests/headless): `injectOnce` still records
    /// the id (preserving once-semantics) but emits nothing.
    public static var emit: ((_ id: String, _ css: String) -> Void)?

    /// Injects `css` under `id` exactly once. The `css` builder runs only on
    /// the first call for an id (so repeat renders don't rebuild the string).
    /// Returns `true` iff this call performed the (first) injection.
    @discardableResult
    public static func injectOnce(id: String, css: () -> String) -> Bool {
        guard !injectedIDs.contains(id) else { return false }
        injectedIDs.insert(id)
        emit?(id, css())
        return true
    }

    /// Forgets all injected ids so the next `injectOnce` re-emits. Tests/HMR.
    public static func reset() { injectedIDs = [] }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StyleInjectionRegistryTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/CSS/StyleInjectionRegistry.swift Tests/SwiflowTests/StyleInjectionRegistryTests.swift
git commit -m "feat(css): StyleInjectionRegistry — host-testable once-injection seam"
```

---

## Task 3: Migrate `CSSInjector` onto the registry (DRY, build-verified)

Route the existing per-component injection through `StyleInjectionRegistry` so there is one once-injection path. This module is WASM-only (`#if canImport(JavaScriptKit)`) and has no host unit tests; the guard logic is now covered by Task 2, so this task is a mechanical refactor verified by `swift build`.

**Files:**
- Modify: `Sources/SwiflowWeb/CSS/CSSInjector.swift`

- [ ] **Step 1: Replace the body of `CSSInjector`**

Replace the entire `enum CSSInjector { ... }` body (keep the file's `#if canImport(JavaScriptKit)` / `import` / `#endif` shell) with:

```swift
@MainActor
enum CSSInjector {
    /// Wires the registry's emit sink to a real `<head>` `<style>` append, then
    /// installs the component-mount hook that injects each type's scoped sheet.
    static func setup() {
        StyleInjectionRegistry.emit = { id, css in
            appendStyle(id: id, css: css)
        }
        onComponentTypeMount = { componentType in
            CSSInjector.inject(for: componentType)
        }
    }

    /// Injects a `<style>` for `componentType` if it declares non-empty
    /// `scopedStyles`. De-duplication is owned by `StyleInjectionRegistry`.
    static func inject(for componentType: any Component.Type) {
        guard let sheet = componentType.scopedStyles else { return }
        let typeName = String(describing: componentType)
        let scopeClass = "swiflow-\(typeName)"
        StyleInjectionRegistry.injectOnce(id: scopeClass) {
            sheet.cssString(scopeClass: scopeClass)
        }
    }

    /// Appends a `<style id=...>` to `<head>` carrying `css`. Skips when a
    /// `<style>` with that id already exists in the document (e.g. an HMR swap
    /// re-running setup) or when `css` is empty.
    private static func appendStyle(id: String, css: String) {
        guard !css.isEmpty else { return }
        let document = JSObject.global.document
        let existing = document.getElementById(id)
        guard existing == .undefined || existing == .null else { return }
        let style = document.createElement("style").object!
        style.id = .string(id)
        style.textContent = .string(css)
        _ = document.head.object!.appendChild!(style)
    }

    /// Clears the registry guard so styles re-inject on the next mount. Tests/HMR.
    static func reset() { StyleInjectionRegistry.reset() }
}
```

Notes for the implementer:
- The old `private static var injected: Set<ObjectIdentifier>` is gone — the registry now owns the guard (keyed by the `scopeClass` string, which is 1:1 with the component type).
- `CSSInjector.reset()` now delegates to `StyleInjectionRegistry.reset()`; keep the method so existing callers (HMR/tests) still compile.
- `import Swiflow` must remain so `StyleInjectionRegistry`, `onComponentTypeMount`, and `Component` are in scope.

- [ ] **Step 2: Verify it builds (host)**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` (host build compiles `SwiflowWeb`'s non-JS surface; the JS-guarded code is type-checked when `canImport(JavaScriptKit)` — confirm no errors).

> If `swift build` does not type-check the `#if canImport(JavaScriptKit)` branch on this host, additionally run the WASM build the repo uses (the implementer should use the project's standard WASM build command, e.g. `swift package --swift-sdk wasm32-unknown-wasi js` or the documented `swiflow build` path) and confirm it compiles. Report which command was used.

- [ ] **Step 3: Run the full host test suite (no regressions)**

Run: `swift test 2>&1 | tail -30`
Expected: all pass except possibly the known `OnChangeStorageTests` parallel flake (re-run `swift test --filter OnChangeStorageTests` in isolation to confirm it passes alone).

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowWeb/CSS/CSSInjector.swift
git commit -m "refactor(css): route CSSInjector through StyleInjectionRegistry (DRY)"
```

---

## Task 4: `SwiflowUI` target + `Tokens.swift`

Create the module (with its first source file so the package builds) and the token enums.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowUI/Tokens.swift`
- Test: `Tests/SwiflowUITests/TokensTests.swift`

- [ ] **Step 1: Add the target + product + test target to `Package.swift`**

In `products:`, add after the `SwiflowHTTP` library line:
```swift
        .library(name: "SwiflowUI", targets: ["SwiflowUI"]),
```

In `targets:`, add after the `SwiflowHTTP` target:
```swift
        .target(
            name: "SwiflowUI",
            dependencies: [
                "Swiflow",
                "SwiflowWeb",
            ],
            path: "Sources/SwiflowUI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

In `targets:`, add after the `SwiflowHTTPTests` test target:
```swift
        .testTarget(
            name: "SwiflowUITests",
            dependencies: ["SwiflowUI", "Swiflow"],
            path: "Tests/SwiflowUITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/SwiflowUITests/TokensTests.swift
import Testing
@testable import SwiflowUI

@Suite("Tokens")
struct TokensTests {
    @Test func spacingMapsToVars() {
        #expect(Spacing.none.css == "0")
        #expect(Spacing.xs.css == "var(--sw-space-xs)")
        #expect(Spacing.md.css == "var(--sw-space-md)")
        #expect(Spacing.xl.css == "var(--sw-space-xl)")
        #expect(Spacing.custom("13px").css == "13px")
    }
    @Test func spacingIsEquatable() {
        #expect(Spacing.md == Spacing.md)
        #expect(Spacing.md != Spacing.none)
    }
    @Test func crossAlignMapsToAlignItems() {
        #expect(CrossAlign.start.css == "flex-start")
        #expect(CrossAlign.center.css == "center")
        #expect(CrossAlign.end.css == "flex-end")
        #expect(CrossAlign.stretch.css == "stretch")
        #expect(CrossAlign.baseline.css == "baseline")
    }
    @Test func mainAlignMapsToJustifyContent() {
        #expect(MainAlign.start.css == "flex-start")
        #expect(MainAlign.center.css == "center")
        #expect(MainAlign.end.css == "flex-end")
        #expect(MainAlign.between.css == "space-between")
        #expect(MainAlign.around.css == "space-around")
        #expect(MainAlign.evenly.css == "space-evenly")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter TokensTests 2>&1 | tail -20`
Expected: FAIL — `no such module 'SwiflowUI'` or `cannot find 'Spacing'`.

- [ ] **Step 4: Write the implementation**

```swift
// Sources/SwiflowUI/Tokens.swift

/// A spacing value drawn from the `--sw-space-*` scale (or an arbitrary length).
/// `.css` is the CSS value written inline (token-var or raw literal); reskinning
/// happens by overriding the var at `:root`, even for inline uses.
public enum Spacing: Equatable {
    case none, xs, sm, md, lg, xl
    case custom(String)

    public var css: String {
        switch self {
        case .none:          return "0"
        case .xs:            return "var(--sw-space-xs)"
        case .sm:            return "var(--sw-space-sm)"
        case .md:            return "var(--sw-space-md)"
        case .lg:            return "var(--sw-space-lg)"
        case .xl:            return "var(--sw-space-xl)"
        case .custom(let v): return v
        }
    }
}

/// Cross-axis alignment → `align-items`.
public enum CrossAlign: Equatable {
    case start, center, end, stretch, baseline
    public var css: String {
        switch self {
        case .start:    return "flex-start"
        case .center:   return "center"
        case .end:      return "flex-end"
        case .stretch:  return "stretch"
        case .baseline: return "baseline"
        }
    }
}

/// Main-axis distribution → `justify-content`.
public enum MainAlign: Equatable {
    case start, center, end, between, around, evenly
    public var css: String {
        switch self {
        case .start:   return "flex-start"
        case .center:  return "center"
        case .end:     return "flex-end"
        case .between: return "space-between"
        case .around:  return "space-around"
        case .evenly:  return "space-evenly"
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter TokensTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SwiflowUI/Tokens.swift Tests/SwiflowUITests/TokensTests.swift
git commit -m "feat(swiflowui): scaffold module + Spacing/CrossAlign/MainAlign tokens"
```

---

## Task 5: `Theme.swift` — base token sheet + lazy install

**Files:**
- Create: `Sources/SwiflowUI/Theme.swift`
- Test: `Tests/SwiflowUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowUITests/ThemeTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@Suite("Theme")
@MainActor
struct ThemeTests {
    @Test func baseSheetContainsRootTokens() {
        let css = SwiflowUI.baseStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(":root"))
        #expect(css.contains("--sw-space-md"))
        #expect(css.contains("--sw-accent"))
        // :root must NOT be scoped (CSSSheet leaves it alone).
        #expect(!css.contains(".swiflow"))
    }

    @Test func installBaseStylesEmitsOnce() {
        StyleInjectionRegistry.reset()
        var ids: [String] = []
        StyleInjectionRegistry.emit = { id, _ in ids.append(id) }
        defer { StyleInjectionRegistry.emit = nil }

        SwiflowUI.installBaseStyles()
        SwiflowUI.installBaseStyles()
        #expect(ids == ["swiflow-ui-base"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThemeTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'SwiflowUI' in scope` / `baseStyleSheet`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/SwiflowUI/Theme.swift
import Swiflow

/// Namespace for SwiflowUI's module-level theme surface.
public enum SwiflowUI {
    /// The design-token contract: the full `--sw-*` vocabulary at `:root`.
    /// v0 primitives consume only the spacing scale + alignment; the rest is
    /// the forward contract that skinned components will read. Authored as a
    /// `CSSSheet` so it's one source of truth; `:root` is left unscoped by
    /// `CSSSheet`'s scoping rules.
    public static let baseStyleSheet: CSSSheet = css {
        raw("""
        :root {
          --sw-space-xs: 0.25rem;
          --sw-space-sm: 0.5rem;
          --sw-space-md: 0.75rem;
          --sw-space-lg: 1.25rem;
          --sw-space-xl: 2rem;
          --sw-radius: 8px;
          --sw-accent: light-dark(#3b82f6, #60a5fa);
          --sw-surface: light-dark(#ffffff, #1a1a1a);
          --sw-text: light-dark(#111111, #f5f5f5);
        }
        """)
    }

    /// Injects `baseStyleSheet` into `<head>` exactly once. Called automatically
    /// the first time any SwiflowUI primitive renders; also public so apps/tests
    /// can install deterministically up front.
    @MainActor
    public static func installBaseStyles() {
        StyleInjectionRegistry.injectOnce(id: "swiflow-ui-base") {
            baseStyleSheet.cssString(scopeClass: "")
        }
    }
}

/// Internal trigger called by every primitive constructor. Idempotent.
@MainActor
func ensureBaseStyles() { SwiflowUI.installBaseStyles() }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ThemeTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift
git commit -m "feat(swiflowui): base token sheet + lazy-once installBaseStyles"
```

---

## Task 6: `Stack.swift` — `VStack` / `HStack`

**Files:**
- Create: `Sources/SwiflowUI/Stack.swift`
- Test: `Tests/SwiflowUITests/StackTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowUITests/StackTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Stack")
@MainActor
struct StackTests {
    @Test func vstackLowersToFlexColumn() {
        let s = styleOf(VStack(spacing: .md, align: .center, justify: .between) { text("x") })
        #expect(s["display"] == "flex")
        #expect(s["flex-direction"] == "column")
        #expect(s["gap"] == "var(--sw-space-md)")
        #expect(s["align-items"] == "center")
        #expect(s["justify-content"] == "space-between")
    }

    @Test func hstackLowersToFlexRow() {
        let s = styleOf(HStack { text("x") })
        #expect(s["display"] == "flex")
        #expect(s["flex-direction"] == "row")
        #expect(s["align-items"] == "stretch")        // default
        #expect(s["justify-content"] == "flex-start") // default
    }

    @Test func gapOmittedWhenNone() {
        let s = styleOf(VStack { text("x") })   // spacing default .none
        #expect(s["gap"] == nil)
    }

    @Test func preservesChildren() {
        let node = VStack { text("a"); text("b") }
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.children.count == 2)
        #expect(data.tag == "div")
    }

    @Test func callerAttributesOverrideDefaults() {
        // A caller-supplied style wins (last-write-wins in applyAttributes).
        let node = HStack(.style("display", "grid")) { text("x") }
        #expect(styleOf(node)["display"] == "grid")
    }

    @Test func callerClassAddsCleanly() {
        let node = VStack(.class("hero")) { text("x") }
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.attributes["class"] == "hero")   // nothing to clobber — stacks carry no class
        #expect(data.style["display"] == "flex")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StackTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'VStack' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/SwiflowUI/Stack.swift
import Swiflow

/// Vertical flex container. Lowers to a `<div>` with inline flex styles using
/// token vars for the spacing axis. Capitalized to distinguish SwiflowUI
/// primitives from lowercase raw HTML element factories (`div`).
@MainActor
public func VStack(
    spacing: Spacing   = .none,
    align:   CrossAlign = .stretch,
    justify: MainAlign  = .start,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    stack(direction: "column", spacing: spacing, align: align, justify: justify,
          attributes: attributes, children: children())
}

/// Horizontal flex container. See `VStack`.
@MainActor
public func HStack(
    spacing: Spacing   = .none,
    align:   CrossAlign = .stretch,
    justify: MainAlign  = .start,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    stack(direction: "row", spacing: spacing, align: align, justify: justify,
          attributes: attributes, children: children())
}

/// Shared lowering: ensure tokens are injected, build inline flex styles in a
/// deterministic order, then let caller `attributes` win (they come last, and
/// `applyAttributes` is last-write-wins).
@MainActor
private func stack(
    direction: String,
    spacing: Spacing,
    align: CrossAlign,
    justify: MainAlign,
    attributes: [Attribute],
    children: [VNode]
) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [
        .style("display", "flex"),
        .style("flex-direction", direction),
        .style("align-items", align.css),
        .style("justify-content", justify.css),
    ]
    if spacing != .none {
        styles.append(.style("gap", spacing.css))
    }
    return element("div", attributes: styles + attributes, children: children)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StackTests 2>&1 | tail -20`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Stack.swift Tests/SwiflowUITests/StackTests.swift
git commit -m "feat(swiflowui): VStack/HStack flex primitives (inline token vars)"
```

---

## Task 7: `Modifiers.swift` — `.padding` / `.gap`

**Files:**
- Create: `Sources/SwiflowUI/Modifiers.swift`
- Test: `Tests/SwiflowUITests/ModifierTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowUITests/ModifierTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Modifiers")
@MainActor
struct ModifierTests {
    @Test func paddingAppendsTokenVar() {
        let s = styleOf(VStack { text("x") }.padding(.lg))
        #expect(s["padding"] == "var(--sw-space-lg)")
        #expect(s["display"] == "flex")   // doesn't disturb existing styles
    }

    @Test func gapModifierOverridesConstructorGap() {
        let s = styleOf(VStack(spacing: .md) { text("x") }.gap(.sm))
        #expect(s["gap"] == "var(--sw-space-sm)")
    }

    @Test func customSpacingPassesThrough() {
        #expect(styleOf(HStack { text("x") }.padding(.custom("3px")))["padding"] == "3px")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModifierTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'VNode' has no member 'padding'`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/SwiflowUI/Modifiers.swift
import Swiflow

public extension VNode {
    /// Appends `padding` using a `--sw-space-*` token (or raw length). Thin
    /// wrapper over the core `VNode.style(_:_:)` postfix modifier; a no-op on
    /// non-element nodes (the existing diagnostic path).
    func padding(_ s: Spacing) -> VNode { style("padding", s.css) }

    /// Appends/overrides `gap` using a `--sw-space-*` token (or raw length).
    func gap(_ s: Spacing) -> VNode { style("gap", s.css) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModifierTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full SwiflowUI + Swiflow suites**

Run: `swift test --filter SwiflowUITests 2>&1 | tail -20 && swift test --filter SwiflowTests 2>&1 | tail -20`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/Modifiers.swift Tests/SwiflowUITests/ModifierTests.swift
git commit -m "feat(swiflowui): .padding/.gap chainable modifiers"
```

---

## Task 8: Browser proof — `examples/SwiflowUIDemo` + EmbeddedTemplates regen

A minimal example that renders stacks and a token reskin, proving the vars resolve in a real browser. Adding an `examples/` dir changes the codegen'd `EmbeddedTemplates.swift`, so it MUST be regenerated or `TemplateEmbedderTests` fails in CI (the TodoCRUD lesson).

**Files:**
- Create: `examples/SwiflowUIDemo/{Package.swift, index.html, swiflow-sw.js, swiflow-driver.js, .gitignore, README.md}`
- Create: `examples/SwiflowUIDemo/Sources/App/App.swift`
- Modify (regenerated): `Sources/SwiflowCLI/EmbeddedTemplates.swift`

- [ ] **Step 1: Scaffold from an existing example**

Copy these verbatim from `examples/HelloWorld/` into `examples/SwiflowUIDemo/`: `index.html` (change `<title>` to `SwiflowUI Demo`), `swiflow-sw.js`, `swiflow-driver.js`, `.gitignore`. (The driver file is force-committed per example — `swiflow dev`/`build` do not emit it; copy it or the page 404s and renders blank.)

- [ ] **Step 2: Write `examples/SwiflowUIDemo/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiflowUIDemo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "App", targets: ["App"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
```

- [ ] **Step 3: Write `examples/SwiflowUIDemo/Sources/App/App.swift`**

```swift
import Swiflow
import SwiflowWeb
import SwiflowUI

@MainActor @Component
final class Demo {
    var body: VNode {
        VStack(spacing: .lg, align: .stretch) {
            h1("SwiflowUI — Stacks")
            HStack(spacing: .md, align: .center) {
                button("One"); button("Two"); button("Three")
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")

            p("The row above uses HStack(spacing: .md). Change --sw-space-md "
              + "in index.html's <style> to reskin every gap at once.")
        }
        .padding(.xl)
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}
```

- [ ] **Step 4: Write `examples/SwiflowUIDemo/README.md`**

One-liner + what it shows (VStack/HStack, token-var gaps, `.padding`, reskin by overriding `--sw-space-md`); run steps (`swiflow dev --port 3003`); the reskin experiment; link to the spec.

- [ ] **Step 5: Regenerate `EmbeddedTemplates.swift`**

Run: `swift scripts/embed-templates.swift 2>&1 | tail -5`
Then verify the embedder test passes:
Run: `swift test --filter TemplateEmbedderTests 2>&1 | tail -20`
Expected: PASS (the regenerated `EmbeddedTemplates.swift` now includes `SwiflowUIDemo`).

- [ ] **Step 6: Build the example to WASM**

Run (from `examples/SwiflowUIDemo/`): the project's standard WASM build (e.g. `swiflow build` or the documented `swift package --swift-sdk wasm32-unknown-wasi js`). Confirm `App.wasm` is produced with no compile errors. Report the exact command used.

- [ ] **Step 7: Manual browser verification**

Run `swiflow dev --port 3003` from the example dir, open `http://localhost:3003`. The Chrome extension may not be connected — verify visually:
1. A vertical stack with a heading, a horizontal row of three buttons (evenly gapped), and a paragraph.
2. The button row has padding and a surface-colored, rounded background (tokens resolved).
3. Edit `index.html`'s `<style>` to add `:root { --sw-space-md: 2.5rem }` → reload → the row's gap visibly widens (proves inline `gap:var(--sw-space-md)` reskins via the cascade).

Stop the dev server when done (`pkill -f 'swiflow dev'`).

- [ ] **Step 8: Final full suite + commit**

Run: `swift test 2>&1 | tail -30`
Expected: all pass (modulo the known `OnChangeStorageTests` parallel flake — confirm in isolation).

```bash
git add examples/SwiflowUIDemo Sources/SwiflowCLI/EmbeddedTemplates.swift
git add -f examples/SwiflowUIDemo/swiflow-driver.js
git commit -m "feat(examples): SwiflowUIDemo — browser proof for SwiflowUI v0 + regen templates"
```

---

## Final review

After Task 8, dispatch a whole-feature code review (spec compliance + quality) per `superpowers:requesting-code-review`, then use `superpowers:finishing-a-development-branch`. Reviewers use **read-only git only**.

## Self-review notes (author)

- **Spec coverage:** token contract (T5) ✓; lazy-once injection + testable seam (T2/T5) ✓; CSSInjector DRY migration (T3) ✓; `element` factory enabler (T1, not in spec files list but required — spec §Architecture implied the array build) ✓; `VStack`/`HStack` inline lowering + gap-omit + caller-override (T6) ✓; `.padding`/`.gap` (T7) ✓; host lowering/theme/modifier tests (T4–T7) ✓; browser e2e (T8) ✓; files list matches (plus `ElementFactoryTests`, `StyleInjectionRegistryTests`, and the `element` factory, which the spec's prose required but didn't enumerate).
- **Type consistency:** `Spacing`/`CrossAlign`/`MainAlign` `.css`, `StyleInjectionRegistry.injectOnce(id:css:)`/`emit`/`reset`, `SwiflowUI.baseStyleSheet`/`installBaseStyles()`, `ensureBaseStyles()`, `element(_:attributes:children:)` — names identical across all tasks.
- **Deviation from spec files list:** added `Sources/Swiflow/DSL/Elements.swift` modification + `element` factory (Task 1) because `applyAttributes` is internal; the spec assumed an array build was possible. Documented here so it's not a surprise.
