# SwiflowUI

A small, accessible component library for Swiflow apps. Built so a freshly
scaffolded project can assemble a real UI without dropping to raw HTML for common
patterns — while staying CSS-first and token-driven.

- **Native-first.** Components are thin wrappers over semantic HTML (`<button>`,
  `<input>`, `<select>`, `<dialog>`, the Popover API), so roles, keyboard handling,
  and focus come from the platform. ARIA is added only where we depart from native.
- **Token-driven.** Every color, space, radius, border, and motion value reads a
  `--sw-*` custom property. Components never branch on user/device preferences — the
  token layer does (dark mode, contrast, reduced motion, …). See the
  [theming guide](swiflowui-theming.md).
- **Composes with the framework.** Two-way `Binding`, `Field`/`Form`, `@State`, and
  `embed { }` are the only state machinery — no new concepts.

## Installation

SwiflowUI ships in the Swiflow package. Add the product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "SwiflowDOM", package: "Swiflow"),
        .product(name: "SwiflowUI",  package: "Swiflow"),
    ]
)
```

```swift
import SwiflowUI
```

The design-token stylesheet injects itself the first time any component renders
(idempotent). To install it deterministically up front — e.g. before your first
`Swiflow.render` — call `SwiflowUI.installBaseStyles()`.

## Conventions

- **Stateless components are free functions** returning `VNode` (layout, Button,
  fields, feedback). They take trailing `Attribute...` that merge onto the root, and
  a caller `.class(_:)` is *merged* with the skin classes (so you extend, not
  replace). Don't pass `.value`/`.checked`/`.on(.input)` to a field — drive the value
  through its binding.
- **Stateful components are `@Component`s** behind a free-function facade (the
  overlays). You call them like any other component; they manage their own DOM.
- Values flow through **`Binding`** (`$state`) or a **`Field`** (binding + validators
  + touched state). Most controls offer both a `…: Binding` form and a `field:` form.

---

## Layout

```swift
VStack(spacing: .md, align: .stretch) { … }     // column
HStack(spacing: .md, align: .center) { … }       // row
Grid(columns: 3, spacing: .md) { … }             // equal columns; columns is Int or a track string
Spacer()                                          // flex filler (push items apart)
Divider()                                          // <hr>; Divider(.vertical) for a column rule
```

Stacks take postfix modifiers: `.padding(.lg)`, `.gap(.sm)`. `Grid(columns: "1fr 2fr")`
accepts any `grid-template-columns` value. Spacing is the `Spacing` scale
(`.xs/.sm/.md/.lg/.xl/.none`).

`.padding` takes an optional edge set as a second argument — `.padding(.lg, .horizontal)`,
`.padding(.sm, [.top, .leading])`. Edges are logical/RTL-aware (`Edge`: `.top`/`.bottom`/
`.leading`/`.trailing` plus the `.horizontal`/`.vertical`/`.all` presets, where `leading`/
`trailing` follow text direction). Chained calls compose per-edge, e.g.
`.padding(.md, .horizontal).padding(.sm, .vertical)` for 16px-horizontal / 8px-vertical.

### Container

```swift
Container { … }              // centered, max-width: --sw-container-md (60rem)
Container(size: .sm) { … }   // --sw-container-sm (40rem)
Container(size: .lg) { … }   // --sw-container-lg (80rem)
```

The page shell most apps wrap their content in: a stateless `<div>` that centers
itself (`margin-inline: auto`) once it hits its `max-width`, with `padding-inline:
--sw-space-md` keeping content off the viewport edge below that width. `size` maps
to one of the `--sw-container-{sm,md,lg}` tokens (`Theme.swift`; 40/60/80rem by
default) — re-point those tokens to retheme every `Container` in an app at once.

### Accordion

```swift
Accordion {
    AccordionItem("Shipping", open: true) { p("...") }
    AccordionItem("Returns") { p("...") }
}

Accordion(exclusive: true) {   // one open at a time — native <details name>
    AccordionItem("What is Swiflow?", open: true) { p("...") }
    AccordionItem("Is it accessible?") { p("...") }
}
```

Native `<details>`/`<summary>` disclosure — no JS. `AccordionItem` is a stateless
free function: a `<details class="sw-accordion__item">` wrapping a `<summary>` label
and a panel `<div>`; `open: true` sets its initial (and, since `<details>` is
uncontrolled, ongoing) expanded state. `Accordion` groups items in a
`.sw-accordion` container and is a thin `@Component` facade — it exists purely to
keep a stable id across re-renders (the `Tabs`/`Dropdown` `nextSwID`-in-`init`
precedent), not for any lifecycle of its own.

`exclusive: true` assigns every `<details>` child the SAME native `name` attribute,
so the platform enforces one-open-at-a-time — opening one closes the others, no
wiring on your end (`<details name>` grouping is Baseline 2024; unsupported browsers
just allow all items open together). Two `Accordion(exclusive: true)` instances
never share a group — each gets its own generated name.

## Typography

### Text

```swift
Text("Page title", variant: .title)          // <h1>
Text("Section heading", variant: .heading)    // <h2>
Text("Subsection", variant: .subheading)      // <h3>
Text("Body copy", variant: .body)             // <p> (the default variant)
Text("Fine print", variant: .caption, color: .muted)   // <p>, smaller
Text("Field label", variant: .label)          // <span>
```

`TextVariant` picks both the size/weight from the type scale and the semantic
tag rendered by default: `.title`→`h1`, `.heading`→`h2`, `.subheading`→`h3`,
`.body`/`.caption`→`p`, `.label`→`span`. Pass `tag:` to keep a variant's
styling but render a different element — e.g. a `.heading`-styled `Text` that
still needs to be the page's only `<h1>`:

```swift
Text("Styled as a heading, rendered as the page's h1", variant: .heading, tag: "h1")
```

`weight:` (`TextWeight`: `.regular`/`.medium`/`.semibold`) overrides the
variant's own weight when set; leave it `nil` (the default) to inherit the
variant's weight. `color:` (`TextColor`: `.standard`/`.muted`/`.accent`/
`.danger`/`.success`/`.warning`) tints the text with the matching token's
`-strong` variant; `.standard` (the default) emits no extra class and just
takes the base `--sw-text` color.

Named `Text` (capitalized) — the DSL's text-node factory is the lowercase
`text(_:)`, so there's no collision, and there's no SwiftUI/Foundation `Text`
on wasm to shadow.

The sizes, weights, and line-heights all come from tokens, so an app can
re-point the whole type scale: `--sw-font-size-xs/sm/md/lg/xl/2xl`,
`--sw-font-weight-regular/medium/semibold`, and `--sw-line-height` /
`--sw-line-height-tight`.

## Controls

### Button

```swift
Button("Save") { save() }
Button("Cancel", variant: .secondary, size: .sm) { dismiss() }
Button("Delete", variant: .danger, disabled: !canDelete) { delete() }
Button(variant: .danger, action: { delete() }) { trashIcon(); text("Delete") }  // builder label
Button(.attr("aria-label", "Close"), action: { close() }) { closeIcon() }       // icon-only: aria-label required (DEBUG warns)
Button("Submit", type: .submit)        // form button — renders type=submit, NO click action
```

`ButtonVariant`: `.primary` / `.secondary` / `.ghost` / `.danger` (destructive
solid fill — delete/remove confirms). `ControlSize`: `.sm/.md/.lg`.
The `type:` overload (`.submit`/`.reset`) is for a button the enclosing `<form>`
drives — it takes no action closure.

### Text fields

```swift
TextField("Name", text: $name)
TextField("Email", text: $email, type: .email, placeholder: "you@example.com")

// Field-integrated: pulls binding + error + blur→markTouched out of a Field
let email = Field("email", $email, $ctrl, .required(), .email)
TextField("Email", field: email, type: .email)
```

The `<label>` wraps the `<input>` (implicit association). On error the input gets
`aria-invalid` and the message renders with `role="alert"`. `TextFieldType`:
`text/email/password/number/search/tel/url`.

### TextArea

```swift
TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")

// Field-integrated: pulls binding + error + blur→markTouched out of a Field
let feedback = Field("feedback", $feedback, $ctrl, .required())
TextArea("Feedback", field: feedback, rows: 4)
```

A multi-line sibling of `TextField`: same `.sw-field` chrome (label wraps the
control, `aria-invalid` + `role="alert"` on error), over a native `<textarea>`
instead of `<input>`. `rows:` sets the native `rows` attribute (default `3`);
everything else — `size:`, `required:`, `disabled:`, caller attributes,
`onBlur:`/`field:` — matches `TextField`.

### NumberField

```swift
NumberField("Rating", value: $rating, min: 0, max: 10, step: 0.5)   // Binding<Double>
NumberField("Age", value: $age, min: 0, max: 120, step: 1)          // Binding<Int>
```

A native `<input type="number">` with the same `.sw-field` chrome as
`TextField`/`TextArea`. Two overloads share the lowering — one over
`Binding<Double>`, one over `Binding<Int>` — with `min`/`max`/`step` typed to
match; each is omitted from the rendered attributes when left `nil`. As with
`TextField`'s `.value`, a parse failure on the user's typed text leaves the
binding unchanged (the malformed text just stays in the DOM). There's no
`Field`-integrated overload: `Field`'s validators are string-typed today, so a
numeric `Field` has no natural home yet — validate by hand until that lands.

### Slider

```swift
Slider("Volume", value: $volume)                       // defaults to 0...1
Slider("Rating", value: $rating, in: 0...10, step: 1)
```

A native `<input type="range">` with the same `.sw-field` chrome as
`NumberField`, over a single `Binding<Double>`. `min`/`max` come from `in:`
(default `0...1`, formatted with the same trailing-`.0`-trimming rule as
`NumberField`); `step` is omitted from the rendered attributes when left
`nil`, leaving the browser's native stepping un-opinionated. There's no
`required:` (a range input always has a value) and no `Field`-integrated
overload, mirroring `NumberField`. The track/thumb are the browser's own —
only `accent-color` is styled, so it follows `--sw-accent` (and dark mode)
without a custom track/thumb reimplementation.

### Toggle, Checkbox

```swift
Toggle("Dark mode", isOn: $isDark)          // a switch (role=switch) for an immediate setting
Checkbox("I accept the terms", isOn: $ok)   // a checkbox for selection/confirmation
Checkbox("Subscribe", field: subscribeField)
```

`Toggle` is a switch (immediate effect, like a settings toggle); `Checkbox` is for
selection/confirmation (e.g. submitted with a form). Both have `field:` forms.

### Select, RadioGroup

```swift
Select("Color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"])
```

`Select` uses the 2026 customizable-select CSS (`appearance: base-select`) where
supported, with a native fallback. `RadioGroup` is a `<fieldset>`/`<legend>` with
roving focus. `options` take `SelectOption`s (string-literal-convertible). Both have
`field:` forms.

### ToggleButtonGroup

```swift
ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])          // single: exactly one pressed
ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])    // multi: toggles Set membership
```

A segmented control: `role="group"` of native `<button type="button"
aria-pressed>`, String-keyed like `RadioGroup`/`Select` (`options: [String]`, id ==
label). Two overloads — `Binding<String>` (single-select: exactly one button
pressed) and `Binding<Set<String>>` (multi-select: tapping toggles membership) —
share one private lowering. `aria-pressed` is the WAI-ARIA toggle-button pattern,
valid for both one and several simultaneously-pressed buttons. **No roving
focus** — each button keeps its own place in Tab order; for strict single-select
*with* roving, use `RadioGroup` (radio roving) or `Tabs` (tablist roving) instead.

## Feedback & display

```swift
Spinner()                                   // role=status; pauses under reduced-motion
ProgressView(value: 0.6)                     // native <progress>, value clamped 0…1
Card { h3("Title"); p("Body") }              // elevated surface (shadow)
Card(variant: .outlined) { … }               // bordered
Card(variant: .plain) { … }                  // the bare padded surface — no shadow, no border
Badge("New", variant: .accent)               // pill; .neutral/.accent/.info/.success/.warning/.danger
```

### Icon — a bring-your-own-SVG seam

```swift
Icon(checkSVG)                                       // decorative — aria-hidden, no role
Icon(checkSVG, size: .lg)                            // .sm 0.875em / .md 1em (default) / .lg 1.5em
Icon(checkSVG, .style("color", Token.accent.css))    // tinted — see below
Icon(closeSVG, label: "Close")                        // the icon IS the accessible name
```

There's no bundled icon set — apps bring their own `<svg>…</svg>` markup as a
trusted, hand-authored (or hand-copied) Swift string constant, not user input.
The js-driver builds every DOM node via `document.createElement`, which has no
SVG namespace, so an `element("svg")` VNode would render a dead
`HTMLUnknownElement`. `Icon` sidesteps that: it renders a `<span>`, sized in
`em`s so it tracks the surrounding text, filled with `background-color:
currentColor`, and clipped to the caller's SVG shape via CSS `mask`/
`-webkit-mask` on a percent-encoded data URI — the same technique the library
already uses for `.sw-dropdown__caret` and Select's `::picker-icon`.

Because a mask only carries alpha, the rendered icon is always exactly the
current text color — **single-color art only**. Tint an `Icon` with
`.style("color", Token.accent.css)`, or nest it under a colored parent; for
genuinely multi-color art (a two-tone logo, a colored illustration), render
the SVG directly via `rawHTML(_:)` instead — that escape hatch injects
trusted markup via `innerHTML`, bypassing both the mask and the
DOM-namespace limitation.

`label: nil` (the default) renders the icon as purely decorative
(`aria-hidden="true"`, no role) — use this when adjacent visible text already
conveys the meaning (a checkmark beside "Saved"). Pass `label:` when the icon
is the *only* conveyor of meaning, e.g. an icon-only button — it then renders
`role="img"` + `aria-label`, with no `aria-hidden`.

### Callout — a status banner

```swift
Callout("Changes saved.", variant: .success)
Callout("Your session will expire soon.", variant: .warning, title: "Heads up")
Callout("Couldn't reach the server.", variant: .danger) {
    Button("Retry") { retry() }
}
```

A stateless semantic banner — a bordered, soft-tinted `<div>` for a standing
in-page notice (unlike `Badge`'s compact pill or `Toast`'s transient queue
item). `title` is optional; the `actions` slot is only rendered when non-empty.
`CalloutVariant` (`.info`/`.success`/`.warning`/`.danger`) maps to `role`/`aria-live`
exactly like `ToastVariant`: `.danger` is assertive (`role="alert"`,
`aria-live="assertive"`), the other three are polite (`role="status"`,
`aria-live="polite"`). Pair it with `Icon` (above) for an icon in the banner.

### Skeleton

```swift
Skeleton(width: "2.5em", height: "2.5em", radius: "50%")   // avatar circle
Skeleton(height: "1.25em")                                  // a title-sized bar
Skeleton(lines: 3)                                          // paragraph placeholder; last line shortens
```

A stateless shimmering placeholder — Badge's shape (a skinned `<span>`) — for
content that hasn't loaded yet. Purely decorative: both variants render
`aria-hidden="true"`, since the real content supplies the accessible
semantics once it mounts. `radius` overrides the sheet's default
`border-radius` inline (e.g. `"50%"` for an avatar); omit it to inherit the
token-driven default. The shimmer animation gates on `animation-play-state:
var(--sw-anim-play)` — the exact `Spinner` precedent — so
`prefers-reduced-motion` freezes it into a static block for free, no
per-component code required.

### Avatar

```swift
Avatar("Ada Lovelace", src: "https://example.com/ada.png")   // <img>, sanitized src + alt=name
Avatar("Ada Lovelace")                                        // no src → "AL" initials
Avatar("Grace Hopper", size: .lg, shape: .rounded)             // ControlSize + AvatarShape
```

A user/entity picture — Badge's shape, sized via the shared `ControlSize`
(`.sm`/`.md`/`.lg`) scale. With `src`, renders an `<img>` — the URL folds
through `URLSanitizer` via `.src`, exactly like `TextLink`'s `href` (a
`javascript:` src is neutralized). Without `src`, renders a `<span role="img"
aria-label=name>` filled with `avatarInitials(name)` — the first letter of the
first up to two whitespace-separated words in `name`, uppercased (an
empty/whitespace-only `name` shows "?" rather than a blank label);
`role`/`aria-label` stand in for the `alt` text an `<img>` would otherwise
carry. `AvatarShape` (`.circle`/`.rounded`/`.square`) maps to a
`sw-avatar--<shape>` class. There's no automatic image-load-error fallback
(e.g. swapping to initials when `src` 404s) — that would need a load-failure
signal this stateless free function has no seam for; an app that needs it can
track the failure itself and re-render with a different `src`/`name`.

## Typed tokens

Reference `--sw-*` tokens by name and a typo fails at compile time — a
stringly `var(--sw-surfce)` fails silent in CSS:

```swift
div(.style("background", .surface),            // Token — typed, compile-checked
    .style("border-radius", .radius))
.style("border", "\(Token.borderWidth.css) solid \(Token.border.css)")  // composites interpolate .css

Theme(.set(.warning, "#b45309")) { … }         // override ANY typed token in a subtree
Theme(.accent("#7c3aed")) { … }                // the branded shortcuts still work
```

The vocabulary mirrors everything the base sheet ships (a CI test pins it);
app-custom properties keep the string spellings (`.style(_:_: String)`,
`ThemeToken.token(_:_:)`).

## Overlays

All three are accessible, token-driven, and animate via `@starting-style` /
`exitAnimation` (collapsing to instant under reduced motion). Dismissal is ESC +
explicit controls; `Alert` can additionally close on a backdrop click — opt in
with `dismissOnBackdrop: true` (detected via `EventInfo.isSelfTarget`).

### Modal — a general-purpose dialog

```swift
@State var showSettings = false

Button("Settings…") { showSettings = true }
Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
    // any content — fields, sections, whatever the caller needs
    Button("Close") { showSettings = false }
}
```

The general-purpose sibling of `Alert`/`Prompt`: same native `<dialog>.showModal()`
machinery, but no baked-in title-required/actions-slot shape — just an optional
`title` and arbitrary `content`. `size` (`.sm`/`.md`/`.lg`) controls the card's
max-width (`.md` is the shared chrome default, `28rem`). Unlike Alert/Prompt,
`dismissOnBackdrop` defaults to `true` — a generic modal is a casual overlay, so
clicking outside to leave is the expected affordance; pass `false` when the modal
guards unsaved work or otherwise needs a deliberate exit. Reach for `Alert` when you
need a confirm dialog, or `Prompt` for a single text-input dialog — both below.

### Alert — a modal `<dialog>`

```swift
@State var confirmDelete = false

Button("Delete…", variant: .secondary) { confirmDelete = true }
Alert("Delete this item?", isPresented: $confirmDelete, message: "This can't be undone.") {
    Button("Cancel", variant: .secondary) { confirmDelete = false }
    Button("Delete") { delete(); confirmDelete = false }
}
```

Bind `isPresented`; the alert drives the native `showModal()`/`close()` (top layer,
backdrop, focus trap, ESC — all native) and writes the binding back on close.

### Prompt — a modal text input

```swift
@State var name = "untitled"
@State var showRename = false

Button("Rename…") { showRename = true }
Prompt("Rename file", isPresented: $showRename, text: $name,
       message: "Enter a new name", placeholder: "untitled", confirmTitle: "Rename") { newName in
    rename(to: newName)     // fires on Enter or Rename only — not Cancel/ESC
}
```

Built on `<form method="dialog">`, so **Enter submits**. The input is a `TextField`,
labelled by `message`.

### Toast — a managed queue

```swift
@ReducerState var toasts: ToastQueue

Button("Save") { self.$toasts.show("Saved!", .success) }
ToastStack(queue: $toasts)         // mount once (e.g. at the app root)
```

`ToastQueue` is a `@ReducerState` reducer that owns the toast state; fire with
`send(.show(_:))`, clear one with `.dismiss(id)` or all with `.dismissAll`. It shows
at most `maxVisible` toasts (default 3, via `ToastQueue(maxVisible:)`); extras wait in a
FIFO queue and are promoted as visible ones dismiss. Duplicate toasts (same message +
variant) **coalesce** into a single entry with a `×N` recurrence badge instead of stacking.

Each toast auto-dismisses (default 4s) or via its ✕. Auto-dismiss pauses on hover/focus
(WCAG 2.2.1). `ToastVariant`: `.info`/`.success`/`.warning`/`.danger` (danger announces
assertively). `ToastPlacement` defaults to `.bottomTrailing`.

> `@ReducerState` is local per-component: mount `ToastStack` and hold the `ToastQueue`
> at your app root, then thread `$toasts.send` to children as needed — it's not a global
> presenter.

> The older `ToastStack(toasts: Binding<[ToastItem]>)` (an app-owned `[ToastItem]` you
> append to) is **deprecated** in favor of the reducer; it still works but has no cap,
> overflow, or coalescing.

> Toasts use a high `z-index`, not the top layer, so a toast can sit *under* a modal
> `<dialog>`. If you mount `ToastStack` inside a `container-type` element, place it as
> a sibling of that element — a query container is a containing block for the fixed
> stack.

### Popover — an anchored panel

```swift
Popover(placement: .bottom) {
    Button("Details…", variant: .secondary) {}
} content: {
    p("Extra information about this row.")
    embed { Link("/docs", "Learn more") }   // Link is a Component — embed it, like anywhere else
}
```

The general-purpose sibling of `Dropdown`: same native Popover-API recipe
(`popover="auto"` + CSS anchor positioning — top layer, native ESC + light-dismiss), but
no baked-in menu-item shape — any single trigger element reveals any caller content.
`placement` (`.top`/`.bottom`/`.leading`/`.trailing`) sets the panel's `position-area`
relative to the trigger. The `trigger` builder must yield exactly one element — Popover
wires `popovertarget`/`anchor-name` onto it, preserving its own classes/attrs untouched
(pass a styled `Button`, and its `sw-btn` skin survives). Caller `Attribute...`/`.class`
land on the panel.

> Light-dismiss and ESC-to-close are native (the Popover API), same as `Dropdown` — no
> handler wiring required.

> Anchor positioning is Baseline-newer (Chromium/Safari; not yet Firefox). Where it's
> unsupported the panel still opens (a centered popover), just not anchored to the
> trigger.

## Navigation

### TextLink

```swift
p { text("Read the "); TextLink("documentation", href: "https://example.com/docs"); text(" before you start.") }
TextLink("View on GitHub", href: "https://github.com", external: true)
```

A token-styled inline hyperlink — a plain `<a>`, not in-app routing. Named `TextLink`,
not `Link`: `SwiflowRouter.Link` already owns in-app (SPA) navigation, so a bare `Link`
would collide in any file importing both modules. `href` is sanitized automatically
(it folds through `URLSanitizer`, same as any other `.href`/`.src` DSL modifier), so a
`javascript:`/`data:` URL is neutralized rather than reaching the DOM. `external: true`
opens the link in a new tab and adds `rel="noopener noreferrer"` (reverse-tabnabbing
guard); `external: false` (the default) adds neither. Caller `Attribute...`/`.class`
merge onto the `<a>`, same convention as every other stateless control.

### Breadcrumbs

```swift
Breadcrumbs([
    Crumb("Home", href: "/"),
    Crumb("Products", href: "/products"),
    Crumb("Widgets", href: "/products/widgets"),
    Crumb("Blue Widget"),
])
```

A stateless `<nav aria-label="Breadcrumb">` wrapping an `<ol>` trail, one `<li>` per
`Crumb`. The LAST crumb is always the current page: it renders as plain text with
`aria-current="page"`, never a link — even if it was given an `href`, since the
current page shouldn't link to itself. A middle crumb with `href == nil` also
renders as plain text, but WITHOUT `aria-current` (only the last crumb is
"current"). Every other crumb renders a plain sanitized `<a>` (the `href` folds
through `URLSanitizer`, same as `TextLink`). Separators are pure CSS (an `::before`
on every non-first `<li>`), not DOM nodes.

Breadcrumbs deliberately does NOT depend on `SwiflowRouter` — it never renders a
Router `Link`, only plain anchors, so SwiflowUI stays usable without a router. An
app that wants in-app (SPA) navigation for its crumbs supplies its own wrapper
(its own `<a>`, or `SwiflowRouter.Link`) around the crumb data; `Breadcrumbs`
itself stays framework-agnostic. Caller `Attribute...`/`.class` merge onto the
`<nav>`.

### Tabs

```swift
@State var tab = "overview"
…
Tabs(selection: $tab) {
    Tab("Overview", id: "overview") { p("...") }
    Tab("Details", id: "details") { p("...") }
    Tab("Settings", id: "settings") { p("...") }
}
```

A WAI-ARIA `role="tablist"` bound to a `Binding<ID>` selection — `ID` can be any
`Hashable & Sendable` value (a `String`, an `enum`, whatever identifies your tabs).
Each `Tab(_:id:content:)` supplies a label, its id, and its panel content.

**Keyboard (automatic activation, horizontal only):** ←/→ move between tabs and
wrap; Home/End jump to the first/last. Moving focus IMMEDIATELY selects the
target tab — its panel swaps and focus follows in the same step, the APG
"automatic activation" pattern (as opposed to "manual activation", where focus
moves and a separate Enter/Space commits the selection). Tab is deliberately
NOT handled by the roving logic: it leaves the tablist for the next tabbable
element, same as everywhere else in Swiflow (handlers can't `preventDefault`,
so hijacking Tab isn't an option regardless).

**All tabs' panels render up front**, always — the inactive ones are simply
`hidden`, not omitted, so panel-local state and ARIA wiring (`aria-labelledby`,
`aria-controls`) stay stable across selection changes instead of being torn
down and rebuilt on every switch.

Caller `Attribute...`/`.class` merge onto the root `.sw-tabs` container. A
`.vertical` orientation variant is deferred to a future release.

## Forms

The controls integrate with the framework's `Field`/`Form` (see the
[forms guide](forms.md)). A `Field` bundles a binding, validators, and touched state;
the `field:` overloads wire the error display + blur→`markTouched` for you:

```swift
let email = Field("email", $email, $ctrl, .required(), .email)
let form  = Form($ctrl) { email }

TextField("Email", field: email, type: .email)
Button("Submit", disabled: !form.isValid) { form.touchAll(); if form.isValid { submit() } }
```

### Tooltip

A descriptive overlay shown on hover and keyboard focus. Wrap any trigger:

```swift
Tooltip("Delete permanently") { Button("Delete", variant: .danger) { delete() } }
Tooltip("Appears below", placement: .bottom) { Button("Below") {} }
```

CSS-only (no JS): `:hover`/`:focus-within` reveal a `role="tooltip"` bubble linked to the trigger
via `aria-describedby`. Placements: `.top` (default), `.bottom`, `.leading`, `.trailing`.

> Limitations (CSS-only): no Escape-to-dismiss (so it doesn't fully meet WCAG 1.4.13), and the
> bubble is not in the top layer, so an ancestor with `overflow: hidden` can crop it. For
> dismissable, top-layer overlays use `Dropdown`/Popover.

## DataTable

A declarative, accessible data table over a typed row model. Sort, multi-select,
pagination, sticky header, empty/loading states, and per-column alignment and width
are all driven by parameters and bindings — no subclassing or delegate pattern.

```swift
DataTable(people, selection: $selected, sortable: true, pageSize: 25) {
    Column("Name",   value: \.name)
    Column("Age",    value: \.age).align(.trailing)
    Column("Role")   { p in Badge(p.role, variant: .accent) }
    Column("") { p in Button("Edit", variant: .secondary, size: .sm) { edit(p) } }
}
```

`Row: Identifiable` rows use the short form above. For non-`Identifiable` rows supply
`id:` explicitly: `DataTable(rows, id: \.uuid, …) { … }`.

### Column model

**Value column** — pass a keypath to any `Comparable & CustomStringConvertible` value.
The column gets a default text cell *and* a comparator for sorting:

```swift
Column("Name", value: \.name)          // text cell + sortable
Column("Age",  value: \.age).align(.trailing)   // numeric, right-aligned
Column("Score", value: \.score).sortable(false) // text cell only, not sortable
```

**Custom-cell column** — trailing closure returns `[VNode]` (single-expression also
works, the `@ChildrenBuilder` unwraps it). No comparator; not sortable by default:

```swift
Column("Role") { p in Badge(p.role, variant: .info) }
Column("") { p in Button("Edit", variant: .secondary, size: .sm) { edit(p) } }
```

Mix a value-column comparator with a custom cell by chaining `.cell { }` after the
value initialiser:

```swift
Column("Score", value: \.score).cell { p in StarRating(p.score) }
```

**Modifiers** chain on any `Column`:

| Modifier | Effect |
|---|---|
| `.align(.leading / .center / .trailing)` | Logical text alignment (RTL-aware) |
| `.width(.px(80) / .auto / .custom("…"))` | Inline `width` hint |
| `.sortable(false)` | Remove the comparator from a value column |
| `.cell { … }` | Override the render, keep the comparator |

### Table knobs

```swift
DataTable(rows,
          selection: $selectedIDs,       // Binding<Set<Row.ID>>? — adds checkbox column
          sortable: true,                // Bool — enable header sort buttons
          sortOrder: $order,             // Binding<SortOrder?>? — controlled sort state
          pageSize: 25,                  // Int? — enables pagination
          page: $pageIndex,             // Binding<Int>? — opt-in controlled page
          onRowClick: { row in … },      // ((Row)->Void)? — whole-row click handler
          loading: false,               // Bool — shows Spinner in the body
          maxHeight: .custom("400px"),   // Spacing? — overflow container for sticky header
          emptyText: "No results") { … }
```

All bindings are optional. When omitted, sort and page self-manage internal `@State`.
`sortOrder` and `page` let you lift that state into the parent (e.g. to persist it or
drive server-side queries).

`SortOrder` carries `columnID: String` and `ascending: Bool`; `nil` means unsorted.
Sort cycles tri-state: ascending → descending → unsorted.

### Sticky header

The table header (`<thead>`) is `position: sticky; top: 0` inside the `.sw-table__scroll`
overflow container. **The header only pins while the table is actually scrolling.** Pass
`maxHeight:` to give the scroll container a bounded height:

```swift
// Header pins while you scroll the 400 px viewport.
DataTable(rows, maxHeight: .custom("400px")) { … }

// Without maxHeight the container never overflows, so the header just sits
// at the top of the flow — no sticky behaviour visible.
DataTable(rows) { … }
```

`Spacing` has no `.px` case — use `.custom("400px")`.

### Caveats

**Dynamic data needs a `key:`.** `DataTable` is an embedded component, so it is reused
across renders and captures `rows`, `loading`, `pageSize`, and the columns at **first
mount** — only the `selection`, `sortOrder`, and `page` bindings stay live. If your data
changes at runtime (a filter, a fetch, an upstream re-sort), the table will not update
unless you pass a `key:` that changes with the data, which remounts it with fresh rows:

```swift
// Filtered/fetched data: key changes with the data → table re-reads `rows`.
DataTable(filtered, selection: $selected,
          key: "people-\(filtered.count)-\(query)") {
    Column("Name", value: \.name)
}
```

Remounting resets the self-managed sort/page state; bind `sortOrder:`/`page:` if you need
those preserved across data changes. (Static data — a `let` array that never changes —
needs no `key:`.)

A keyed `DataTable` is a *keyed* child, and Swiflow requires siblings to be all-keyed or
all-unkeyed. If the table sits beside unkeyed siblings (a heading, a filter control), give
it its own single-child container so it isn't mixed with them:

```swift
VStack {
    h2("People")
    Select("Role", selection: $role, options: roles)
    VStack {                                  // isolates the keyed table
        DataTable(filtered, key: "people-\(role)") { … }
    }
}
```

**Row-click + interactive cells.** Swiflow handlers cannot stop event propagation.
A click on an in-cell `Button` also fires `onRowClick`. Avoid combining `onRowClick`
with buttons or links inside cells; use one or the other:

```swift
// Fine — action is only in the button, no onRowClick.
Column("") { p in Button("Edit", variant: .secondary, size: .sm) { edit(p) } }

// Fine — whole-row is clickable, cells are display-only.
DataTable(rows, onRowClick: { select($0) }) {
    Column("Name", value: \.name)
}

// Avoid — button click also fires onRowClick.
DataTable(rows, onRowClick: { select($0) }) {
    Column("") { p in Button("Edit") { edit(p) } }   // both fire
}
```

### Virtualization

For large datasets, opt into windowed rendering — only the rows in (and just around) the
viewport stay in the DOM:

```swift
DataTable(people, sortable: true,
          maxHeight: .custom("440px"),          // required: the scroll container
          virtualization: .fixed(rowHeight: 44), // constant row height
          columnsTemplate: "2fr 80px 1fr") {     // required: shared column track sizes
    Column("Name", value: \.name)
    Column("Age", value: \.age).align(.trailing)
    Column("Role") { p in Badge(p.role, variant: .accent) }
}
```

- **`columnsTemplate` is required for stable columns.** Virtualized rows are CSS grid rows
  sharing one `grid-template-columns`, so per-column `.width` is ignored. `fr` units are valid
  here. When a selection checkbox column is present, a `min-content` track is auto-prepended.
- **`maxHeight` is required.** It is the scroll container the window is measured against;
  without it the table falls back to rendering every row.
- **Virtualization replaces pagination.** If you set both `virtualization:` and `pageSize:`,
  virtualization wins and no pager is shown.
- **Dynamic data still needs a changing `key:`** — rows freeze at first mount (embed reuse).
- Fixed row height only in this release; variable/measured heights are future work.

### Deferred

Density/zebra-stripe variants, column resize, full ARIA-grid keyboard roving (`role=grid`,
arrow-key cell focus), totals/summary row, and server-side sort are not in this version.
Variable/measured row heights and a standalone virtualized `List` are also deferred.

## Accessibility

Native elements carry their own semantics; SwiflowUI adds: `aria-invalid` + `role=alert`
errors on fields, `role=switch` on Toggle, `role=radiogroup` + roving focus on
RadioGroup, `role=status`/live regions on Spinner and Toast (`role=alert` for danger),
`role=alertdialog` + `aria-labelledby`/`aria-describedby` on Alert. Every animation
honors `prefers-reduced-motion`; overlays honor `prefers-reduced-transparency`.

## Theming

Re-skin everything by overriding `--sw-*` tokens (no component changes), and dive
deeper with `#css`. See the [theming guide](swiflowui-theming.md).
