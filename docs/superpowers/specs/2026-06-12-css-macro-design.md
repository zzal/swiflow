# `#css` Macro — Real CSS in Swift

**Date:** 2026-06-12
**Status:** Approved design, pending implementation plan

## Problem

Component styles are written through the `css { rule(".x") { fontSize("1.4rem") } }`
result-builder DSL. Every value is a raw string anyway, so authors pay DSL ceremony
(function-call wrappers, the `property(_:_:)` escape hatch for anything not among the
~80 wrapper functions, no nesting) without getting type safety in return. For people
who already know CSS, the constant translation — "is there a `gridTemplateColumns`
function, or do I need `property(...)`?" — is friction with no payoff.

## Goal

Let experienced CSS authors write **actual CSS** in Swift files. The framework
validates *structure* at compile time and otherwise passes the rules to the browser
verbatim — so as CSS evolves, new properties, selectors, and at-rules work the day
the browser ships them, with no Swiflow release required.

## Decisions already made

| Decision | Choice |
|---|---|
| North star | Real CSS syntax for CSS veterans, zero translation tax |
| Validation | Compile time, via a freestanding `#css` macro |
| Interpolation | None — static literals only; dynamic values flow through CSS custom properties |
| Existing DSL | Stays a first-class peer; both documented, both supported |
| Architecture | Validated pass-through + native CSS nesting for scoping (no CSS IR, no per-property modeling) |

## API

```swift
extension QuakesPage {
    static var scopedStyles: CSSSheet? = #css("""
        :host {
          display: block;
          max-width: 860px;
          margin: 0 auto;
        }
        .quake-row {
          display: grid;
          grid-template-columns: 5.5rem 1fr max-content;
          gap: var(--sw-space-md);

          .when { color: color-mix(in srgb, var(--sw-text) 60%, transparent); }
          &:hover { background: var(--sw-surface-hover); }
        }
        @media (max-width: 600px) {
          .quake-row { grid-template-columns: 1fr; }
        }
        @keyframes mc-spin {
          to { transform: rotate(360deg); }
        }
    """)
}
```

- `#css` is a freestanding expression macro returning `CSSSheet`. It composes with
  DSL-built sheets via the existing `+` operator (`#css("...") + animations`).
- The argument must be a **static string literal**. Interpolation is a compile error
  with a fix-it message pointing at the custom-property idiom:

```swift
// dynamic values: set a custom property on the node…
div(.class("badge")).style("--badge-color", magColor)
// …and consume it in the static sheet:
#css(".badge { color: var(--badge-color); }")
```

## Architecture

### Expansion target

A new `CSSEntry` case carries the scoped body; hoisted segments reuse the existing
`.raw` case:

```swift
public enum CSSEntry: Sendable {
    // …existing cases unchanged…
    /// CSS authored via #css. Rendered as ".<scopeClass> { <body> }" so the
    /// browser's native CSS nesting performs the scoping.
    case scopedBlock(String)
}
```

The macro expands to ordinary `CSSSheet` construction — e.g.:

```swift
CSSSheet(entries: [
    .raw("@keyframes mc-spin {\n  to { transform: rotate(360deg); }\n}"),
    .scopedBlock("…everything else, with :host rewritten…"),
])
```

Because the result is a plain `CSSSheet`, the entire downstream pipeline —
`cssString(scopeClass:)`, `CSSInjector`, `StyleInjectionRegistry` de-dup, HMR style
re-injection, sheet composition — works unchanged.

### What the macro does (and deliberately does not do)

The macro plugin gains a **structural** CSS parser (`CSSStructuralParser`): a
tokenizer that understands comments, strings, `url()`, and brace/paren/bracket
balance, plus a top-level block splitter. It never models properties, values, or
selector grammar — that is the browser's job and the source of the design's
future-proofness.

At expansion time it:

1. **Validates structure** (see Diagnostics below).
2. **Splits top-level segments** into three classes:
   - *Hoisted at-rules* — `@keyframes`, `@font-face`, `@property`, `@layer`
     statements, and any other at-rule that is invalid when nested inside a style
     rule. Emitted as `.raw` entries in source order, outside the scope wrapper.
   - *Unscoped rules* — selectors starting with `:root`, `html`, or `body`
     (parity with the DSL path's `shouldScope`). Emitted as `.raw`.
   - *Everything else* — concatenated into a single `.scopedBlock`.
3. **Rewrites `:host`** within the scoped block: bare `:host` → `&`;
   `:host(<sel>)` → `&:is(<sel>)`. Inside the runtime wrapper, `&` is the
   scope-class element, so this lands on the component root.

Conditional group at-rules (`@media`, `@container`, `@supports`, `@scope`,
`@starting-style`, and whatever ships next) need **no special handling** — native
nesting permits them inside style rules, so they stay in the scoped block verbatim.
Unknown at-rules are assumed nestable; if a future at-rule turns out to need
hoisting, adding its name to the hoist list is a one-line change.

### Runtime rendering

```swift
case .scopedBlock(let body):
    return ".\(scopeClass) {\n\(indent(body))\n}"
```

Native CSS nesting (baseline in all supported browsers, alongside the
`light-dark()` / `color-mix()` / `@starting-style` features Swiflow already relies
on) makes the browser perform the scoping. A future upgrade can swap this wrapper
for `@scope (.<scopeClass>) to (…)` to get donut scoping — stopping parent styles
from leaking into nested components — **with zero API change**, because scoping
lives entirely in this one render case.

## Scoping semantics (the documented contract)

- `:host { … }` styles the component's root element (the one carrying
  `.swiflow-<TypeName>`). Top-level `&` means the same thing.
- Every other top-level selector matches **descendants** of the root.
- `:root` / `html` / `body`-leading rules escape scoping entirely.
- `@keyframes` names are global (unchanged from the DSL path) — authors namespace
  manually, e.g. `mc-spin`. Auto-namespacing is future work.

This is the Shadow-DOM mental model CSS authors already hold. Note one deliberate
divergence from the DSL path: the DSL emits a dual compound+descendant selector for
class-leading rules (`.swiflow-X.foo, .swiflow-X .foo`); `#css` is
descendant-only, with `:host` as the explicit way to style the root. The docs state
this side by side.

## Diagnostics

All structural problems are **compile errors** carrying the line/column *within the
CSS literal*, mapped back to a source location inside the literal where
swift-syntax segment offsets allow (multiline-literal indentation stripping makes
this fiddly; v1 may anchor the diagnostic on the literal with "line N, column M"
in the message, tightening to exact positions where feasible):

| Condition | Diagnostic |
|---|---|
| Unbalanced `{}`/`()`/`[]`, unterminated string or comment | `CSS syntax error at line N: …` |
| Declaration segment (ends in `;`) with no `:` | `expected 'property: value' at line N — got 'display grid'` |
| String interpolation anywhere | `#css requires a static literal — pass dynamic values via CSS custom properties (.style("--x", value))` |
| Non-literal argument | same as above |
| `@import` | `@import is not supported in component sheets — load global CSS from index.html` |

**Not validated, by design:** property names, value grammar, selector pseudo-class
spelling. Unknown CSS passes through exactly as it would in a `.css` file. This is
the future-proofing contract: Swiflow never gatekeeps what CSS you may write.

Empty/whitespace-only literal: valid, expands to an empty sheet.

## Components

| Piece | Location | Role |
|---|---|---|
| `CSSMacro` | `Sources/SwiflowMacrosPlugin/CSSMacro.swift` | Freestanding expression macro: literal extraction, parser invocation, diagnostics, `CSSSheet` expression emission |
| `CSSStructuralParser` | `Sources/SwiflowMacrosPlugin/CSSStructuralParser.swift` | Pure tokenizer + splitter + `:host` rewriter; returns segments + diagnostics with offsets; no SwiftSyntax dependency so it is unit-testable in isolation |
| Macro declaration | `Sources/Swiflow/Macros.swift` | `@freestanding(expression) public macro css(_ source: String) -> CSSSheet` (invoked as `#css`; no collision with the `css {}` function — macro references always use `#`) |
| `CSSEntry.scopedBlock` | `Sources/Swiflow/CSS/CSSSheet.swift` | New case + render arm |
| Example migration | `examples/MissionControl/…/QuakesPage+Styles.swift` | Rewritten with `#css` as the living showcase; other examples stay on the DSL, demonstrating that both are peers |
| Docs | `docs/guides/…` | "Styling with #css" guide + side-by-side scoping-semantics note |

## Testing

- **Parser unit tests** (new target-internal tests beside the existing
  `SwiflowMacrosTests` pattern): brace/paren balance, comments, strings, `url()`,
  hoist classification for each at-rule, `:root`/`html`/`body` escape, `:host` and
  `:host(...)` rewriting, diagnostic offsets, empty input.
- **Macro expansion tests** (`Tests/SwiflowMacrosTests/CSSMacroTests.swift`, via
  `assertMacroExpansion` like the existing macro tests): golden expansions for a
  representative sheet; each diagnostic condition fires with the right message.
- **Render tests** (`Tests/SwiflowTests/CSS/CSSSheetTests.swift` additions):
  `.scopedBlock` wraps with the scope class; hoisted `.raw` entries emit unwrapped;
  `#css`-built and DSL-built sheets compose with `+`.
- **End-to-end:** the migrated Quakes page must pass the existing playwright suite
  unchanged — same visual result from `#css` as from the DSL it replaces.

## Out of scope (v1)

- Interpolation in values (revisit if custom properties prove insufficient)
- `@keyframes` auto-namespacing
- `@scope`-based donut scoping (designed-for, not built)
- Sidecar `.css` files
- Property-name lints / typo warnings
- Any change to the existing DSL (peers, per decision)