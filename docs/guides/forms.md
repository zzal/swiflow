# Forms in Swiflow

Phase 7 ships the primitives a controlled-input form needs:

- `.value(_:Binding<String|Int|Double>)` — two-way bind a text/number input.
- `.checked(_:Binding<Bool>)` — two-way bind a checkbox.
- `.selection(_:Binding<String>)` — two-way bind a `<select>`.
- `Ref<JSObject>` + `.ref(_:)` — direct DOM access for `focus()`, scroll, etc.
- `.on(.input)` / `.on(.change)` / `.on(.blur)` / `.on(.submit)` — event hooks.

This guide is a recipe collection, not a framework. A higher-level
`Field` / `Form` layer with reusable validators arrives in Phase 12 — for
now, controlled inputs plus a few `@State` fields and a handler is the
recommended path.

> **HMR preserves form state.** When you save a Swift source file while `swiflow dev` is running, the runtime captures the current `@State` values (including everything bound to a `.value($text)` or `.checked($flag)`) before re-importing the new module, then restores them into the freshly-mounted tree. Typing in a form, saving a render tweak, and watching the field's value survive is the centerpiece demo of Phase 8.

All examples assume:

```swift
import Swiflow
import SwiflowWeb
import JavaScriptKit
```

## Hello forms

The minimum controlled input — type a letter, see it appear in the
heading.

```swift
final class Greeter: Component {
    @State var text: String = ""

    var body: VNode {
        div {
            h1("Hello, \(text.isEmpty ? "World" : text)!")
            input(.value($text))
        }
    }
}
```

`.value($text)` writes `text` into the element's `value` property on
every render and registers an `input` listener that calls `text = …`
when the user types. The `$text` projected value comes from the
`@State` property wrapper.

## Numeric inputs

`.value(_:)` is overloaded on `Binding<Int>` and `Binding<Double>` for
`<input type="number">`. Parse failure (`"abc"` in a numeric field) is
**silently ignored** — the binding keeps its previous value, the
DOM keeps the user's malformed text. They reconcile on the next
successful parse.

```swift
final class AgeForm: Component {
    @State var age: Int = 0
    @State var bmi: Double = 22.5

    var body: VNode {
        div {
            label("Age",      .attr("for", "age"))
            input(.id("age"), .attr("type", "number"), .value($age))

            label("BMI",      .attr("for", "bmi"))
            input(.id("bmi"), .attr("type", "number"), .attr("step", "0.1"), .value($bmi))

            p("You entered: age=\(age), bmi=\(bmi)")
        }
    }
}
```

If you need to validate "is this a number?", reach for a `Binding<String>`
plus your own parse step on `.on(.blur)` — see Validation on blur below.

## Checkboxes

`.checked(_:Binding<Bool>)` is the checkbox equivalent. It writes the
`checked` DOM property and listens for `change`.

```swift
final class Settings: Component {
    @State var darkMode: Bool = false

    var body: VNode {
        label(.class("checkbox-row")) {
            input(.attr("type", "checkbox"), .checked($darkMode))
            VNode.text(" Enable dark mode")
        }
    }
}
```

Note the `label`-wraps-`input` pattern — clicking the label toggles
the checkbox, which is the standard HTML accessibility idiom.

## Single-select

`<select>` works with `.selection(_:Binding<String>)`. Each `option`
carries its underlying form value via `.attr("value", …)`.

```swift
final class Picker: Component {
    @State var color: String = "blue"

    var body: VNode {
        div {
            select(.selection($color)) {
                option("Red",   .attr("value", "red"))
                option("Green", .attr("value", "green"))
                option("Blue",  .attr("value", "blue"))
            }
            p("You picked: \(color)")
        }
    }
}
```

Multi-select (`<select multiple>` → `Binding<[String]>`) lands in
Phase 12 with the rest of the form framework. For now, render a list
of `input(type: "checkbox")` rows backed by a `@State var selected: Set<String>`.

## Refs — direct DOM access

When you need to call a DOM method that bindings don't cover — `focus()`,
`scrollIntoView()`, reading an uncontrolled element's value — use a `Ref`.

```swift
final class Login: Component {
    @State var username: String = ""
    let usernameInput = Ref<JSObject>()

    var body: VNode {
        div {
            label("Username", .attr("for", "u"))
            input(.id("u"), .value($username), .ref(usernameInput))
        }
    }

    func onAppear() {
        _ = usernameInput.wrappedValue?.focus.function?()
    }
}
```

`Ref<JSObject>.wrappedValue` is `nil` before mount and after unmount.
`onAppear()` is the earliest lifecycle hook where the DOM node exists,
so it's the right spot for autofocus.

Phase 7 ships `Ref<JSObject>` as the only resolved generic; future
typed wrappers like `Ref<HTMLInputElement>` will arrive without an ABI
break.

## Validation on blur

A common UX pattern: don't shout at the user mid-type — wait until
they tab away. `.on(.blur)` fires when the input loses focus. Combine
it with a separate `@State` field for the error message.

```swift
final class EmailForm: Component {
    @State var email: String = ""
    @State var error: String?

    var body: VNode {
        div {
            label("Email", .attr("for", "e"))
            input(
                .id("e"),
                .attr("type", "email"),
                .value($email),
                .on(.blur) { self.validate() }
            )
            if let error {
                p(error, .class("error"))
            }
        }
    }

    func validate() {
        if email.isEmpty {
            error = "Email is required."
        } else if !email.contains("@") {
            error = "That doesn't look like an email."
        } else {
            error = nil
        }
    }
}
```

A few notes on this pattern:

- The validator is a plain method. No framework, no schema — just
  Swift you can unit-test directly.
- Re-render after `validate()` is automatic: `@State var error` is the
  reactivity trigger.
- For inline ("while typing") feedback, swap `.on(.blur)` for
  `.on(.input)` — but expect users to find it noisy.

## Composing fields

Real forms have multiple inputs and a submit gate. The Swiflow idiom
is: one `@State` per field, derived computeds for cross-field state.

```swift
final class SignUp: Component {
    @State var name: String = ""
    @State var email: String = ""
    @State var agreed: Bool = false

    var canSubmit: Bool {
        !name.isEmpty && email.contains("@") && agreed
    }

    var body: VNode {
        div(.class("container")) {
            h2("Sign up")

            div {
                label("Name", .attr("for", "n"))
                input(.id("n"), .value($name))
            }

            div {
                label("Email", .attr("for", "e"))
                input(.id("e"), .attr("type", "email"), .value($email))
            }

            label {
                input(.attr("type", "checkbox"), .checked($agreed))
                VNode.text(" I agree to the terms")
            }

            button(
                "Create account",
                .attr("disabled", !canSubmit),
                .on(.click) { self.submit() }
            )
        }
    }

    func submit() {
        // Send name + email to your API.
    }
}
```

Two things to notice:

- `canSubmit` is a plain computed `Bool`. Because it reads `@State`
  properties, it recomputes on every render — which is exactly when
  the disabled-state needs to be re-evaluated.
- `.attr("disabled", Bool)` uses the boolean attribute overload —
  passing `false` removes the attribute entirely, matching HTML's
  boolean-attribute semantics.

## What's next

Phase 12 ships a higher-level `Field` / `Form` framework with reusable
validators, async submit, server-error reconciliation, and field-level
focus tracking. Until then, the pattern above — controlled inputs,
`@State` per field, plain Swift validators, `.on(.blur)` for
non-noisy feedback — is the recommended path. It's a small enough
amount of code that "graduate to the framework later" is a real
option, not a rewrite.
