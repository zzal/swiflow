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

## Controls

### Button

```swift
Button("Save") { save() }
Button("Cancel", variant: .secondary, size: .sm) { dismiss() }
Button("Delete", variant: .ghost, disabled: !canDelete) { delete() }
Button("Submit", type: .submit)        // form button — renders type=submit, NO click action
```

`ButtonVariant`: `.primary` / `.secondary` / `.ghost`. `ControlSize`: `.sm/.md/.lg`.
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

## Feedback & display

```swift
Spinner()                                   // role=status; pauses under reduced-motion
ProgressView(value: 0.6)                     // native <progress>, value clamped 0…1
Card { h3("Title"); p("Body") }              // elevated surface (shadow)
Card(variant: .outlined) { … }               // bordered
Badge("New", variant: .accent)               // pill; .neutral/.accent/.danger/.success
```

## Overlays

All three are accessible, token-driven, and animate via `@starting-style` /
`exitAnimation` (collapsing to instant under reduced motion). Dismissal is ESC +
explicit controls (click-outside isn't wired — the framework can't yet expose the
event target).

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

### Toast — an app-owned queue

```swift
@State var toasts: [ToastItem] = []

Button("Save") { toasts.append(ToastItem("Saved!", variant: .success)) }
ToastStack(toasts: $toasts)        // mount once (e.g. at the app root)
```

The app owns the array; fire by appending. Each toast auto-dismisses (default 4s) or
via its ✕ and removes itself. Auto-dismiss pauses on hover/focus (WCAG 2.2.1).
`ToastVariant`: `.info`/`.success`/`.danger` (danger announces assertively).
`ToastPlacement` defaults to `.bottomTrailing`.

> Toasts use a high `z-index`, not the top layer, so a toast can sit *under* a modal
> `<dialog>`. If you mount `ToastStack` inside a `container-type` element, place it as
> a sibling of that element — a query container is a containing block for the fixed
> stack.

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
| `.width(.px(80) / .fr(2) / .auto / .custom("…"))` | Inline `width` hint |
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

### Deferred

Virtualization (windowed rendering for large datasets), density/zebra-stripe variants,
column resize, full ARIA-grid keyboard roving (`role=grid`, arrow-key cell focus),
totals/summary row, and server-side sort are not in this version. The pagination +
`maxHeight` scroll container is the current strategy for large-but-bounded datasets.

## Accessibility

Native elements carry their own semantics; SwiflowUI adds: `aria-invalid` + `role=alert`
errors on fields, `role=switch` on Toggle, `role=radiogroup` + roving focus on
RadioGroup, `role=status`/live regions on Spinner and Toast (`role=alert` for danger),
`role=alertdialog` + `aria-labelledby`/`aria-describedby` on Alert. Every animation
honors `prefers-reduced-motion`; overlays honor `prefers-reduced-transparency`.

## Theming

Re-skin everything by overriding `--sw-*` tokens (no component changes), and dive
deeper with `#css`. See the [theming guide](swiflowui-theming.md).
