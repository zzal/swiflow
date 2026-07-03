# Styling components

Swiflow offers two first-class ways to write component-scoped CSS. Both
produce a `CSSSheet`, compose with `+`, and inject as a `<style>` element
scoped to the component's `.swiflow-<TypeName>` root class.

## `#css` — real CSS (recommended if you know CSS)

```swift
extension QuakesPage {
    static var scopedStyles: CSSSheet? = #css("""
        :host {
          display: block;
          max-width: 860px;
        }
        .quake-row {
          display: grid;
          gap: var(--sw-space-md);

          .when { color: gray; }       /* nesting works */
          &:hover { background: var(--sw-surface); }
        }
        @media (max-width: 600px) {
          .quake-row { grid-template-columns: 1fr; }
        }
        """)
}
```

The macro validates **structure** at compile time — unbalanced braces, a
missing `:` in a declaration, or `@import` are compile errors pointing at
the literal. It deliberately validates nothing else: property names, values,
and selectors pass through to the browser verbatim, so new CSS features work
the day a browser ships them.

### Scoping contract

The sheet body is emitted as `.swiflow-<TypeName> { …your CSS… }` and the
browser's native CSS nesting performs the scoping:

- `:host { … }` (or top-level `&`) styles the component's **root element**.
- Every other top-level selector matches **descendants** of the root.
- `:root`, `html`, and `body` rules escape scoping entirely.
- `@keyframes`, `@font-face`, and `@property` (and the other non-nestable
  at-rules: `@page`, `@counter-style`, `@font-feature-values`, `@layer`
  statements) are hoisted outside the scope wrapper. `@keyframes` names are
  **global** — prefix them, e.g. `mc-spin` not `spin`.

Two practical notes:

- The root element's **inline styles win** over `:host` rules, as everywhere
  in CSS — if your component's root is a `VStack`, its flex layout comes from
  inline styles and a `:host { display: block; }` won't override it.
- `:host(<sel>)` compiles to `&:is(<sel>)` inside the scope wrapper, so it
  carries one class-level more specificity than real Shadow-DOM `:host()`.

### Quotes and backslashes

Write `#css` with **multiline `"""` literals**, where `"` needs no escaping:

```swift
static var scopedStyles: CSSSheet? = #css("""
    a::after { content: "→"; }
    """)
```

Backslashes pass through to CSS verbatim — CSS escapes like
`content: "\2014"` work as written; Swift escape cooking (`\n`, `\u{…}`)
does not happen. In a *single-line* literal, Swift's `\"` reaches the CSS
parser as backslash-quote and fails structural validation — use a multiline
or raw (`#"…"#`) literal instead.

### Dynamic values

`#css` takes a static literal — no string interpolation. Route dynamic
values through CSS custom properties, which also update without re-injecting
the sheet:

```swift
// set on the node (.cssVar is an intent-revealing alias for .style):
div(.class("badge")).cssVar("--badge-color", magColor)
```

```css
/* read in the static sheet: */
.badge { color: var(--badge-color); }
```

## `css { }` — the builder DSL

The original result-builder DSL remains fully supported:

```swift
static var scopedStyles: CSSSheet? = css {
    host(.display("block"))
    rule(".quake-row",
         .display("grid"),
         .gap("var(--sw-space-md)"),
         .property("grid-template-columns", "5.5rem 1fr max-content"))
}
```

Property declarations (`color`, `padding`, `display`, …) are static members
of `CSSDeclaration`, consumed via leading-dot (implicit-member) syntax in
argument position — the parameter type supplies the context, so no
`CSSDeclaration.` prefix is needed. Static members keep the 72 single-word
property names off the module's top-level namespace, and argument position
(rather than a closure body) means a leading-dot line can never be mis-parsed
as a postfix continuation of the previous statement.

One scoping difference to know when migrating: for a class-leading selector
the DSL emits both `.swiflow-X.foo` *and* `.swiflow-X .foo` (root-or-
descendant), while `#css` is descendant-only — style the root explicitly
with `:host`.

## Mixing both

Sheets compose regardless of how they were written:

```swift
static var scopedStyles: CSSSheet? = #css("""
    .layout { display: grid; }
    """) + sharedBadgeStyles   // a css { } sheet from elsewhere
```
