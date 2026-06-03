# SwiflowUI Foundation — Design (v0: token foundation + Stack proof)

> **Status:** Approved in brainstorming 2026-06-03. Next step: implementation plan
> (`docs/superpowers/plans/`). This is data-layer-adjacent roadmap item **B3**
> (`docs/future-work/roadmap.md`), cut down to its self-contained first increment.

## Goal

Establish `SwiflowUI` — a standard component library module — by shipping its
**styling foundation** (a `--sw-*` design-token contract + a once-injected base
sheet) and proving the mechanics with the two leanest layout primitives:
`VStack` and `HStack`. No framework prerequisites; runs entirely on existing
infrastructure.

## Scope

**In:** the `--sw-*` token contract, lazy-once base-sheet injection, `VStack` /
`HStack`, a tiny `Spacing`-typed chainable-modifier set (`.padding`, `.gap`),
and tests.

**Out (explicitly deferred to follow-up specs):**
- `Grid`, `Stack` (z-axis/overlap), `Spacer`, `Divider`, and richer layout.
- **Overlays** — `Alert` / `Prompt` / `Toast`. These need the portal/overlay-root
  host (roadmap cross-cutting **#3**) and `EventInfo` target identity (**#4**,
  see `project_eventinfo_missing_target`) for backdrop / click-outside. They get
  their own spec that builds those enablers first.
- Skinned components (e.g. a styled `Button`). The base-sheet mechanism is built
  and proven here so skins drop in later with no new infrastructure.
- Edge-specific padding (`.padding(.lg, .horizontal)`) — trivial follow-up.

## Decisions (locked in brainstorming)

1. **API flavor — Hybrid (JSX call site + typed args).** Primitives are
   free functions returning `VNode`, identical in shape to today's `div { }`.
   **No parallel `View` tree / value-view abstraction.** SwiftUI-ish ergonomics
   (typed `spacing:`/`align:` args, a light chainable-modifier surface) over the
   existing model, not a reimplementation of it.
2. **Styling stance — token-driven themeable defaults.** Components only ever
   *read* `--sw-*` custom properties; an app reskins by overriding them at
   `:root`. Ship sensible defaults.
3. **CSS mechanism — split.** Dynamic per-instance axes (`gap`, `padding`,
   `align`, `justify`) → **inline styles referencing token vars** (reuses the
   existing `.style()` machinery; stays themeable because the var resolves from
   the cascade even when written inline). Component *skins* + pseudo/responsive
   states → the **shared base sheet** (the existing `CSSSheet` mechanism). For v0
   the base sheet is just the `:root` token block; it gains skin rules when
   skinned components arrive.
4. **Injection trigger — lazy auto-install + testable seam.** First render of any
   SwiflowUI primitive injects the base sheet exactly once; no app boilerplate. A
   public `installBaseStyles()` is also exposed for explicit/deterministic use.

## Architecture

### Module shape

New SwiftPM target **`SwiflowUI`**, depending on `Swiflow` (for `VNode`,
`Attribute`, `CSSSheet`) and `SwiflowWeb` (for DOM injection). All JavaScript
touchpoints are behind `#if canImport(JavaScriptKit)`, so host `swift build` /
`swift test` compile and run the pure logic (lowering + token sheet) with
injection a no-op.

```
Sources/SwiflowUI/
  Tokens.swift     — Spacing / CrossAlign / MainAlign enums + value mapping
  Theme.swift      — baseStyleSheet (CSSSheet of :root tokens) + ensureBaseStyles() + installBaseStyles()
  Stack.swift      — VStack / HStack free functions
  Modifiers.swift   — .padding(_:) / .gap(_:) VNode extensions (Spacing-typed)
```

### Shared once-injection (DRY refactor)

Today `CSSInjector` (SwiflowWeb) owns both the *once-guard* (a `Set` of injected
ids) and the *DOM emit*. To avoid a second copy in SwiflowUI, factor the
guard + emit into a reusable, host-testable seam:

- **`StyleInjectionRegistry` (in `Swiflow`, pure):** holds `injectedIDs:
  Set<String>` and a `nonisolated(unsafe) var emit: ((_ id: String, _ css: String) -> Void)?`
  hook (mirrors the existing `onComponentTypeMount` / `CSSMountHook` pattern).
  `injectOnce(id:css:)` checks the guard, inserts, and calls `emit`. `reset()`
  clears the guard (tests/HMR).
- **`SwiflowWeb` wiring:** at setup, sets `StyleInjectionRegistry.emit` to the
  real `<head>` `<style>` append (the body of today's `CSSInjector.inject`).
  `CSSInjector` is migrated to route through the registry so there is exactly
  one injection code path. Its existing tests pin the behavior across the move.
- **`SwiflowUI`:** `ensureBaseStyles()` calls
  `StyleInjectionRegistry.injectOnce(id: "swiflow-ui-base", css: baseStyleSheet.cssString(scopeClass: ""))`.
  (The token block uses `:root`, which `CSSSheet.shouldScope` already leaves
  unscoped, so the empty `scopeClass` is harmless.)

This keeps the once-semantics in one place, makes "emitted exactly once"
assertable on the host via the `emit` hook, and removes duplicated DOM code.

### Token contract (`Theme.swift`)

The complete `--sw-*` vocabulary ships now (only spacing/align are *consumed* by
v0 primitives; the rest is the forward contract skinned components will read):

```swift
public let baseStyleSheet = css {
  raw("""
  :root {
    --sw-space-xs: 0.25rem;  --sw-space-sm: 0.5rem;  --sw-space-md: 0.75rem;
    --sw-space-lg: 1.25rem;  --sw-space-xl: 2rem;
    --sw-radius:  8px;
    --sw-accent:  light-dark(#3b82f6, #60a5fa);
    --sw-surface: light-dark(#ffffff, #1a1a1a);
    --sw-text:    light-dark(#111111, #f5f5f5);
  }
  """)
}
```

### Tokens & mappings (`Tokens.swift`)

```swift
public enum Spacing {
  case none, xs, sm, md, lg, xl
  case custom(String)
  /// CSS length for a `gap`/`padding` value.
  var css: String {
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

public enum CrossAlign {            // -> align-items
  case start, center, end, stretch, baseline
  var css: String {
    switch self {
    case .start:    return "flex-start"
    case .center:   return "center"
    case .end:      return "flex-end"
    case .stretch:  return "stretch"
    case .baseline: return "baseline"
    }
  }
}

public enum MainAlign {             // -> justify-content
  case start, center, end, between, around, evenly
  var css: String {
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

### Primitives (`Stack.swift`)

`VStack`/`HStack` are capitalized free functions — capitalization marks a
SwiflowUI primitive versus a lowercase raw HTML element (`div`). They lower
**fully inline** (no structural class), so a caller's `.class("hero")` adds
cleanly with nothing to clobber.

```swift
public func VStack(
  spacing: Spacing   = .none,
  align:   CrossAlign = .stretch,
  justify: MainAlign  = .start,
  _ attributes: Attribute...,
  @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
  stack(direction: "column", spacing, align, justify, attributes, children())
}

public func HStack(
  spacing: Spacing   = .none,
  align:   CrossAlign = .stretch,
  justify: MainAlign  = .start,
  _ attributes: Attribute...,
  @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode { … direction "row" … }
```

A private `stack(...)` helper triggers `ensureBaseStyles()`, builds the inline
style decls in a deterministic order, prepends them as `.style(...)` attributes
(so caller-supplied `attributes` win on conflict via last-write-wins in
`applyAttributes`), and returns `div(...) { children }`.

Emitted output for `VStack(spacing: .md, align: .center)`:

```html
<div style="display:flex; flex-direction:column; gap:var(--sw-space-md); align-items:center; justify-content:flex-start">
```

(`gap` is omitted when `.none`; `align-items`/`justify-content` always emitted at
their defaults — cheap and explicit. Decision: emit `display`/`flex-direction`
always; emit `gap` only when non-`.none`; always emit align/justify.)

### Chainable modifiers (`Modifiers.swift`)

```swift
public extension VNode {
  func padding(_ s: Spacing) -> VNode { style("padding", s.css) }
  func gap(_ s: Spacing) -> VNode { style("gap", s.css) }
}
```

Both are thin wrappers over the existing `VNode.style(_:_:)` postfix modifier
(`VNodeModifiers.swift`), so they append one inline decl and are no-ops on
non-element nodes (the existing `mergeAttribute` diagnostic path).

## Data flow

1. App calls `VStack(spacing: .md) { … }` inside a component `body`.
2. `stack(...)` calls `ensureBaseStyles()` → `StyleInjectionRegistry.injectOnce`.
   On the first call ever, the `emit` hook appends the `:root` token `<style>` to
   `<head>`; subsequent calls hit the guard and do nothing. On the host (no JS),
   `emit` is nil → no-op.
3. `stack(...)` returns a `div` `VNode` carrying inline `display/flex-direction/
   gap/align-items/justify-content` styles (token vars for the spacing axis).
4. The normal renderer diffs/patches the `div` like any other element. The
   browser resolves `var(--sw-space-md)` from the injected `:root` block.
5. An app reskin (`:root { --sw-space-md: 1rem }` in its own sheet, later in the
   cascade) overrides the token; inline `gap:var(--sw-space-md)` re-resolves.

## Error handling / edge cases

- **No JS host:** injection `emit` is nil; primitives still produce correct
  `VNode`s. This is the test path, not an error.
- **Modifier on non-element VNode:** inherits the existing
  `mergeAttribute` DEBUG diagnostic + pass-through (no crash).
- **Double install:** idempotent by the registry `Set` guard.
- **`.custom(value)`:** passed through verbatim as a raw CSS length; caller's
  responsibility (documented). No validation — matches `.style()` today.
- **Known future consideration (not v0):** when *skinned* primitives arrive they
  WILL carry a structural class (e.g. `sw-btn`), and a caller's `.class("x")`
  would clobber it (current `VNode.class` overwrites). That motivates an additive
  `addClass` then; out of scope here because `VStack`/`HStack` carry no class.

## Testing

- **Lowering (host, deterministic, no JS):** assert the returned `VNode`'s
  `ElementData` — `tag == "div"`, style bag has `display:flex`,
  `flex-direction:column|row`, `gap:var(--sw-space-md)` (and absent when
  `.none`), `align-items`, `justify-content`; children preserved; caller
  attributes override.
- **Modifiers (host):** `.padding(.lg)` appends `padding:var(--sw-space-lg)`;
  `.gap(.sm)` overrides a prior gap; non-element node passes through.
- **Theme / injection (host):** `baseStyleSheet.cssString(scopeClass: "")`
  contains the `:root` token block unscoped; with a test `emit` hook installed,
  rendering several primitives fires the emit **exactly once** for id
  `swiflow-ui-base`; `reset()` re-arms it.
- **CSSInjector parity:** existing `CSSInjector` tests still pass after the
  migration to `StyleInjectionRegistry` (behavior unchanged).
- **Browser e2e (one):** a minimal `SwiflowUI` usage renders a flex row/column
  with a visible gap (computed `display:flex`), and overriding `--sw-space-md`
  at `:root` visibly changes the gap.

## Files

```
Create:  Sources/SwiflowUI/Tokens.swift
Create:  Sources/SwiflowUI/Theme.swift
Create:  Sources/SwiflowUI/Stack.swift
Create:  Sources/SwiflowUI/Modifiers.swift
Create:  Sources/Swiflow/CSS/StyleInjectionRegistry.swift
Modify:  Sources/SwiflowWeb/CSS/CSSInjector.swift   (route through the registry)
Modify:  Package.swift                               (SwiflowUI target + test target)
Create:  Tests/SwiflowUITests/StackLoweringTests.swift
Create:  Tests/SwiflowUITests/ModifierTests.swift
Create:  Tests/SwiflowUITests/ThemeInjectionTests.swift
```

## Dependencies / sequencing

- No framework prerequisites — runs on `VNode`/`CSSSheet`/`CSSInjector` as they
  exist today.
- **Next specs after this:** richer layout (`Grid`/`Spacer`/`Divider`), then
  overlays (`Alert`/`Prompt`/`Toast`) which first build cross-cutting prereqs
  **#3** (portal host) and **#4** (`EventInfo` target identity).
