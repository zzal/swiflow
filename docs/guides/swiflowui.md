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

## Accessibility

Native elements carry their own semantics; SwiflowUI adds: `aria-invalid` + `role=alert`
errors on fields, `role=switch` on Toggle, `role=radiogroup` + roving focus on
RadioGroup, `role=status`/live regions on Spinner and Toast (`role=alert` for danger),
`role=alertdialog` + `aria-labelledby`/`aria-describedby` on Alert. Every animation
honors `prefers-reduced-motion`; overlays honor `prefers-reduced-transparency`.

## Theming

Re-skin everything by overriding `--sw-*` tokens (no component changes), and dive
deeper with `#css`. See the [theming guide](swiflowui-theming.md).
