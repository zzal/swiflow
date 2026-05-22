# Swiflow Phase 12b — Form Validation Design

## Goal

Ship a form validation framework that lets components validate user input, track touched/dirty state, and coordinate multi-field submit/reset — without leaving Swift or adding new WASM dependencies.

---

## Section 1 — Architecture

### New files

| File | Responsibility |
|---|---|
| `Sources/Swiflow/Forms/Validator.swift` | `Validator<Value>` struct + static factory methods |
| `Sources/Swiflow/Forms/Field.swift` | `Field<Value>` struct — binding, validators, touched, error |
| `Sources/Swiflow/Forms/FormController.swift` | `FormController` struct — persistent touched state |
| `Sources/Swiflow/Forms/Form.swift` | `Form` struct + `@FieldBuilder` result builder |
| `Tests/SwiflowTests/Forms/FormTests.swift` | Unit tests |

### No modified files in `SwiflowWeb`

All four types are pure Swift value types with no JavaScriptKit dependency. They live entirely in `Sources/Swiflow/Forms/` and are tested without a WASM build.

### Two-tier coordinator pattern

Form state is split into two roles:

- **`FormController`** — a `@State`-backed value type that persists across renders. Holds only `touched: Set<String>` — the minimal mutable state that must survive re-renders.
- **`Form`** — an ephemeral struct assembled in `body` from `Field` instances. Holds type-erased closures for `reset()`, `isDirty`, and validation. Rebuilt on every render; never stored.

This mirrors the existing `@State` / computed-in-body pattern throughout Swiflow.

---

## Section 2 — `Validator<Value>`

```swift
public struct Validator<Value>: Sendable {
    let validate: @Sendable (Value) -> String?   // nil = valid; non-nil = error message
}
```

### Built-in validators (constrained to `String`)

```swift
extension Validator where Value == String {
    static func required(message: String = "Required") -> Validator<String>
    static func minLength(_ n: Int, message: String? = nil) -> Validator<String>
    // default message: "Must be at least \(n) characters"
    static func maxLength(_ n: Int, message: String? = nil) -> Validator<String>
    // default message: "Must be at most \(n) characters"
    static var email: Validator<String>
    // default message: "Invalid email address"
    static func regex(_ pattern: some RegexComponent, message: String) -> Validator<String>
}
```

### Custom validator (any `Value`)

```swift
extension Validator {
    static func custom(_ message: String, _ check: @escaping @Sendable (Value) -> Bool) -> Validator<Value>
    // check returning false → message shown; true → valid
}
```

### Validator ordering

Validators run in declaration order. The first failure wins — subsequent validators are not evaluated. This means `.required` must come before `.minLength` to show "Required" on an empty field rather than "Must be at least N characters".

---

## Section 3 — `FormController`

```swift
public struct FormController: Sendable {
    public var touched: Set<String>
    package var initialSnapshots: [String: AnyInitialValue]  // type-erased initial values

    public init() {
        touched = []
        initialSnapshots = [:]
    }
}
```

`AnyInitialValue` is a package-internal type-erased wrapper that stores the initial value and a closure to check equality and reset the binding. Used as `@State var ctrl = FormController()` on the component.

The persistent form state is: (1) which field keys have been touched, and (2) the initial value snapshot for each key (captured on first render). Everything else — validation results, closures — lives in the ephemeral `Form` struct.

---

## Section 4 — `Field<Value>`

```swift
public struct Field<Value>: Sendable where Value: Sendable {
    public let binding: Binding<Value>    // two-way binding to the @State value
    public let touched: Bool              // read from FormController via key
    public var error: String?             // nil if valid OR if !touched
    public var isValid: Bool              // runs validators regardless of touched
    public var isDirty: Bool              // current value != initial value (requires Value: Equatable)

    public func markTouched()             // inserts key into FormController.touched
}
```

### Construction

```swift
Field<Value>(
    _ key: String,
    _ binding: Binding<Value>,
    _ ctrl: Binding<FormController>,
    _ validators: Validator<Value>...
)
```

The `Field` captures `binding.get()` as its **initial value** on first construction — specifically when `ctrl.touched` does not yet contain `key`. On subsequent renders where `key` is already in `touched`, the captured initial value comes from the `FormController`'s stored snapshot (see Section 5).

### `error` vs `isValid`

- `error` — returns the first validator failure message only when `touched == true`. Nil if untouched (even if invalid). Nil if all validators pass.
- `isValid` — runs all validators regardless of `touched`. Used by `Form.isValid` to gate submit.

### Blur wiring (manual)

`touched` is set to `true` by calling `markTouched()`. The component wires this to `.on(.blur)`:

```swift
input(.value(pw.binding), .on(.blur) { pw.markTouched() })
if pw.touched, let err = pw.error { p(.class("field-error"), err) }
```

There is no automatic blur detection in Phase 12b — the caller wires it explicitly. This keeps `Field` pure and avoids hidden event handler registration.

---

## Section 5 — `Form` coordinator

```swift
public struct Form: Sendable {
    public var isValid: Bool
    public var isDirty: Bool
    public func touchAll()
    public func reset()
}
```

### Construction with `@FieldBuilder`

```swift
let form = Form {
    pw    // Field<String>
    em    // Field<String>
    agree // Field<Bool>
}
```

`@FieldBuilder` is a result builder that accepts heterogeneous `Field<Value>` instances and type-erases them into `[AnyField]`. Each `AnyField` holds:

- `key: String`
- `isValid: Bool` (computed at Form construction time)
- `isDirtyCheck: () -> Bool` (closure capturing binding + initial value)
- `resetAction: () -> Void` (closure: `binding.set(initialValue)`)
- `touchAction: (inout FormController) -> Void` (closure: `ctrl.touched.insert(key)`)

### Initial value capture

`Form` captures each field's initial value at construction time using a two-step approach:

1. On the **first render** (when `ctrl.touched` is empty for a given key), `Field.init` snapshots `binding.get()` as the initial value and stores it in `FormController` via a type-erased `[String: InitialSnapshot]` dictionary.
2. On **subsequent renders**, `Field.init` reads the stored snapshot from `FormController` to reconstruct the `isDirtyCheck` and `resetAction` closures consistently.

`FormController` therefore holds two things: `touched: Set<String>` and `initialSnapshots: [String: any Sendable]` (type-erased).

### `isValid`

```swift
var isValid: Bool { fields.allSatisfy { $0.isValid } }
```

Runs all validators synchronously. No async validators in Phase 12b.

### `isDirty`

```swift
var isDirty: Bool { fields.contains { $0.isDirtyCheck() } }
```

Each `isDirtyCheck` closure captures the binding and initial value at Form construction time. Requires `Value: Equatable` — enforced at `Field` construction via a conditional conformance.

### `touchAll()`

Sets `ctrl.touched` to include all registered field keys, triggering a re-render that reveals all error messages simultaneously:

```swift
func touchAll() {
    fields.forEach { $0.touchAction(&ctrl) }
    ctrlBinding.set(ctrl)
}
```

### `reset()`

Restores all field bindings to their initial values and clears `FormController.touched`:

```swift
func reset() {
    fields.forEach { $0.resetAction() }
    ctrlBinding.set(FormController())   // clears touched + keeps initialSnapshots
}
```

After `reset()`, `FormController.initialSnapshots` is preserved (the initial values themselves don't change — only the current values reset to them).

### Full usage pattern

```swift
final class SignUp: Component {
    @State var password = ""
    @State var email    = ""
    @State var ctrl     = FormController()

    var body: VNode {
        let pw = Field("password", $password, $ctrl, .required, .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let em = Field("email",    $email,    $ctrl, .required, .email)
        let form = Form { pw; em }

        div {
            input(.value(pw.binding), .on(.blur) { pw.markTouched() })
            if pw.touched, let err = pw.error { p(.class("field-error"), err) }

            input(.value(em.binding), .on(.blur) { em.markTouched() })
            if em.touched, let err = em.error { p(.class("field-error"), err) }

            button("Submit", .disabled(!form.isValid),
                .on(.click) {
                    form.touchAll()
                    guard form.isValid else { return }
                    // proceed with submission
                })
            button("Reset", .on(.click) { form.reset() })
        }
    }
}
```

---

## Section 6 — Testing Strategy

### Unit tests (`Tests/SwiflowTests/Forms/FormTests.swift`)

**Validator tests:**
- `.required` — rejects `""`, accepts `"a"`
- `.minLength(3)` — rejects `"ab"`, accepts `"abc"` and `"abcd"`
- `.maxLength(3)` — rejects `"abcd"`, accepts `"abc"` and `"ab"`
- `.email` — accepts `"a@b.com"`, rejects `"notanemail"` and `"@b.com"`
- `.regex(/^\d+$/, message: "Digits only")` — accepts `"123"`, rejects `"abc"`
- `.custom("Bad") { $0 == "bad" }` — rejects `"bad"`, accepts anything else
- Validator ordering: `.required` before `.minLength(3)` on `""` → "Required" not minLength message

**Field tests:**
- `error` is nil when `touched == false` even if invalid
- `error` is non-nil when `touched == true` and invalid
- `error` is nil when `touched == true` and valid
- `isValid` is false when invalid regardless of `touched`
- `markTouched()` sets `ctrl.touched` to include key
- `isDirty` is false when value matches initial, true after mutation

**Form tests:**
- `form.isValid` — false if any field invalid
- `form.isValid` — true when all fields valid
- `form.isDirty` — false before any mutation, true after one field changes
- `form.touchAll()` — all fields report `touched == true` after call
- `form.reset()` — all field values restored to initial; `ctrl.touched` cleared
- `form.reset()` followed by `form.isDirty` → false

### Integration

`examples/HelloWorld/Sources/App/App.swift` gains a `SignIn` component demonstrating:
- Two fields: email + password with validators
- Error messages shown on blur
- Submit button disabled until `form.isValid`
- `touchAll()` on submit attempt to reveal all errors
- Reset button

---

## Section 7 — Design Decisions

| Question | Decision |
|---|---|
| `Field` API shape | Plain struct wrapping `Binding` (Option B) — no new property wrapper |
| Form coordinator | Two-tier: `@State var ctrl = FormController()` + ephemeral `Form` struct |
| Touched wiring | Manual `.on(.blur) { field.markTouched() }` — explicit, no hidden handlers |
| Async validators | Out of scope for Phase 12b |
| Error display | Caller renders errors — no `FieldError` helper component in Phase 12b |
| Custom validators | `.custom("message") { value in Bool }` — any `Value` type |
| Built-in validators | Constrained to `String` — all HTML inputs produce strings |
| Initial value capture | Stored in `FormController.initialSnapshots` on first `Field` construction |
| `isDirty` requirement | `Value: Equatable` — enforced at `Field` construction |
