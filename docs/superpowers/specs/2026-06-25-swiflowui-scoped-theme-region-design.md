# SwiflowUI Scoped Theme Region Design

> **Date:** 2026-06-25 · **Status:** approved, ready for implementation plan
> **Milestone:** SwiflowUI **M8 (1.1) — Token correctness & generation**, part 3 of 3 (closes
> M8: contrast tokens PR #66, palette generator PR #67, this).
> **Origin:** the [Reshaped evaluation](../../future-work/swiflowui-reshaped-evaluation.md)
> steal-list #4 (scoped theming via a `Theme` fragment).

## Problem

Apps can already scope a token override to a subtree today — `section(.style("--sw-accent",
"#7c3aed")) { … }` — and because the accent family now derives from `--sw-accent` (P1, PR #67),
that single call already re-skins the subtree's buttons, ghost buttons, badges, and focus rings.
What's missing is **ergonomics for the multi-token case**: branding a region usually means
overriding several tokens at once (accent + radius + a spacing tweak), and `.style()` is
single-property and stringly-typed (`.style("--sw-accent", v).style("--sw-radius", v)…`). There
is no discoverable, typed way to theme a region, and a hand-rolled wrapper `<div>` carrying the
overrides would inject a block-level box that can break a flex/grid layout.

## Goal

A small, ergonomic **`Theme` container** that applies a set of `--sw-*` overrides to its subtree
in one typed, discoverable call, with **zero layout impact** and **no runtime color math** (the
build-time generator owns derivation; this just re-points explicit token values).

## Non-goals

- **No runtime seed→palette derivation.** `Theme(.accent("#7c3aed"))` re-points exactly that
  token (the family then cascades via P1). Deriving a full validated palette from a seed is the
  build-time `swiflow theme` CLI's job — putting OKLab math in the wasm is explicitly out.
- **No new CSS stylesheet / `installControlSheet`.** `Theme` emits inline custom properties only.
- **No caller `Attribute...` passthrough on `Theme` for v1.** It's a styling-only wrapper; an app
  needing an `id`/class on a real box wraps its own element.
- **No bloated typed token set.** A small brand-relevant set of typed statics; everything else via
  the `.token(_:_:)` escape hatch.

## API

A free function matching SwiflowUI's container convention (`Card`/`Grid`/`Stack`: free function,
`@ChildrenBuilder`, returns an `element("div", …)`):

```swift
@MainActor
public func Theme(
    _ tokens: ThemeToken...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode
```

Usage:

```swift
Theme(.accent("#7c3aed"), .radius("12px")) {
    Card { Button("Branded") { … } }       // accent family + radius re-skinned, here only
}

Theme(.accent("var(--brand-teal)"), .token("--sw-space-md", "1rem")) { … }
```

`ThemeToken` is a small value type with typed statics for the commonly-branded tokens plus a
general escape hatch:

```swift
public struct ThemeToken: Equatable, Sendable {
    public let name: String     // e.g. "--sw-accent"
    public let value: String

    public static func accent(_ v: String)  -> ThemeToken { .init(name: "--sw-accent",  value: v) }
    public static func radius(_ v: String)  -> ThemeToken { .init(name: "--sw-radius",  value: v) }
    public static func surface(_ v: String) -> ThemeToken { .init(name: "--sw-surface", value: v) }
    public static func text(_ v: String)    -> ThemeToken { .init(name: "--sw-text",    value: v) }
    public static func border(_ v: String)  -> ThemeToken { .init(name: "--sw-border",  value: v) }
    public static func danger(_ v: String)  -> ThemeToken { .init(name: "--sw-danger",  value: v) }
    public static func success(_ v: String) -> ThemeToken { .init(name: "--sw-success", value: v) }

    /// Escape hatch for any other token (spacing scale, motion, overlay, custom).
    public static func token(_ name: String, _ value: String) -> ThemeToken { .init(name: name, value: value) }
}
```

## Rendering — `display: contents` (the key choice)

`Theme` renders a wrapper `<div>` carrying the overrides as inline `.style()` attributes **plus
`display: contents`**:

```html
<div style="display: contents; --sw-accent: #7c3aed; --sw-radius: 12px"> … children … </div>
```

`display: contents` removes the wrapper's own box — its children participate directly in the
parent's flex/grid layout — while the element remains in the DOM tree, so its custom properties
**still inherit** to descendants (custom-property inheritance follows the DOM tree, not the box
tree). The net effect is scoped token theming with **zero layout impact**: no stray block-level
div breaking a flex row. Nesting works via the cascade — an inner `Theme` overrides an outer one
for its subtree. `display: contents` is Baseline.

Implementation builds the attribute list from the existing `.style(_:_:)` Attribute (which the
framework merges into one `style` string), so no new CSS machinery is introduced:

```swift
let styleAttrs: [Attribute] = [.style("display", "contents")] + tokens.map { .style($0.name, $0.value) }
return element("div", attributes: styleAttrs, children: children())
```

`Theme` calls `ensureBaseStyles()` (like its sibling components) so the base `:root` tokens it
overrides are present.

## Why this isn't redundant with `.style()`

A single `.style("--sw-accent", v)` already cascades the accent family (P1). `Theme` adds three
things a bare `.style()` does not: **multi-token in one call**, **typed/discoverable** statics
(autocomplete over the `--sw-*` vocabulary instead of stringly-typed names), and the
**`display: contents`** correctness that a hand-rolled wrapper div would lack.

## Components & boundaries

| Unit | Responsibility | Depends on |
|------|----------------|-----------|
| `ThemeToken` | name/value pair + typed statics for brand tokens + `.token()` escape hatch | none |
| `Theme(_:children:)` | render a `display: contents` div carrying the overrides as inline custom properties | `element`, `.style`, `@ChildrenBuilder`, `ensureBaseStyles` |

New file `Sources/SwiflowUI/ThemeScope.swift` holds both, keeping `Theme.swift` (the base
stylesheet) focused.

## Testing

- **Unit (`Tests/SwiflowUITests/ThemeScopeTests.swift`, Swift Testing):**
  - `Theme(.accent("#7c3aed"), .radius("12px")) { p("x") }` renders an `element` `div` whose
    `style` attribute contains `display: contents`, `--sw-accent: #7c3aed`, and
    `--sw-radius: 12px`, with the child node present.
  - `.token("--sw-space-md", "1rem")` produces `--sw-space-md: 1rem`.
  - Nesting: `Theme(.accent(a)) { Theme(.radius(r)) { … } }` renders nested divs each with its
    own override.
  - Each typed static maps to the right `--sw-*` name (`.accent` → `--sw-accent`, etc.).
- **Playwright (`Tests/playwright/`):** a `Button` rendered inside `Theme(.accent("#dc2626"))`
  computes its background from the overridden accent (and a button outside it keeps the default),
  confirming the subtree scoping actually takes effect in a browser.

## Verification

- `swift test` green (the unit suite); the Playwright spec confirms scoped re-skin + no layout
  shift (the themed region sits inline where a normal div would not). Build the demo locally
  (CI skips example builds) and optionally add a themed section to `examples/SwiflowUIDemo`.

## Decisions resolved during brainstorming

1. **What it is** → a **runtime ergonomic `Theme` wrapper** (explicit multi-token overrides), not
   a new capability — single-token subtree theming already works via `.style()` + the accent
   cascade. The build-time generator `--selector` option and a "skip it" close-out were the
   alternatives considered.
2. **Rendering** → `display: contents` wrapper for zero layout impact while still scoping custom
   properties.
3. **No runtime color math** → explicit token values only; derivation stays in the build-time CLI.
