# Swiflow Phase 12a — Styling & Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a CSS-in-Swift scoped styling system with enter/exit animations and a CSS variables bridge for Swiflow components.

**Architecture:** Pure-Swift `CSSSheet` model + three result builders live in `Sources/Swiflow/CSS/`; WASM-only `CSSInjector` (injects `<style>` tags into `<head>`) lives in `Sources/SwiflowWeb/CSS/`. The diff adds the scope class to every component's body root element at mount/update time via a small helper. Exit animations use a new `animateExit` Patch case that both drivers handle with a JS `setTimeout`.

**Tech Stack:** Swift 6, Swift Testing, JavaScriptKit (WASM side only), `swift scripts/embed-driver.swift` to sync JS→Swift after driver edits.

---

## File map

| File | Action | Purpose |
|---|---|---|
| `Sources/Swiflow/CSS/CSSSheet.swift` | **Create** | `CSSSheet`, `CSSEntry`, `KeyframeStop` model + `cssString(scopeClass:)` |
| `Sources/Swiflow/CSS/CSSBuilder.swift` | **Create** | Three `@resultBuilder`s + `css {}`, `rule()`, `keyframes()`, `from {}`, `to {}`, `at(_:) {}` free functions |
| `Sources/Swiflow/CSS/CSSProperties.swift` | **Create** | ~35 property functions + `property(_:_:)` escape hatch + `cssVar(_:_:)` |
| `Sources/Swiflow/CSS/CSSMountHook.swift` | **Create** | `onComponentTypeMount` hook (SwiflowWeb sets it; Diff.swift calls it) |
| `Sources/Swiflow/Reactivity/Component.swift` | **Modify** | Add `static var scopedStyles`, `exitAnimation`, `exitDuration` protocol requirements |
| `Sources/Swiflow/DSL/Modifiers.swift` | **Modify** | Add `Attribute.transition(_:)`, `.animation(_:)`, `.cssVar(_:_:)` |
| `Sources/Swiflow/DSL/VNodeModifiers.swift` | **Modify** | Add postfix `.transition(_:)`, `.animation(_:)`, `.cssVar(_:_:)` on VNode |
| `Sources/Swiflow/Patch.swift` | **Modify** | Add `animateExit(handle:parentHandle:animation:durationMs:)` |
| `Sources/Swiflow/PatchSerializer.swift` | **Modify** | Encode `animateExit` |
| `Sources/Swiflow/Diff/Diff.swift` | **Modify** | `addScopeClass()` helper; call it in mount+update; call mount hook; `destroy()` gets `skipDestroyForHandle` |
| `Sources/Swiflow/Diff/IndexedChildrenDiff.swift` | **Modify** | Check `exitAnimation` before emitting `removeChild` |
| `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` | **Modify** | Same as indexed |
| `Sources/SwiflowWeb/CSS/CSSInjector.swift` | **Create** | Injects `<style>` tags per component type; sets `onComponentTypeMount` hook |
| `Sources/SwiflowWeb/SwiflowWeb.swift` | **Modify** | Call `CSSInjector.setup()` on render init |
| `js-driver/swiflow-driver.js` | **Modify** | Handle `animateExit` op |
| `Sources/SwiflowCLI/EmbeddedDriver.swift` | **Regenerate** | Run `swift scripts/embed-driver.swift` |
| `Tests/SwiflowTests/CSS/CSSSheetTests.swift` | **Create** | 9 unit tests for serialization |
| `Tests/SwiflowTests/DiffTests/ExitAnimationTests.swift` | **Create** | 4 tests for exit animation patch emission |
| `examples/HelloWorld/Sources/App/App.swift` | **Modify** | Add `scopedStyles` + `Toast` with exit animation |
| `README.md` | **Modify** | Update status line |

---

## Task 1: CSSSheet data model, builders, and property functions

**Files:**
- Create: `Sources/Swiflow/CSS/CSSSheet.swift`
- Create: `Sources/Swiflow/CSS/CSSBuilder.swift`
- Create: `Sources/Swiflow/CSS/CSSProperties.swift`
- Create: `Tests/SwiflowTests/CSS/CSSSheetTests.swift`

- [ ] **Step 1: Create the test file first**

```swift
// Tests/SwiflowTests/CSS/CSSSheetTests.swift
import Testing
@testable import Swiflow

@Suite("CSSSheet — serialization")
struct CSSSheetTests {

    @Test("plain class selector is scoped")
    func plainClassScoped() {
        let sheet = css {
            rule(".root") {
                padding("1rem")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Card")
        #expect(result.contains(".swiflow-Card .root {"))
        #expect(result.contains("padding: 1rem;"))
    }

    @Test("pseudo-class is scoped")
    func pseudoClassScoped() {
        let sheet = css {
            rule(".title:hover") {
                color("#fff")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-Btn")
        #expect(result.contains(".swiflow-Btn .title:hover {"))
    }

    @Test(":root selector is NOT scoped")
    func rootNotScoped() {
        let sheet = css {
            rule(":root") {
                cssVar("--bg", "#fff")
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix(":root {"))
        #expect(!result.contains("swiflow-T"))
    }

    @Test("html selector is NOT scoped")
    func htmlNotScoped() {
        let sheet = css { rule("html") { property("box-sizing", "border-box") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix("html {"))
    }

    @Test("body selector is NOT scoped")
    func bodyNotScoped() {
        let sheet = css { rule("body") { margin("0") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.hasPrefix("body {"))
    }

    @Test("@keyframes are emitted globally (no scope prefix)")
    func keyframesGlobal() {
        let sheet = css {
            keyframes("slide-in") {
                from { opacity("0") }
                to   { opacity("1") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-X")
        #expect(result.hasPrefix("@keyframes slide-in {"))
        #expect(!result.contains("swiflow-X"))
    }

    @Test("cssVar() emits custom property declaration")
    func cssVarDeclaration() {
        let sheet = css { rule(":root") { cssVar("--radius", "8px") } }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        #expect(result.contains("--radius: 8px;"))
    }

    @Test("at() produces percent stop in keyframes")
    func atPercent() {
        let sheet = css {
            keyframes("pulse") {
                from  { opacity("1") }
                at(50) { opacity("0.5") }
                to    { opacity("1") }
            }
        }
        let result = sheet.cssString(scopeClass: "swiflow-X")
        #expect(result.contains("50% {"))
        #expect(result.contains("opacity: 0.5;"))
    }

    @Test("multiple rules serialized in declaration order")
    func multipleRulesOrdered() {
        let sheet = css {
            rule(".a") { color("#000") }
            rule(".b") { color("#fff") }
        }
        let result = sheet.cssString(scopeClass: "swiflow-T")
        let rangeA = result.range(of: ".a {")!
        let rangeB = result.range(of: ".b {")!
        #expect(rangeA.lowerBound < rangeB.lowerBound)
    }

    @Test("empty sheet produces empty string")
    func emptySheet() {
        let sheet = css {}
        #expect(sheet.cssString(scopeClass: "swiflow-T") == "")
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail (types undefined)**

```bash
swift test --filter CSSSheetTests 2>&1 | tail -20
```

Expected: compile error — `css`, `rule`, `keyframes`, etc. are not defined.

- [ ] **Step 3: Create `Sources/Swiflow/CSS/CSSSheet.swift`**

```swift
// Sources/Swiflow/CSS/CSSSheet.swift

/// A compiled CSS stylesheet for a single component scope.
/// Produced by the `css { }` builder and stored on a component type.
public struct CSSSheet: Sendable {
    package let entries: [CSSEntry]
    package init(entries: [CSSEntry]) { self.entries = entries }

    /// Serializes the sheet to a CSS string. Selectors not starting with
    /// `:root`, `html`, or `body` are prefixed with `".\(scopeClass) "`.
    /// `@keyframes` are always emitted globally (no prefix).
    public func cssString(scopeClass: String) -> String {
        entries.map { $0.cssString(scopeClass: scopeClass) }.joined(separator: "\n")
    }
}

package enum CSSEntry: Sendable {
    case rule(selector: String, declarations: [CSSDeclaration])
    case keyframes(name: String, stops: [KeyframeStop])

    package func cssString(scopeClass: String) -> String {
        switch self {
        case .rule(let selector, let declarations):
            let scopedSelector = shouldScope(selector)
                ? ".\(scopeClass) \(selector)"
                : selector
            let decls = declarations
                .map { "  \($0.name): \($0.value);" }
                .joined(separator: "\n")
            return "\(scopedSelector) {\n\(decls)\n}"
        case .keyframes(let name, let stops):
            let stopsStr = stops.map { stop in
                let decls = stop.declarations
                    .map { "    \($0.name): \($0.value);" }
                    .joined(separator: "\n")
                return "  \(stop.position) {\n\(decls)\n  }"
            }.joined(separator: "\n")
            return "@keyframes \(name) {\n\(stopsStr)\n}"
        }
    }

    private func shouldScope(_ selector: String) -> Bool {
        let lower = selector.lowercased()
        return !lower.hasPrefix(":root")
            && !lower.hasPrefix("html")
            && !lower.hasPrefix("body")
    }
}

package struct CSSDeclaration: Sendable {
    package let name: String
    package let value: String
    package init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

package struct KeyframeStop: Sendable {
    package let position: String   // "from", "to", or "50%"
    package let declarations: [CSSDeclaration]
    package init(position: String, declarations: [CSSDeclaration]) {
        self.position = position
        self.declarations = declarations
    }
}
```

- [ ] **Step 4: Create `Sources/Swiflow/CSS/CSSBuilder.swift`**

```swift
// Sources/Swiflow/CSS/CSSBuilder.swift

// MARK: - Sheet builder

@resultBuilder
public enum CSSSheetBuilder {
    public static func buildBlock(_ components: [CSSEntry]...) -> [CSSEntry] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ e: CSSEntry) -> [CSSEntry] { [e] }
    public static func buildOptional(_ e: [CSSEntry]?) -> [CSSEntry] { e ?? [] }
    public static func buildEither(first: [CSSEntry]) -> [CSSEntry] { first }
    public static func buildEither(second: [CSSEntry]) -> [CSSEntry] { second }
    public static func buildArray(_ components: [[CSSEntry]]) -> [CSSEntry] { components.flatMap { $0 } }
}

// MARK: - Rule/stop body builder

@resultBuilder
public enum CSSRuleBuilder {
    public static func buildBlock(_ components: [CSSDeclaration]...) -> [CSSDeclaration] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ d: CSSDeclaration) -> [CSSDeclaration] { [d] }
    public static func buildOptional(_ d: [CSSDeclaration]?) -> [CSSDeclaration] { d ?? [] }
    public static func buildEither(first: [CSSDeclaration]) -> [CSSDeclaration] { first }
    public static func buildEither(second: [CSSDeclaration]) -> [CSSDeclaration] { second }
    public static func buildArray(_ components: [[CSSDeclaration]]) -> [CSSDeclaration] { components.flatMap { $0 } }
}

// MARK: - Keyframe stops builder

@resultBuilder
public enum CSSKeyframeBuilder {
    public static func buildBlock(_ components: [KeyframeStop]...) -> [KeyframeStop] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ s: KeyframeStop) -> [KeyframeStop] { [s] }
}

// MARK: - Free functions

/// Produces a `CSSSheet` from a list of CSS entries.
public func css(@CSSSheetBuilder _ content: () -> [CSSEntry]) -> CSSSheet {
    CSSSheet(entries: content())
}

/// Produces a CSS rule entry (`.root`, `.title:hover`, `:root`, etc.).
public func rule(_ selector: String, @CSSRuleBuilder _ declarations: () -> [CSSDeclaration]) -> CSSEntry {
    .rule(selector: selector, declarations: declarations())
}

/// Produces a `@keyframes` entry.
public func keyframes(_ name: String, @CSSKeyframeBuilder _ stops: () -> [KeyframeStop]) -> CSSEntry {
    .keyframes(name: name, stops: stops())
}

/// Keyframe `from` stop.
public func from(@CSSRuleBuilder _ declarations: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "from", declarations: declarations())
}

/// Keyframe `to` stop.
public func to(@CSSRuleBuilder _ declarations: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "to", declarations: declarations())
}

/// Keyframe stop at a given percentage (e.g. `at(50) { … }` → `50% { … }`).
public func at(_ percent: Int, @CSSRuleBuilder _ declarations: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "\(percent)%", declarations: declarations())
}
```

- [ ] **Step 5: Create `Sources/Swiflow/CSS/CSSProperties.swift`**

```swift
// Sources/Swiflow/CSS/CSSProperties.swift
// Property functions — used inside rule { } and keyframe stop blocks.
// Each produces a CSSDeclaration consumed by CSSRuleBuilder.

// MARK: - Box model
public func padding(_ v: String)        -> CSSDeclaration { .init("padding", v) }
public func paddingTop(_ v: String)     -> CSSDeclaration { .init("padding-top", v) }
public func paddingBottom(_ v: String)  -> CSSDeclaration { .init("padding-bottom", v) }
public func paddingLeft(_ v: String)    -> CSSDeclaration { .init("padding-left", v) }
public func paddingRight(_ v: String)   -> CSSDeclaration { .init("padding-right", v) }
public func margin(_ v: String)         -> CSSDeclaration { .init("margin", v) }
public func marginTop(_ v: String)      -> CSSDeclaration { .init("margin-top", v) }
public func marginBottom(_ v: String)   -> CSSDeclaration { .init("margin-bottom", v) }
public func marginLeft(_ v: String)     -> CSSDeclaration { .init("margin-left", v) }
public func marginRight(_ v: String)    -> CSSDeclaration { .init("margin-right", v) }
public func width(_ v: String)          -> CSSDeclaration { .init("width", v) }
public func height(_ v: String)         -> CSSDeclaration { .init("height", v) }
public func maxWidth(_ v: String)       -> CSSDeclaration { .init("max-width", v) }
public func minHeight(_ v: String)      -> CSSDeclaration { .init("min-height", v) }
public func overflow(_ v: String)       -> CSSDeclaration { .init("overflow", v) }

// MARK: - Borders
public func border(_ v: String)         -> CSSDeclaration { .init("border", v) }
public func borderRadius(_ v: String)   -> CSSDeclaration { .init("border-radius", v) }
public func borderTop(_ v: String)      -> CSSDeclaration { .init("border-top", v) }
public func borderBottom(_ v: String)   -> CSSDeclaration { .init("border-bottom", v) }
public func borderLeft(_ v: String)     -> CSSDeclaration { .init("border-left", v) }
public func borderRight(_ v: String)    -> CSSDeclaration { .init("border-right", v) }
public func boxShadow(_ v: String)      -> CSSDeclaration { .init("box-shadow", v) }
public func outline(_ v: String)        -> CSSDeclaration { .init("outline", v) }

// MARK: - Color & background
public func color(_ v: String)              -> CSSDeclaration { .init("color", v) }
public func backgroundColor(_ v: String)    -> CSSDeclaration { .init("background-color", v) }
public func background(_ v: String)         -> CSSDeclaration { .init("background", v) }
public func opacity(_ v: String)            -> CSSDeclaration { .init("opacity", v) }

// MARK: - Typography
public func fontSize(_ v: String)       -> CSSDeclaration { .init("font-size", v) }
public func fontWeight(_ v: String)     -> CSSDeclaration { .init("font-weight", v) }
public func fontFamily(_ v: String)     -> CSSDeclaration { .init("font-family", v) }
public func lineHeight(_ v: String)     -> CSSDeclaration { .init("line-height", v) }
public func letterSpacing(_ v: String)  -> CSSDeclaration { .init("letter-spacing", v) }
public func textAlign(_ v: String)      -> CSSDeclaration { .init("text-align", v) }
public func textDecoration(_ v: String) -> CSSDeclaration { .init("text-decoration", v) }

// MARK: - Layout
public func display(_ v: String)        -> CSSDeclaration { .init("display", v) }
public func flexDirection(_ v: String)  -> CSSDeclaration { .init("flex-direction", v) }
public func alignItems(_ v: String)     -> CSSDeclaration { .init("align-items", v) }
public func justifyContent(_ v: String) -> CSSDeclaration { .init("justify-content", v) }
public func gap(_ v: String)            -> CSSDeclaration { .init("gap", v) }

// MARK: - Positioning
public func position(_ v: String)       -> CSSDeclaration { .init("position", v) }
public func top(_ v: String)            -> CSSDeclaration { .init("top", v) }
public func left(_ v: String)           -> CSSDeclaration { .init("left", v) }
public func right(_ v: String)          -> CSSDeclaration { .init("right", v) }
public func bottom(_ v: String)         -> CSSDeclaration { .init("bottom", v) }
public func zIndex(_ v: String)         -> CSSDeclaration { .init("z-index", v) }

// MARK: - Animation & transforms
public func transform(_ v: String)      -> CSSDeclaration { .init("transform", v) }
public func transition(_ v: String)     -> CSSDeclaration { .init("transition", v) }
public func animation(_ v: String)      -> CSSDeclaration { .init("animation", v) }
public func cursor(_ v: String)         -> CSSDeclaration { .init("cursor", v) }

// MARK: - CSS variables
/// Emits `--name: value` as a CSS custom property declaration.
public func cssVar(_ name: String, _ value: String) -> CSSDeclaration { .init(name, value) }

// MARK: - Escape hatch
/// Emits any CSS property not covered by the named functions above.
public func property(_ name: String, _ value: String) -> CSSDeclaration { .init(name, value) }
```

- [ ] **Step 6: Run the tests**

```bash
swift test --filter CSSSheetTests 2>&1 | tail -20
```

Expected: all 9 tests PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/CSS/ Tests/SwiflowTests/CSS/
git commit -m "feat(css): CSSSheet data model, builders, and property functions"
```

---

## Task 2: Component protocol extensions + attribute modifiers

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Component.swift`
- Modify: `Sources/Swiflow/DSL/Modifiers.swift`
- Modify: `Sources/Swiflow/DSL/VNodeModifiers.swift`

- [ ] **Step 1: Add `scopedStyles`, `exitAnimation`, `exitDuration` to `Component`**

In `Sources/Swiflow/Reactivity/Component.swift`, add after the existing `onDisappear()` requirement (around line 38):

```swift
    /// The component's scoped CSS stylesheet. Injected into `<head>` once on
    /// first mount. All selectors (except `:root`, `html`, `body`) are
    /// prefixed with a stable scope class derived from the component's type
    /// name (e.g. `.swiflow-Card`).
    static var scopedStyles: CSSSheet? { get }

    /// CSS animation shorthand applied to the component's root element just
    /// before removal. The diff defers DOM removal by `exitDuration` seconds,
    /// letting the animation play out. Example: `"fade-out 0.3s ease forwards"`.
    static var exitAnimation: String? { get }

    /// How long (in seconds) to wait before removing the DOM node after
    /// `exitAnimation` is applied. Defaults to `0` (remove after next frame).
    static var exitDuration: Double? { get }
```

Add defaults in the existing `public extension Component` block:

```swift
    public static var scopedStyles: CSSSheet? { nil }
    public static var exitAnimation: String? { nil }
    public static var exitDuration: Double? { nil }
```

- [ ] **Step 2: Run `swift build` to confirm the protocol changes compile**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` (no errors)

- [ ] **Step 3: Add `.transition()`, `.animation()`, `.cssVar()` to `Modifiers.swift`**

In `Sources/Swiflow/DSL/Modifiers.swift`, add before the closing `}` of `public enum Attribute`:

```swift
    /// Sets the `transition` inline style. Equivalent to `.style("transition", value)`.
    public static func transition(_ value: String) -> Attribute {
        .style(name: "transition", value: value)
    }

    /// Sets the `animation` inline style. Equivalent to `.style("animation", value)`.
    public static func animation(_ value: String) -> Attribute {
        .style(name: "animation", value: value)
    }

    /// Sets a CSS custom property as an inline style (`--name: value`).
    /// Re-evaluated on every render. Children read it via `var(--name)`.
    public static func cssVar(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }
```

- [ ] **Step 4: Add postfix variants to `VNodeModifiers.swift`**

In `Sources/Swiflow/DSL/VNodeModifiers.swift`, add to `public extension VNode`:

```swift
    /// Sets the `transition` inline style on this element.
    func transition(_ value: String) -> VNode {
        mergeAttribute(self) { $0.style["transition"] = value }
    }

    /// Sets the `animation` inline style on this element.
    func animation(_ value: String) -> VNode {
        mergeAttribute(self) { $0.style["animation"] = value }
    }

    /// Sets a CSS custom property as an inline style (`--name: value`).
    func cssVar(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.style[name] = value }
    }
```

- [ ] **Step 5: Run `swift build` and the full test suite**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
swift test 2>&1 | tail -5
```

Expected: build succeeds; all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Reactivity/Component.swift \
        Sources/Swiflow/DSL/Modifiers.swift \
        Sources/Swiflow/DSL/VNodeModifiers.swift
git commit -m "feat(css): Component CSS protocol hooks + .transition/.animation/.cssVar modifiers"
```

---

## Task 3: CSSInjector + scope class injection in the diff

**Files:**
- Create: `Sources/Swiflow/CSS/CSSMountHook.swift`
- Create: `Sources/SwiflowWeb/CSS/CSSInjector.swift`
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift`

- [ ] **Step 1: Create `Sources/Swiflow/CSS/CSSMountHook.swift`**

```swift
// Sources/Swiflow/CSS/CSSMountHook.swift

/// Called once per distinct component type when it first mounts.
/// `SwiflowWeb.CSSInjector` sets this to inject `<style>` tags.
/// Unset by default (non-WASM and test environments).
public nonisolated(unsafe) var onComponentTypeMount: ((any Component.Type) -> Void)?
```

- [ ] **Step 2: Create `Sources/SwiflowWeb/CSS/CSSInjector.swift`**

```swift
// Sources/SwiflowWeb/CSS/CSSInjector.swift
#if canImport(JavaScriptKit)
import JavaScriptKit

/// Injects per-component `<style>` tags into `<head>` on first mount.
/// One tag per component type, identified by `id="swiflow-<TypeName>"`.
/// Never re-injected on re-mount.
@MainActor
enum CSSInjector {
    private static var injected: Set<ObjectIdentifier> = []

    /// Wire up the `onComponentTypeMount` hook. Call once at renderer startup.
    static func setup() {
        onComponentTypeMount = { componentType in
            inject(for: componentType)
        }
    }

    static func inject(for componentType: any Component.Type) {
        let id = ObjectIdentifier(componentType)
        guard !injected.contains(id) else { return }
        guard let sheet = componentType.scopedStyles else {
            injected.insert(id)
            return
        }
        injected.insert(id)
        let typeName = String(describing: componentType)
        let scopeClass = "swiflow-\(typeName)"
        let css = sheet.cssString(scopeClass: scopeClass)
        guard !css.isEmpty else { return }

        let styleId = scopeClass
        // Skip if already in DOM (e.g. HMR re-init without full page reload).
        if JSObject.global.document.object!.getElementById!(styleId) != .undefined {
            return
        }
        let style = JSObject.global.document.object!.createElement!("style").object!
        style.id = .string(styleId)
        style.textContent = .string(css)
        _ = JSObject.global.document.object!.head.object!.appendChild!(style)
    }

    /// Clear injected state (used by HMR full-swap to force re-injection).
    static func reset() {
        injected = []
    }
}
#endif
```

- [ ] **Step 3: Call `CSSInjector.setup()` from `SwiflowWeb.swift`**

In `Sources/SwiflowWeb/SwiflowWeb.swift`, in the `static func render<C: Component>(...)` function, add `CSSInjector.setup()` immediately before the line `let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)` (currently around line 64):

```swift
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
```

`setup()` just assigns the closure — calling it multiple times is idempotent. `CSSInjector.injected` persists across calls correctly.

- [ ] **Step 4: Add scope class helper and mount hook call in `Diff.swift`**

In `Sources/Swiflow/Diff/Diff.swift`, add this package-internal helper anywhere before `mount()`:

```swift
/// Prepends `scopeClass` to the `class` attribute of `vnode`'s root element.
/// If `vnode` is not an `.element`, returns it unchanged.
@MainActor
func addScopeClass(_ vnode: VNode, scopeClass: String) -> VNode {
    guard case .element(var data) = vnode else { return vnode }
    if let existing = data.attributes["class"], !existing.isEmpty {
        data.attributes["class"] = "\(scopeClass) \(existing)"
    } else {
        data.attributes["class"] = scopeClass
    }
    return .element(data)
}
```

In `mount()`, in the `.component` case (currently around line 204), add these lines **after** `wireStateAndRestore(...)` and **before** calling `mount(bodyVNode, ...)`:

Find the block:
```swift
        let previousEnv = AmbientEnvironment.current
        AmbientEnvironment.current = environment
        let bodyVNode = instance.instance.body
        AmbientEnvironment.current = previousEnv
        let bodyMount = mount(
            bodyVNode,
```

Replace with:
```swift
        let componentType = type(of: instance.instance)
        onComponentTypeMount?(componentType)
        let previousEnv = AmbientEnvironment.current
        AmbientEnvironment.current = environment
        let bodyVNode = instance.instance.body
        AmbientEnvironment.current = previousEnv
        let scopeClass = "swiflow-\(String(describing: componentType))"
        let bodyMount = mount(
            addScopeClass(bodyVNode, scopeClass: scopeClass),
```

In `update()`, in the component same-typeID case (around line 363), add scope class injection. Find the block:

```swift
        let previousEnv = AmbientEnvironment.current
        AmbientEnvironment.current = environment
        let newBodyVNode = instance.instance.body
        AmbientEnvironment.current = previousEnv
        // Reconcile the new body VNode against the previously-mounted body
        // subtree. The returned MountNode may be the same reference (if the
        // body root type/tag matched) or a fresh one (if the body root
        // itself was replaced wholesale). Either way it becomes the new body.
        let newBodyMount = update(
            mounted: oldBody,
            next: newBodyVNode,
```

Replace with:
```swift
        let componentType = type(of: instance.instance)
        let previousEnv = AmbientEnvironment.current
        AmbientEnvironment.current = environment
        let newBodyVNode = instance.instance.body
        AmbientEnvironment.current = previousEnv
        // Reconcile the new body VNode against the previously-mounted body
        // subtree. The returned MountNode may be the same reference (if the
        // body root type/tag matched) or a fresh one (if the body root
        // itself was replaced wholesale). Either way it becomes the new body.
        let newBodyMount = update(
            mounted: oldBody,
            next: addScopeClass(newBodyVNode, scopeClass: "swiflow-\(String(describing: componentType))"),
```

- [ ] **Step 5: Run `swift build` and full test suite**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
swift test 2>&1 | tail -5
```

Expected: build succeeds; all existing tests pass. The scope class is now injected on every component mount and re-render.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/CSS/CSSMountHook.swift \
        Sources/SwiflowWeb/CSS/CSSInjector.swift \
        Sources/SwiflowWeb/SwiflowWeb.swift \
        Sources/Swiflow/Diff/Diff.swift
git commit -m "feat(css): CSSInjector + scope class injection in mount/update"
```

---

## Task 4: Exit animation — Patch, drivers, and diff changes

**Files:**
- Modify: `Sources/Swiflow/Patch.swift`
- Modify: `Sources/Swiflow/PatchSerializer.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Modify: `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`
- Modify: `js-driver/swiflow-driver.js`
- Regenerate: `Sources/SwiflowCLI/EmbeddedDriver.swift`
- Create: `Tests/SwiflowTests/DiffTests/ExitAnimationTests.swift`

- [ ] **Step 1: Write the failing tests first**

```swift
// Tests/SwiflowTests/DiffTests/ExitAnimationTests.swift
import Testing
@testable import Swiflow

// A component that declares an exit animation.
@MainActor
private final class Toaster: Component {
    static var exitAnimation: String? = "fade-out 0.3s ease forwards"
    static var exitDuration: Double? = 0.3
    var body: VNode { div(.class("toast")) {} }
}

// A component with no exit animation.
@MainActor
private final class Plain: Component {
    var body: VNode { div {} }
}

@Suite("Diff — exit animation")
@MainActor
struct ExitAnimationTests {

    @Test("removing a component with exitAnimation emits animateExit instead of removeChild+destroyNode for the root")
    func exitAnimationPatches() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        // Mount two Toasters.
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        // Update to one Toaster — second should exit-animate.
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let hasAnimateExit = result.patches.contains {
            if case .animateExit(_, _, let anim, _) = $0 {
                return anim == "fade-out 0.3s ease forwards"
            }
            return false
        }
        #expect(hasAnimateExit)
    }

    @Test("removing a component with exitAnimation does NOT emit removeChild for the exiting handle")
    func noRemoveChildForExiting() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let toasterDomHandle = result.newMountTree.children.first!.domHandle
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let hasRemoveChildForToaster = result.patches.contains {
            if case .removeChild(_, let child) = $0 { return child == toasterDomHandle }
            return false
        }
        #expect(!hasRemoveChildForToaster)
    }

    @Test("removing a component WITHOUT exitAnimation still emits removeChild+destroyNode")
    func plainComponentRemovesNormally() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Plain.self, factory: { Plain() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let plainDomHandle = result.newMountTree.children.first!.domHandle
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let hasRemoveChild = result.patches.contains {
            if case .removeChild(_, let child) = $0 { return child == plainDomHandle }
            return false
        }
        #expect(hasRemoveChild)
    }

    @Test("animateExit durationMs matches exitDuration * 1000")
    func durationMs() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let animPatch = result.patches.first {
            if case .animateExit = $0 { return true }
            return false
        }
        guard case .animateExit(_, _, _, let ms) = animPatch else {
            Issue.record("expected animateExit patch")
            return
        }
        #expect(ms == 300.0)
    }
}
```

- [ ] **Step 2: Run tests to confirm compile failure**

```bash
swift test --filter ExitAnimationTests 2>&1 | tail -10
```

Expected: compile error — `animateExit` not defined on `Patch`.

- [ ] **Step 3: Add `animateExit` to `Patch.swift`**

In `Sources/Swiflow/Patch.swift`, add after `case destroyNode`:

```swift
    /// Plays `animation` on `handle`'s element, then after `durationMs`
    /// milliseconds removes it from `parentHandle` and drops it from the
    /// driver's node map. Emitted instead of `removeChild`+`destroyNode`
    /// for components that declare `exitAnimation`.
    case animateExit(handle: Int, parentHandle: Int, animation: String, durationMs: Double)
```

- [ ] **Step 4: Encode `animateExit` in `PatchSerializer.swift`**

In `Sources/Swiflow/PatchSerializer.swift`, add a case in `encode(_:)` after the `destroyNode` case:

```swift
        case .animateExit(let handle, let parentHandle, let animation, let durationMs):
            return PatchPayload(op: "animateExit", fields: [
                "handle":       .int(handle),
                "parentHandle": .int(parentHandle),
                "animation":    .string(animation),
                "durationMs":   .double(durationMs),
            ])
```

Note: `PatchPayload.Field` in `Sources/Swiflow/PatchPayload.swift` currently only has `.int`, `.string`, `.property`. Add a `.double` case to `Field` and handle it in the WASM-side `toJSValue()` (or equivalent) call. In `SwiflowWeb`'s patch application code, `.double` should map to `JSValue.number(Double(value))`. Add to `PatchPayload.Field`:
```swift
case double(Double)
```

- [ ] **Step 5: Add `skipDestroyForHandle` to `destroy()` in `Diff.swift`**

Find the `destroy()` function signature:
```swift
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry
) {
```

Replace with:
```swift
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry,
    skipDestroyForHandle: Int? = nil
) {
```

Find the final `patches.append(.destroyNode(handle: node.handle))` line and replace with:

```swift
            if node.handle != skipDestroyForHandle {
                patches.append(.destroyNode(handle: node.handle))
            }
```

- [ ] **Step 6: Emit `animateExit` in `IndexedChildrenDiff.swift`**

In `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`, find the surplus-removal loop at the bottom (lines ~91-95):

```swift
        let removed = mounted.children[newCount]
        patches.append(.removeChild(parent: mounted.handle, child: removed.domHandle))
        destroy(removed, into: &patches, handlers: handlers)
        mounted.removeChild(at: newCount)
```

Replace with:

```swift
        let removed = mounted.children[newCount]
        if let comp = removed.component,
           let anim = type(of: comp.instance).exitAnimation {
            let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
            patches.append(.animateExit(
                handle: removed.domHandle,
                parentHandle: mounted.handle,
                animation: anim,
                durationMs: durMs
            ))
            destroy(removed, into: &patches, handlers: handlers,
                    skipDestroyForHandle: removed.domHandle)
        } else {
            patches.append(.removeChild(parent: mounted.handle, child: removed.domHandle))
            destroy(removed, into: &patches, handlers: handlers)
        }
        mounted.removeChild(at: newCount)
```

- [ ] **Step 7: Emit `animateExit` in `KeyedChildrenDiff.swift`**

In `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`, find every call site that does `.removeChild` + `destroy(...)` for a keyed surplus child. The pattern appears when a keyed child is in the bucket at the end and gets destroyed. Search for `destroy(` and the adjacent `removeChild` pattern.

Find the block (likely near end of the function) that removes orphaned keyed children:

```swift
for (_, old) in bucket {
    patches.append(.removeChild(parent: mounted.handle, child: old.domHandle))
    destroy(old, into: &patches, handlers: handlers)
    mounted.removeChild(...)  // or similar
}
```

Replace each `removeChild` + `destroy` pair with the same animateExit check pattern as Step 6:

```swift
for (_, old) in bucket {
    if let comp = old.component,
       let anim = type(of: comp.instance).exitAnimation {
        let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
        patches.append(.animateExit(
            handle: old.domHandle,
            parentHandle: mounted.handle,
            animation: anim,
            durationMs: durMs
        ))
        destroy(old, into: &patches, handlers: handlers,
                skipDestroyForHandle: old.domHandle)
    } else {
        patches.append(.removeChild(parent: mounted.handle, child: old.domHandle))
        destroy(old, into: &patches, handlers: handlers)
    }
}
```

Also apply the same pattern to any keyed cross-kind replacement in `KeyedChildrenDiff.swift` where a keyed old child is destroyed because its type changed (look for the old-type-mismatch removeChild + destroy pattern).

- [ ] **Step 8: Handle `animateExit` in `js-driver/swiflow-driver.js`**

In `js-driver/swiflow-driver.js`, inside the `applyOne(p)` function, add a case after `"destroyNode"`:

```javascript
      case "animateExit": {
        const node = nodes.get(p.handle);
        const parent = nodes.get(p.parentHandle);
        if (!node) return;
        node.style.animation = p.animation;
        setTimeout(function () {
          if (parent && node.parentNode === parent) {
            parent.removeChild(node);
          } else if (node.parentNode) {
            node.parentNode.removeChild(node);
          }
          nodes.delete(p.handle);
        }, p.durationMs);
        return;
      }
```

- [ ] **Step 9: Regenerate `EmbeddedDriver.swift`**

```bash
swift scripts/embed-driver.swift
```

Verify the output contains the new `animateExit` case:
```bash
grep -c "animateExit" Sources/SwiflowCLI/EmbeddedDriver.swift
```

Expected: output is `1` (or more).

- [ ] **Step 10: Run the exit animation tests**

```bash
swift test --filter ExitAnimationTests 2>&1 | tail -10
```

Expected: all 4 tests PASS.

- [ ] **Step 11: Run the full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: all tests pass, no regressions.

- [ ] **Step 12: Commit**

```bash
git add Sources/Swiflow/Patch.swift \
        Sources/Swiflow/PatchSerializer.swift \
        Sources/Swiflow/Diff/Diff.swift \
        Sources/Swiflow/Diff/IndexedChildrenDiff.swift \
        Sources/Swiflow/Diff/KeyedChildrenDiff.swift \
        Tests/SwiflowTests/DiffTests/ExitAnimationTests.swift \
        js-driver/swiflow-driver.js \
        Sources/SwiflowCLI/EmbeddedDriver.swift
git commit -m "feat(css): animateExit patch + exit animation in indexed/keyed diff"
```

---

## Task 5: HelloWorld example update + README

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `README.md`

- [ ] **Step 1: Update `Counter` to use `scopedStyles`, add `Toast` component**

Replace the entire `examples/HelloWorld/Sources/App/App.swift` with:

```swift
// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

final class Counter: Component {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showToast: Bool = false
    let greetingInput = Ref<JSObject>()

    static var scopedStyles: CSSSheet? = css {
        keyframes("counter-in") {
            from { opacity("0"); transform("translateY(-6px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        rule(".container") {
            maxWidth("480px")
            margin("2rem auto")
            padding("2rem")
            fontFamily("-apple-system, BlinkMacSystemFont, sans-serif")
            animation("counter-in 0.3s ease forwards")
        }
        rule(".count") {
            fontSize("1.5rem")
            fontWeight("600")
            color("#1a202c")
        }
        rule(".greeting-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            marginTop("1rem")
        }
        rule(".checkbox-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            marginTop("0.75rem")
            cursor("pointer")
        }
    }

    var body: VNode {
        div(.class("container")) {
            h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")")
            p(.class("count"), "Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
            button("Show toast", .on(.click) { self.showToast = true })

            div(.class("greeting-row")) {
                label("Greeting", .attr("for", "g"))
                input(.id("g"), .value($greeting), .ref(greetingInput))
            }

            label(.class("checkbox-row")) {
                input(.attr("type", "checkbox"), .checked($celebrate))
                VNode.text(" Celebrate")
            }

            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }
        }
    }

    func onAppear() {
        _ = greetingInput.wrappedValue?.focus.function?()
    }
}

final class Toast: Component {
    let message: String
    let onDone: () -> Void

    init(message: String, onDone: @escaping () -> Void) {
        self.message = message
        self.onDone = onDone
    }

    static var scopedStyles: CSSSheet? = css {
        keyframes("toast-in") {
            from { opacity("0"); transform("translateY(8px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        keyframes("toast-out") {
            to { opacity("0"); transform("translateY(8px)") }
        }
        rule(".root") {
            backgroundColor("#323232")
            color("#fff")
            padding("0.75rem 1.25rem")
            borderRadius("8px")
            marginTop("1rem")
            animation("toast-in 0.2s ease forwards")
            cursor("pointer")
        }
    }

    static var exitAnimation: String? = "toast-out 0.25s ease forwards"
    static var exitDuration: Double?  = 0.25

    var body: VNode {
        div(.class("root"), .on(.click) { self.onDone() }) {
            VNode.text(message)
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}
```

- [ ] **Step 2: Update README.md status line**

Find the current status line in `README.md` (look for `Phase` near the top). Change it to:

```
**Status:** Phase 12a (Styling & Animation) — CSS-in-Swift scoped styles, keyframe animations, enter/exit transitions, CSS variables bridge.
```

- [ ] **Step 3: Verify the example builds**

```bash
cd examples/HelloWorld && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Run the full test suite one final time**

```bash
cd ../.. && swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add examples/HelloWorld/Sources/App/App.swift README.md
git commit -m "feat(example): Counter + Toast demo for Phase 12a styling/animation"
```

---

## Notes for the implementer

**`PatchPayload.double` value:** If `PatchPayload` doesn't yet have a `.double` case, look at `Sources/Swiflow/PatchPayload.swift`. Add `case double(Double)` to `PatchValue` and serialize it as a number in `PatchPayload`'s encoding logic. The JS driver always receives it as a JS number (`p.durationMs`), so no string parsing is needed on the JS side.

**`KeyedChildrenDiff.swift` destroy call sites:** This file is 418 lines. Search for all `destroy(` calls and `removeChild` patches that are paired — there may be more than one location (cross-kind replacement, end-of-diff surplus cleanup). Apply the animateExit check to all of them.

**Access to `ComponentDescription` in tests:** Use `ComponentDescription(MyType.self, factory: { MyType() })` — the `public init<C: Component>(_ type:key:factory:)` overload in `Component.swift:95`. Do not use the `package init(typeID:key:factory:)` overload directly; it's package-scoped and the test target accesses it only via `@testable import`.

**`swift build` from repo root, not `examples/`:** The Swift package for tests is at the root. Always run `swift build` and `swift test` from `./`, not from inside `examples/`.

**Cross-module access:** `CSSSheet`, `CSSEntry`, `CSSDeclaration`, `KeyframeStop` are `package` for cross-module sharing within the Swiflow package. `CSSInjector` is `internal` to `SwiflowWeb`. `onComponentTypeMount` is `public` so `SwiflowWeb` can set it from the `Swiflow` module.

**SourceKit diagnostics are stale:** If the IDE shows "Cannot find type X in scope", verify with `swift build` before acting. SourceKit frequently lags behind disk state. See `feedback_sourcekit_diagnostics_are_stale.md`.

**EmbeddedDriver sync:** After every edit to `js-driver/swiflow-driver.js`, run `swift scripts/embed-driver.swift` from the repo root. Do not edit `Sources/SwiflowCLI/EmbeddedDriver.swift` directly.
