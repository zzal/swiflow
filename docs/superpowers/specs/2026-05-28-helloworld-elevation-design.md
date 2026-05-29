# HelloWorld Elevation — Design

**Date:** 2026-05-28
**Status:** Spec, ready for plan
**Scope:** `examples/HelloWorld/`, plus targeted additions to `Sources/Swiflow/` and `Sources/SwiflowWeb/`.

## Problem

`examples/HelloWorld` is Swiflow's first impression. It currently doesn't earn it.

1. **The scoped CSS doesn't work on the root element.** `Counter`'s scoped rule `.container` is rewritten as `.swiflow-Counter .container` — a descendant selector. But `.container` is the body root and *is* `.swiflow-Counter`, not a descendant of it. None of the root rules apply. That's why the `counter-in` animation never runs, and why `Toast`'s background/padding/border-radius silently no-op. The keyframes are valid; the rules that reference them are dead.
2. **The toast isn't a toast.** It renders inline below the count: no fixed positioning, no shadow, no top-layer guarantee, no auto-dismiss, no accessibility role.
3. **The HTML is unambitious.** Inline `.style(...)` scattered through `SignIn`. No use of `<dialog>`, the Popover API, `<details>`, anchor positioning, `color-mix`, `light-dark`, `@property`, container queries, view transitions, or `focus-visible`.

## Goal

Make HelloWorld land as a small, complete, modern showcase of what the framework can do — without ballooning into a gallery and without losing the "hello, here's Swiflow" simplicity. Fix the framework bug that's silently breaking scoped styles on root elements. Add the minimum set of framework primitives (element factories, CSS DSL entries, composable sheets) that the showcase needs.

## Non-goals

- True CSS-Modules-style locally-scoped hashed class names. Deferred to a separate spec.
- Sidecar external `.css` resource files. Deferred to a separate spec.
- A second example app or a card-gallery rewrite. The Counter → Toast → SignIn flow stays.
- Reworking `MiniRouter` or any other example.
- Adding HMR or build-pipeline tooling.

## Design

### 1. Framework fix — scoped class rules must match the root

In `Sources/Swiflow/CSS/CSSSheet.swift`, `CSSEntry.cssString(scopeClass:)` currently emits:

```
.swiflow-Counter .container { ... }
```

for `rule(".container") { ... }`. Change the rewrite for class-leading selectors to a dual selector:

```
.swiflow-Counter.container, .swiflow-Counter .container { ... }
```

The compound form (no space) matches the root when the rule's leading class equals one of its classes; the descendant form keeps matching nested elements. This is the trick `<style scoped>` uses without introducing a data-attribute or an `&` parser.

Selectors that don't lead with a class (e.g. `rule("button") { ... }`, `rule(":root") { ... }`) are unaffected — they keep their current behavior.

Edge case: combined selectors like `rule(".x .y") { ... }`. The leading class is `.x`; we still only emit dual selectors for the leading token. The compound form becomes `.swiflow-T.x .y` and the descendant form `.swiflow-T .x .y`. Both work.

### 2. Framework addition — `host { }` DSL entry

For the cases where the author explicitly means "the root element of this component," add a `host` builder:

```swift
public func host(@CSSRuleBuilder _ content: () -> [CSSDeclaration]) -> CSSEntry {
    .host(declarations: content())
}
```

This compiles to `.swiflow-T { ... }` (single selector, no compound or descendant). It's the right tool when (a) the root has no extra class to key off, or (b) you want unambiguous root-only styles without relying on the dual-selector trick.

Internally, `CSSEntry` gains a `.host(declarations:)` case.

### 3. Framework addition — composable sheets (`+` operator)

```swift
public extension CSSSheet {
    static func + (lhs: CSSSheet, rhs: CSSSheet) -> CSSSheet {
        CSSSheet(entries: lhs.entries + rhs.entries)
    }
}
```

Lets a component split its styles across files via Swift extensions:

```swift
extension Counter {
    static var scopedStyles: CSSSheet? = layout + theme + animations
}
extension Counter {
    static let layout     = css { host { ... }; rule(".count") { ... } }
    static let theme      = css { host { ... }; rule(".card") { ... } }
    static let animations = css { keyframes("counter-in") { ... } }
}
```

Zero runtime cost — `+` is array concatenation. Editor support stays intact.

### 4. Framework addition — missing element factories

In `Sources/Swiflow/DSL/Elements.swift`, add the following alongside the existing factories, following the same `(_ attributes: Attribute..., @ChildrenBuilder children:)` pattern (plus text-only convenience overloads where natural):

- `dialog(...)`
- `details(...)`
- `summary(...)`
- `aside(...)`
- `output(...)`
- `hr(...)` — void element, no children block

Popover is *not* a new factory — it's an attribute (`.attr("popover", "auto" | "manual")`) on any element. We document this in the changelog rather than add a wrapper.

### 5. Framework addition — CSS declaration helpers

Add the following one-line `CSSDeclaration` helpers in the CSS DSL (each is a literal `CSSDeclaration("kebab-name", value)`):

- `positionAnchor`, `positionArea`, `anchorName`
- `viewTransitionName`
- `interpolateSize`
- `accentColor`
- `colorScheme`
- `insetBlockEnd`, `insetInline`, `inset`
- `placeItems`
- `marginInline`
- `backdropFilter`
- `transitionBehavior`

These are mechanical additions; they exist so the showcase can be written in pure Swift without dropping to raw inline CSS.

### 5b. Framework addition — raw CSS escape hatch for at-rules

The current CSS DSL only models `.rule` and `.keyframes` entries. The showcase needs `@container (max-width: 380px) { ... }` (container query) and `@property --accent { ... }` (registered custom property). Rather than model every at-rule with its own builder, add a single escape hatch:

```swift
public enum CSSEntry: Sendable {
    case rule(selector: String, declarations: [CSSDeclaration])
    case keyframes(name: String, stops: [KeyframeStop])
    case host(declarations: [CSSDeclaration])  // from §2
    case raw(String)                            // new
}

public func raw(_ css: String) -> CSSEntry { .raw(css) }
```

`raw` emits its string verbatim — no scoping, no rewriting. The HelloWorld showcase uses it twice: once for `@property --accent { ... }` (which is global-by-nature) and once for `@container (max-width: 380px) { ... }` wrapping a class rule (acceptable for a single-line at-rule; if container queries become common we add a dedicated builder later).

This is a deliberate small surface — escape hatches are appropriate for at-rules that aren't worth modeling yet. The CSS scoping fix in §1 leaves `.raw` untouched.

### 6. Toast — rebuilt as a Popover

`Toast` becomes a top-layer popover with proper styling, accessibility, and auto-dismiss.

Key behaviors:

- The root element gets `.attr("popover", "manual")`. Manual mode keeps light-dismiss off so clicks elsewhere on the page aren't stolen.
- `onAppear` calls `showPopover()` on the root element (via `Ref<JSObject>`) and schedules a 2.5-second auto-dismiss by invoking the parent's `onDone` callback.
- Click on the toast also dismisses (the existing `cursor: pointer` affordance stays).
- `role="status"`, `aria-live="polite"` for screen-reader announcement on insertion.

Open question to resolve during implementation: does `SwiflowWeb` already expose a tick/`after(_:)` utility for the 2.5-second timer? If not, add a tiny `setTimeout`-backed helper. Either way, the timer must be cancellable on early unmount (when the parent toggles `showToast = false` before 2.5s elapse).

Styling, in a `Toast.scopedStyles` composed sheet:

- Uses `host { ... }` to target the popover root (no `.root` class on it anymore — popover state IS the identifier).
- `position: fixed; inset-block-end: 1.5rem; inset-inline: 0; margin-inline: auto; width: max-content; max-width: min(90vw, 360px);`.
- Pill shape: `border-radius: 999px`, `padding: 0.75rem 1rem`.
- `background: color-mix(in oklab, canvas 88%, canvasText)`, `color: canvasText` — picks up light/dark from `color-scheme`.
- `box-shadow: 0 12px 32px -12px rgb(0 0 0 / .35), 0 2px 6px -2px rgb(0 0 0 / .15)`.
- Existing `toast-in` / `toast-out` keyframes kept; entry animation gets a slight `scale(.96 → 1)` so it feels less flat.
- An `.icon` child element rendered before the message (`✓` for now; passable via `init` later if needed).

`exitAnimation` / `exitDuration` stay; the popover mechanism is orthogonal to Swiflow's existing exit animation pipeline.

### 7. Counter — small surface upgrades

- Body root becomes `div(.class("card"))` (not `.container`) and uses `host { ... }` for the card chrome. Eliminates the dual-selector ambiguity entirely for this component.
- `count` increment is wrapped in a `document.startViewTransition(...)` call when the API is available. The `.count` element declares `view-transition-name: count-value` so the digit crossfades on change. Pure CSS for browsers without VT — they get an instant swap.
- Adds a small `<button popovertarget="about-popover">ⓘ</button>` next to the `<h1>`, and the popover element described in §8.
- Adds a `<details>` block: "▸ What's running here?" — when open, a short annotated list of the components/primitives on screen. Uses custom `::marker` for the chevron, and `interpolate-size: allow-keywords` + `transition: height` for animated open/close.
- The `Show Sign In demo` toggle is replaced with `Sign in…`, which opens a `<dialog>` via `showModal()` (see §9).
- Inline `.style(...)` for the bottom border-top spacing block is moved into the scoped sheet.

### 8. AboutPopover — declarative popover with anchor positioning

A small component rendered once by `Counter`:

```swift
@MainActor @Component
final class AboutPopover {
    static var scopedStyles: CSSSheet? = css {
        host {
            // popover layer styling
            positionAnchor("--info-anchor")
            positionArea("bottom span-right")
            // appearance
        }
        rule("h3") { ... }
        rule("a") { ... }
    }
    var body: VNode {
        div(.id("about-popover"),
            .attr("popover", "auto"),
            .style(name: "anchor-name", value: "--info-anchor")) {
            h3("About Swiflow")
            p("Swift, compiled to WASM, with a reactive component model.")
            link("View on GitHub", .attr("href", "..."))
        }
    }
}
```

The `<button>` trigger uses `popovertarget="about-popover"` — no Swift event handler needed. CSS Anchor Positioning floats the card next to the trigger. `popover="auto"` gives light-dismiss and Escape-to-close.

Older browsers without popover/anchor positioning still render the element; it appears as a normal block (visually less polished, but functional). Acceptable for an example.

### 9. SignIn — wrapped in a native `<dialog>`

The current `SignIn` body is preserved verbatim. It becomes the contents of a `<dialog>` element opened via `showModal()`:

```swift
@MainActor @Component
final class Counter {
    let signInDialog = Ref<JSObject>()
    ...
    func openSignIn() {
        if let el = signInDialog.wrappedValue { _ = el.showModal!() }
    }
}
```

What this earns us:

- Native focus trap and `inert` on the rest of the page.
- Escape-to-close for free.
- A real `::backdrop` pseudo-element — styled with a blurred `backdrop-filter`.
- Open/close animation surface via `@starting-style` + `transition-behavior: allow-discrete` on `display`/`overlay`. No JS animation orchestration.

The dialog closes via either Escape, the backdrop click (we'll wire a small `(.on(.click))` handler that calls `.close()` when the click target is the dialog itself), or the existing "Sign out" / explicit cancel button.

Inline `.style(...)` calls inside `SignIn` are migrated to a `SignIn+Styles.swift` extension so the component body is structural HTML only.

### 10. CSS tokens applied across the showcase

Used consistently in all three components' style files:

- `:root` rule (emitted unscoped — current behavior of `cssString` for `:root`) sets `color-scheme: light dark` and a small token set: `--accent`, `--surface`, `--surface-elev`, `--text`, `--text-dim`, `--border`. Each uses `light-dark(...)`.
- `@property --accent` declared as `<color>` with an initial value so it's animatable. Emitted via the §5b `raw(...)` escape hatch. The count number's color animates on increment.
- All interactive elements get `:focus-visible` outlines (not `:focus`).
- Inputs/checkboxes get `accent-color: var(--accent)`.
- `.card` has a `@container (max-width: 380px) { ... }` rule that restacks vertically — also emitted via `raw(...)`. The card sets `container-type: inline-size` on its host.

This is the part that gives the page visual identity without theme code.

### 11. File layout

```
examples/HelloWorld/
  Sources/App/
    App.swift                 // @main, Counter, render entry
    Counter+Styles.swift      // layout + theme + animations sheets
    Toast.swift               // popover-based toast
    Toast+Styles.swift
    SignIn.swift              // body wrapped by Counter's <dialog>
    SignIn+Styles.swift
    AboutPopover.swift
    AboutPopover+Styles.swift
  index.html                  // minimal inline CSS — only the loading indicator
  Package.swift               // unchanged
```

Goes from one 220-line file to ~8 focused files, none over ~80 lines. The CLI `swiflow init --template HelloWorld` flow keeps working because templates re-embed automatically from `examples/`.

## Testing

### Unit tests

- `Tests/SwiflowTests` gets a test for `CSSSheet.cssString` covering:
  - `.x` class rule → emits dual selector.
  - `tag` rule → unchanged (descendant only).
  - `:root` rule → unscoped, unchanged.
  - `host { ... }` entry → emits `.swiflow-T { ... }`.
  - `.x .y` rule → dual selector on `.x`, descendant on `.y`.
  - `raw("…")` entry → emitted verbatim, no scoping applied.
- `CSSSheet.+` round-trip: `(a + b).entries == a.entries + b.entries`.

### E2E

- A new Playwright spec under `tests/e2e/helloworld.spec.ts`:
  - Increment runs the view transition (the `.count` element is present and the value changes).
  - "Show toast" mounts the popover, auto-dismisses within ~3s, role/aria attributes present.
  - "Sign in…" opens the dialog (`dialog[open]` present), Escape closes it, backdrop is rendered.
  - "ⓘ" popover toggles via `popovertarget` and dismisses on Escape.
  - "▸ What's running here?" `<details>` opens/closes.

Per the auto-memory note: Playwright runs PR-only, and this project pushes to `main`. Spec must explicitly call out that this E2E suite must be run manually after framework runtime changes.

### CLI template round-trip

- The existing `swiflow init --template HelloWorld` round-trip test (per `EmbeddedTemplates` freshness test) keeps working unchanged. New files are picked up automatically by the codegen script. No test changes required beyond confirming the round-trip still passes after the file split.

## Migration / compatibility

- The CSS scope fix changes emitted CSS. Existing components whose root selector was `.x` and that *also* relied on the (broken) descendant-only match for nested `.x` are extraordinarily unlikely, but if any downstream user has both a `.x` root and a descendant `.x` and depended on the bug, they'd now see both styled. This is the intended correction; it'll be called out in the changelog.
- All other framework additions are purely additive (new factories, new DSL entries, new operator, new `CSSEntry` case). No public API removed or renamed.

## Open questions deferred to plan-writing

1. Whether `SwiflowWeb` has an `after(_:)` / cancellable timer helper. If not, add a small one (likely in a new `SwiflowWeb/Timing.swift`).
2. Exact value-animation hook for `--accent` on increment: CSS-only via `@property` + a transition, or assist with a one-line view-transition wrap. Both work; pick during implementation based on what feels less noisy.
3. Whether the backdrop-click-to-close on `<dialog>` needs any care for nested click targets (Form is inside the dialog). Probably fine with `event.target === dialogElement`; verify.

These are implementation-detail questions, not design questions.

## Future work (separately specced)

- **Sidecar `.css` resource files** with framework-level scope rewrite. Real CSS files, no hashed names. Needs a small selector tokenizer and a `Bundle.module` resource smoke test under WASM.
- **True CSS Modules.** Build-time codegen producing `enum CounterStyles { static let card = "counter-card-a3f2" }`. Requires a build pipeline (Swift macro or Node-based) — significant project.
