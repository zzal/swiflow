# SwiflowUI directional padding — Design

> **Date:** 2026-06-29 · **Status:** approved, ready for implementation plan
> **Milestone:** the **edge-specific padding** item from the SwiflowUI 1.1+ deferred list
> (`.padding(.lg, .horizontal)`), sketched as a "trivial follow-up" in the original foundation spec.
> **Prior art:** the existing all-edges `VNode.padding(_:)` / `.gap(_:)` modifiers
> (`Sources/SwiflowUI/Modifiers.swift`) and the `Spacing` token enum (`Sources/SwiflowUI/Tokens.swift`);
> the logical/RTL-aware CSS house style (Tooltip's `inset-inline-*`).

## Problem

SwiflowUI's padding modifier is all-edges only: `VNode.padding(_ s: Spacing) -> VNode` writes the
`padding` shorthand. Real layouts routinely want asymmetric padding — "16px horizontal, 8px
vertical", "pad the top only" — which today forces a drop to a raw `.style("padding-inline", …)`
call, defeating the token-driven convenience. The 1.1+ roadmap lists `.padding(.lg, .horizontal)`
for exactly this.

## Goal

Add an edge selector to the padding modifier so any subset of edges can be padded with a `Spacing`
token (or raw length), RTL-aware, with deterministic composition across chained calls — without a
core/framework change and without breaking existing `.padding(.lg)` call sites.

## Decisions (from brainstorming)

1. **Edge selector = `OptionSet`** (not a preset enum, not per-edge keywords). `.padding(.lg, .horizontal)`
   works as sketched, and `.padding(.sm, [.top, .leading])` composes arbitrary subsets in one call.
2. **Logical / RTL-aware.** `leading`/`trailing` → inline-start/-end; `top`/`bottom` → block-start/-end.
   Matches the chosen naming and the house style (Tooltip `inset-inline-*`). Under RTL, `leading`
   follows text direction automatically.
3. **Emit the four atomic logical longhands only — never a shorthand.** This is the load-bearing
   correctness decision (see Mechanism).
4. **Scope = padding only.** Directional `.gap` (row/column-gap) and a new `.margin` modifier are
   non-goals (trivial follow-ups if ever wanted).
5. **No core/framework change** — one new value type + one modifier overload in SwiflowUI.

## API

`Edge` (in `Sources/SwiflowUI/Tokens.swift`, beside `Spacing`):

```swift
/// A set of box edges for directional spacing modifiers. Logical (writing-mode / RTL aware):
/// `leading`/`trailing` follow text direction (inline-start/-end); `top`/`bottom` are block-start/-end.
public struct Edge: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top      = Edge(rawValue: 1 << 0)   // padding-block-start
    public static let bottom   = Edge(rawValue: 1 << 1)   // padding-block-end
    public static let leading  = Edge(rawValue: 1 << 2)   // padding-inline-start
    public static let trailing = Edge(rawValue: 1 << 3)   // padding-inline-end

    public static let horizontal: Edge = [.leading, .trailing]
    public static let vertical:   Edge = [.top, .bottom]
    public static let all:        Edge = [.top, .bottom, .leading, .trailing]
}
```

`padding` overload (in `Sources/SwiflowUI/Modifiers.swift`), replacing the current all-edges-only one:

```swift
public extension VNode {
    /// Adds (or overwrites) padding on the given `edges` using a `--sw-space-*` token (or raw
    /// length). Edges are logical (RTL-aware). Defaults to `.all`, so `.padding(.md)` is unchanged
    /// for callers. Emits the four atomic logical longhands (never a shorthand) so chained calls
    /// compose deterministically — `.padding(.lg).padding(.md, .horizontal)` ⇒ block lg, inline md.
    func padding(_ s: Spacing, _ edges: Edge = .all) -> VNode { … }
}
```

Usage:

```swift
VStack { … }.padding(.lg)                       // all edges (unchanged)
HStack { … }.padding(.lg, .horizontal)          // inline-start + inline-end
Card { … }.padding(.md, .horizontal).padding(.sm, .vertical)   // 16px h / 8px v
panel.padding(.sm, [.top, .leading])            // exactly two edges
row.padding(.custom("3px"), .bottom)            // raw length, one edge
```

The `.gap(_:)` modifier is unchanged.

## Mechanism

Each call maps the selected `edges` to the corresponding **atomic** logical-longhand property names
and writes `name → s.css` for each, via the existing core `VNode.style(_:_:)` postfix modifier (a
no-op on non-element nodes — the established diagnostic path):

| Edge | CSS property |
|------|--------------|
| `.top` | `padding-block-start` |
| `.bottom` | `padding-block-end` |
| `.leading` | `padding-inline-start` |
| `.trailing` | `padding-inline-end` |

`.horizontal` writes the two inline properties; `.vertical` the two block properties; `.all` all
four. (The axis shorthands `padding-inline`/`padding-block` are deliberately NOT used.)

**Why atomic longhands only (the correctness core).** Inline styles are applied per-property through
the CSSOM (`node.style[name] = value`, `js-driver/swiflow-driver.js:207`) and `ElementData.style`
is an **unordered** `[String: String]`. If one modifier wrote the `padding` (or `padding-inline`)
shorthand and another wrote a longhand it overlaps, the result would depend on the nondeterministic
apply order of the dict — a shorthand applied last resets the longhand. Writing only the four atomic
longhands makes every edge a distinct dictionary key, so composition is pure by-key overwrite:
order-independent and deterministic, and partial overrides (`.padding(.lg).padding(.md, .leading)`)
behave intuitively (only `padding-inline-start` changes).

**Behavior change to the existing modifier.** `.padding(.lg)` now emits the four atomic longhands
(each `var(--sw-space-lg)`) instead of a single `padding: var(--sw-space-lg)`. The rendered result
is visually identical; only the emitted property set changes. One existing unit test
(`ModifierTests.paddingAppendsTokenVar`) is updated to assert the longhands. Pre-1.0, the emitted
CSS is an implementation detail, and the longhand form is the more-correct (logical/RTL) one.

## Components & boundaries

| Unit | Change |
|------|--------|
| `Edge` (Tokens.swift) | new `OptionSet` value type + edge→property mapping helper |
| `VNode.padding(_:_:)` (Modifiers.swift) | replace the all-edges overload; default `edges: .all`; emit atomic longhands |
| `ModifierTests` | update the existing all-edges assertion; add directional + composition tests |
| `docs/guides/swiflowui.md` | one-line note + example |

All in SwiflowUI. No core/framework change; `.gap`, `Spacing`, and every other component untouched.

## Testing

- **Unit (`Tests/SwiflowUITests/ModifierTests.swift`):**
  - `.padding(.lg)` sets all four atomic longhands to `var(--sw-space-lg)` and nothing named `padding`.
  - `.padding(.lg, .horizontal)` sets `padding-inline-start`/`-end` only; `.vertical` sets the block pair only.
  - `.padding(.sm, [.top, .leading])` sets exactly `padding-block-start` + `padding-inline-start`.
  - **Composition:** `.padding(.lg).padding(.md, .horizontal)` ⇒ block longhands `lg`, inline longhands `md`.
  - `.padding(.custom("3px"), .bottom)` ⇒ `padding-block-end: 3px`.
  - Doesn't disturb sibling styles (e.g. a stack's `display: flex` survives).
- **Host `swift build` + `swift test`** green.
- **Demo (optional eyeball):** an asymmetric-padding example can be added to the SwiflowUIDemo gallery
  if useful, but is not required for this change.

## Non-goals

- **No directional `.gap`** (row-gap/column-gap) and **no `.margin` modifier** — out of scope.
- **No physical edges** (`left`/`right`) — logical only.
- **No per-edge-different-value single call** (`.padding(top: .lg, bottom: .sm)`) — chain instead.
- **No core/framework change**, no new state machinery.

## Decisions resolved during brainstorming

1. **Edge selector shape** → `OptionSet` (preset-enum and per-edge-keyword forms rejected).
2. **Logical vs physical** → logical/RTL-aware (`leading`/`trailing`, inline/block).
3. **Emission** → four atomic logical longhands only, never a shorthand (deterministic composition
   over the unordered style dict).
4. **Scope** → padding only; `.gap`/`.margin` deferred.
