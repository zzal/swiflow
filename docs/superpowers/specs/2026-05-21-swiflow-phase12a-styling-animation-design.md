# Swiflow Phase 12a — Styling & Animation Design

## Goal

Ship a CSS-in-Swift scoped styling system with enter/exit animations and a CSS variables bridge, so components can own their visual presentation without leaving Swift or adding a build step.

---

## Section 1 — Architecture

### New files

| File | Responsibility |
|---|---|
| `Sources/Swiflow/CSS/CSSSheet.swift` | Data model: `CSSSheet`, `CSSEntry`, `KeyframeStop`, serialization |
| `Sources/Swiflow/CSS/CSSBuilder.swift` | Three `@resultBuilder`s + free functions: `css {}`, `rule()`, `keyframes()`, `from {}`, `to {}`, `at(_:) {}` |
| `Sources/Swiflow/CSS/CSSProperties.swift` | ~35 camelCase property functions + `property(_:_:)` escape hatch + `cssVar(_:_:)` |
| `Sources/SwiflowWeb/CSS/CSSInjector.swift` | WASM-only; manages `<style>` tags in `<head>`, tracks injected types |

### Modified files

| File | Change |
|---|---|
| `Sources/Swiflow/Reactivity/Component.swift` | Add `static var scopedStyles: CSSSheet?`, `static var exitAnimation: String?`, `static var exitDuration: Double?` |
| `Sources/SwiflowWeb/Renderer.swift` | Inject styles on first mount; add scope class to component root element; handle deferred exit removal |
| `Sources/Swiflow/DSL/Modifiers.swift` | Add `Attribute.transition(_:)`, `.animation(_:)`, `.cssVar(_:_:)` |
| `Sources/Swiflow/DSL/VNodeModifiers.swift` | Same modifiers in postfix shape |

### Module boundary

`CSSSheet`, the builders, and the property functions live in `Sources/Swiflow` — no JavaScriptKit dependency. `CSSInjector` and the renderer integration live in `Sources/SwiflowWeb` (WASM-only).

---

## Section 2 — CSS Builder API

### `css { }` produces a `CSSSheet`

```swift
final class Card: Component {

  static var scopedStyles: CSSSheet? = css {

    rule(".root") {
      padding("1.5rem")
      border("1px solid #e2e8f0")
      borderRadius("12px")
      backgroundColor("#fff")
    }

    rule(".title") {
      fontSize("1.25rem")
      fontWeight("600")
    }

    rule(".title:hover") {
      color("#4a90e2")
    }
  }

  var body: VNode {
    div(.class("root")) {
      h2(.class("title")) { ... }
    }
  }
}
```

`.root` → `.swiflow-Card .root` in the injected `<style>`.

### `@keyframes` with `from`, `to`, `at(_:)`

```swift
static var scopedStyles: CSSSheet? = css {

  keyframes("slide-in") {
    from {
      opacity("0")
      transform("translateY(-8px)")
    }
    to {
      opacity("1")
      transform("translateY(0)")
    }
  }

  keyframes("pulse") {
    from  { opacity("1") }
    at(50) { opacity("0.4") }   // 50% stop
    to    { opacity("1") }
  }

  rule(".root") {
    animation("slide-in 0.25s ease forwards")
  }
}
```

`@keyframes` are emitted globally (no scope prefix). Enter animation fires once on mount — element wasn't in DOM before, so CSS animation triggers automatically.

### Exit animation

```swift
final class Toast: Component {

  static var scopedStyles: CSSSheet? = css {
    keyframes("fade-out") {
      to { opacity("0") }
    }
    rule(".root") {
      borderRadius("8px")
      padding("0.75rem 1rem")
    }
  }

  static var exitAnimation: String? = "fade-out 0.3s ease forwards"
  static var exitDuration: Double?  = 0.3   // seconds to defer DOM removal

  var body: VNode { ... }
}
```

The diff applies `element.style.animation = exitAnimation` inline, then `setTimeout(remove, exitDuration * 1000)`. No extra class or selector magic.

### CSS variables bridge

```swift
final class ThemeRoot: Component {
  @State var isDark = false

  static var scopedStyles: CSSSheet? = css {
    rule(":root") {              // :root is NOT scoped — sets global CSS vars
      cssVar("--radius", "8px")
    }
  }

  var body: VNode {
    div(
      .cssVar("--bg", isDark ? "#1a1a2e" : "#ffffff"),
      .cssVar("--fg", isDark ? "#e0e0e0" : "#1a202c"),
      .transition("background 0.2s, color 0.2s")
    ) {
      button(.on(.click) { self.isDark.toggle() }) { ... }
    }
  }
}
```

`.cssVar()` injects `--name: value` as an inline style — re-evaluated on every render. Children read via `var(--bg)` in their own CSS rules.

---

## Section 3 — Component Integration

### Scope class derivation

```swift
"swiflow-\(String(describing: type(of: self)))"
```

For `final class Card`, scope class = `"swiflow-Card"`. Stable across renders.

### Style injection lifecycle

1. On first mount of any component type `T`:
   - If `T.scopedStyles != nil` and `ObjectIdentifier(T)` not in `CSSInjector.injected`:
     - Serialize `scopedStyles.cssString(scopeClass: "swiflow-Card")`
     - Append `<style id="swiflow-Card">…</style>` to `<head>`
     - Mark `ObjectIdentifier(T)` as injected
2. Never re-injected on subsequent renders or re-mounts.

### Root element scoping

The renderer automatically adds the scope class to the root DOM element produced by `body`. The user writes `.class("root")` on their div; the renderer adds `"swiflow-Card"` alongside it. No user-side markup required.

### Selectors that are NOT scoped

- `:root`, `html`, `body` — emitted verbatim (global context).
- `@keyframes` — always global.

Everything else is prefixed: `.root` → `.swiflow-Card .root`.

### Exit animation flow

When the diff is about to remove a component node whose type has `exitAnimation != nil`:

1. Apply `element.style.animation = T.exitAnimation!` inline.
2. Call `setTimeout(remove, (T.exitDuration ?? 0) * 1000)`.
3. Return without removing the node immediately.

When `exitDuration` is nil, the delay is 0 ms — the node is removed after the current animation frame (safe fallback).

---

## Section 4 — Attribute Modifiers

Two new modifiers usable on any element:

```swift
div(.transition("background 0.2s, color 0.2s")) { ... }
div(.animation("spin 1s linear infinite")) { ... }
```

Both map to inline `style="transition: …"` / `style="animation: …"`, re-evaluated on every render. They compose with `.style()` and other modifiers.

**No typed shorthand in Phase 12a.** String values keep scope tight; the escape hatch exists for any property.

**Interaction:** if `.animation()` is set as an attribute modifier AND `scopedStyles` has `animation(...)` on `.root`, the inline style wins (specificity). These are independent knobs.

---

## Section 5 — CSS Variables Bridge

### Static side (in `scopedStyles`)

`cssVar("--name", "value")` inside a `rule()` block emits `--name: value` as a CSS property:

```swift
rule(":root") {
  cssVar("--radius", "8px")
  cssVar("--primary", "#4a90e2")
}
```

### Dynamic side (attribute modifier)

`.cssVar("--name", value)` sets `--name` as an inline style on the element — re-evaluated every render. Children anywhere in the subtree read it with `var(--name)` in their own `scopedStyles` rules.

```swift
div(.cssVar("--bg", isDark ? "#1a1a2e" : "#ffffff")) { ... }
```

No subscription, no extra API surface — just CSS cascade.

---

## Section 6 — Data Model

### `CSSSheet`

```swift
public struct CSSSheet {
  let entries: [CSSEntry]
  public func cssString(scopeClass: String) -> String
}
```

### `CSSEntry`

```swift
enum CSSEntry {
  case rule(selector: String, declarations: [(name: String, value: String)])
  case keyframes(name: String, stops: [KeyframeStop])
}
```

### `KeyframeStop`

```swift
struct KeyframeStop {
  let position: String   // "from", "to", or "50%"
  let declarations: [(name: String, value: String)]
}
```

### Serialization rules

- Rule selector starts with `:root`, `html`, or `body` → emit verbatim.
- `@keyframes` → emit globally (no prefix).
- Everything else → prefix selector with `".\(scopeClass) "`.
- `cssVar("--x", "y")` → declaration `"--x: y"`.

---

## Section 7 — CSS Property Functions

Implemented in `CSSProperties.swift` as free functions inside the `CSSRuleBuilder` context. Initial set (~35):

`backgroundColor`, `color`, `border`, `borderRadius`, `borderTop`, `borderBottom`, `borderLeft`, `borderRight`, `padding`, `paddingTop`, `paddingBottom`, `paddingLeft`, `paddingRight`, `margin`, `marginTop`, `marginBottom`, `marginLeft`, `marginRight`, `fontSize`, `fontWeight`, `fontFamily`, `lineHeight`, `letterSpacing`, `textAlign`, `textDecoration`, `display`, `flexDirection`, `alignItems`, `justifyContent`, `gap`, `width`, `height`, `maxWidth`, `minHeight`, `overflow`, `opacity`, `transform`, `transition`, `animation`, `boxShadow`, `cursor`, `position`, `top`, `left`, `right`, `bottom`, `zIndex`.

Plus:
- `property(_ name: String, _ value: String)` — escape hatch for any property.
- `cssVar(_ name: String, _ value: String)` — emits `--name: value`.

---

## Section 8 — Testing Strategy

### Unit tests (`Tests/SwiflowTests/CSS/`)

- `CSSSheetTests.swift`:
  - `rule(".root")` → `.swiflow-Card .root { … }`
  - `rule(".title:hover")` → `.swiflow-Card .title:hover { … }`
  - `rule(":root")` → `:root { … }` (not scoped)
  - `rule("html")` → `html { … }` (not scoped)
  - `@keyframes "slide-in"` → emitted globally
  - `cssVar("--x", "y")` → `--x: y` in declarations
  - `at(50)` → `50% { … }` in keyframes
  - Multiple rules serialized in order
  - Empty sheet → empty string

### Integration

- `examples/HelloWorld` Counter gains a `scopedStyles` block:
  - Background, border-radius, transition on the button
  - Enter animation (`slide-in`) on the counter root
- A `Toast`-style component added to HelloWorld:
  - Mounts, stays 2 seconds, then fades out via `exitAnimation`
- Visual smoke-test: `swiflow build` + open in browser; inspect `<head>` for injected `<style>` tags

---

## Open questions (resolved)

| Question | Decision |
|---|---|
| Scoped CSS approach | CSS-in-Swift builder (Option B) — no build step, co-located with Swift |
| Animation scope | Full: CSS transitions + enter/exit animations + keyframes |
| CSS variables bridge | Included in Phase 12a (minimal modifiers, high leverage) |
| Typed vs string property values | String values for Phase 12a — YAGNI; typed shorthand deferred |
| Module placement | Pure-Swift model in `Swiflow`; WASM injection in `SwiflowWeb` |
