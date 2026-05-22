# Swiflow Phase 12b — Form Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pure-Swift form validation framework (`Validator`, `Field`, `FormController`, `Form`) with no JavaScriptKit dependency, unit tests, and a `SignIn` demo in HelloWorld.

**Architecture:** Two-tier coordinator: `@State var ctrl = FormController()` persists `touched: Set<String>` and initial-value snapshots across renders; `Form` is an ephemeral struct assembled in `body` that type-erases the fields via `@FieldBuilder` and provides `isValid`, `isDirty`, `touchAll()`, and `reset()`. `Field<Value>` snapshots `binding.get()` into `FormController.initialSnapshots` on first construction (side effect that triggers one extra render per field key — acceptable). Everything lives in `Sources/Swiflow/Forms/`; zero changes to `SwiflowWeb`.

**Tech Stack:** Swift 6, Swift Testing (`@Suite`/`@Test`/`#expect`), pure `Swiflow` module (no JavaScriptKit)

---

### Task 1: `Validator<Value>` + tests

**Files:**
- Create: `Sources/Swiflow/Forms/Validator.swift`
- Create: `Tests/SwiflowTests/Forms/FormTests.swift` (Validator section only)

- [ ] **Step 1: Write the failing validator tests**

Create `Tests/SwiflowTests/Forms/FormTests.swift`:

```swift
import Testing
@testable import Swiflow

@Suite("Forms")
struct FormTests {

    @Suite("Validator")
    struct ValidatorTests {

        @Test(".required rejects empty string")
        func requiredRejectsEmpty() {
            #expect(Validator.required().validate("") == "Required")
        }

        @Test(".required accepts non-empty string")
        func requiredAcceptsNonEmpty() {
            #expect(Validator.required().validate("a") == nil)
        }

        @Test(".minLength rejects short string")
        func minLengthRejectsShort() {
            #expect(Validator.minLength(3).validate("ab") == "Must be at least 3 characters")
        }

        @Test(".minLength accepts string at or above threshold")
        func minLengthAcceptsAtThreshold() {
            #expect(Validator.minLength(3).validate("abc") == nil)
            #expect(Validator.minLength(3).validate("abcd") == nil)
        }

        @Test(".maxLength rejects long string")
        func maxLengthRejectsLong() {
            #expect(Validator.maxLength(3).validate("abcd") == "Must be at most 3 characters")
        }

        @Test(".maxLength accepts string at or below limit")
        func maxLengthAcceptsAtLimit() {
            #expect(Validator.maxLength(3).validate("abc") == nil)
            #expect(Validator.maxLength(3).validate("ab") == nil)
        }

        @Test(".email accepts valid address")
        func emailAcceptsValid() {
            #expect(Validator<String>.email.validate("a@b.com") == nil)
        }

        @Test(".email rejects invalid addresses")
        func emailRejectsInvalid() {
            #expect(Validator<String>.email.validate("notanemail") != nil)
            #expect(Validator<String>.email.validate("@b.com") != nil)
        }

        @Test(".regex accepts matching string")
        func regexAccepts() {
            let v = Validator<String>.regex(/^\d+$/, message: "Digits only")
            #expect(v.validate("123") == nil)
        }

        @Test(".regex rejects non-matching string")
        func regexRejects() {
            let v = Validator<String>.regex(/^\d+$/, message: "Digits only")
            #expect(v.validate("abc") == "Digits only")
        }

        @Test(".custom rejects when check returns false")
        func customRejects() {
            let v = Validator<String>.custom("Bad") { $0 == "bad" }
            #expect(v.validate("bad") == "Bad")
        }

        @Test(".custom accepts when check returns true")
        func customAccepts() {
            let v = Validator<String>.custom("Bad") { $0 == "bad" }
            #expect(v.validate("good") == nil)
        }

        @Test("required before minLength: empty field shows Required not minLength message")
        func validatorOrdering() {
            let v1 = Validator<String>.required()
            let v2 = Validator<String>.minLength(3)
            let validators = [v1, v2]
            let result = validators.lazy.compactMap { $0.validate("") }.first
            #expect(result == "Required")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "FormTests/ValidatorTests" 2>&1 | tail -20
```

Expected: compilation error — `Validator` not found.

- [ ] **Step 3: Create `Sources/Swiflow/Forms/Validator.swift`**

```swift
public struct Validator<Value> {
    let validate: (Value) -> String?
}

extension Validator where Value == String {
    private static let _emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

    public static func required(message: String = "Required") -> Validator<String> {
        Validator { $0.isEmpty ? message : nil }
    }

    public static func minLength(_ n: Int, message: String? = nil) -> Validator<String> {
        Validator { v in
            v.count < n ? (message ?? "Must be at least \(n) characters") : nil
        }
    }

    public static func maxLength(_ n: Int, message: String? = nil) -> Validator<String> {
        Validator { v in
            v.count > n ? (message ?? "Must be at most \(n) characters") : nil
        }
    }

    public static var email: Validator<String> {
        Validator { v in
            v.wholeMatch(of: _emailPattern) == nil ? "Invalid email address" : nil
        }
    }

    public static func regex(_ pattern: some RegexComponent, message: String) -> Validator<String> {
        Validator { v in
            v.wholeMatch(of: pattern) == nil ? message : nil
        }
    }
}

extension Validator {
    public static func custom(_ message: String, _ check: @escaping (Value) -> Bool) -> Validator<Value> {
        Validator { v in check(v) ? nil : message }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "FormTests/ValidatorTests" 2>&1 | tail -20
```

Expected: all 13 validator tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Forms/Validator.swift Tests/SwiflowTests/Forms/FormTests.swift
git commit -m "feat(forms): Validator<Value> with built-ins + custom + tests"
```

---

### Task 2: `FormController`, `AnyInitialValue`, and `Field<Value>` + tests

**Files:**
- Create: `Sources/Swiflow/Forms/FormController.swift`
- Create: `Sources/Swiflow/Forms/Field.swift`
- Modify: `Tests/SwiflowTests/Forms/FormTests.swift` (add Field test suite)

**Important design notes:**
- `AnyInitialValue` is `package`-internal and marked `@unchecked Sendable`; it stores two closures capturing `Binding<Value>` (non-Sendable) — safe because all usage is `@MainActor`.
- `Field.init` has a deliberate side effect: on the first call for a given `key` (when `initialSnapshots[key] == nil`), it writes the initial value snapshot into `FormController` via `ctrl.set(updated)`. This triggers one extra render per field key, which is acceptable and expected.
- `FormController` is `@unchecked Sendable` for the same reason (stores `AnyInitialValue` which holds closures).

- [ ] **Step 1: Add the Field test suite to `Tests/SwiflowTests/Forms/FormTests.swift`**

Append inside the outer `FormTests` struct, after `ValidatorTests`:

```swift
    @Suite("Field")
    struct FieldTests {

        private func makeField(
            key: String = "pw",
            value: String = "",
            touched: Bool = false,
            validators: Validator<String>...
        ) -> (field: Field<String>, getValue: () -> String, getCtrl: () -> FormController) {
            var v = value
            var ctrl = FormController()
            if touched { ctrl.touched.insert(key) }
            let binding = Binding<String>(get: { v }, set: { v = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let field = Field(key, binding, ctrlBinding, validators)
            return (field, { v }, { ctrl })
        }

        @Test("error is nil when untouched even if invalid")
        func errorNilWhenUntouched() {
            let (field, _, _) = makeField(value: "", validators: .required())
            #expect(field.error == nil)
            #expect(field.isValid == false)
        }

        @Test("error is non-nil when touched and invalid")
        func errorNonNilWhenTouchedAndInvalid() {
            let (field, _, _) = makeField(value: "", touched: true, validators: .required())
            #expect(field.error == "Required")
        }

        @Test("error is nil when touched and valid")
        func errorNilWhenTouchedAndValid() {
            let (field, _, _) = makeField(value: "hello", touched: true, validators: .required())
            #expect(field.error == nil)
        }

        @Test("isValid is false regardless of touched when invalid")
        func isValidFalseWhenInvalid() {
            let (field, _, _) = makeField(value: "", validators: .required())
            #expect(field.isValid == false)
        }

        @Test("markTouched inserts key into ctrl.touched")
        func markTouchedInsertsKey() {
            let (field, _, getCtrl) = makeField(key: "pw", value: "x", validators: .required())
            field.markTouched()
            #expect(getCtrl().touched.contains("pw"))
        }

        @Test("isDirty is false when value matches initial")
        func isDirtyFalseOnInit() {
            let (field, _, _) = makeField(value: "hello", validators: .required())
            #expect(field.isDirty == false)
        }

        @Test("isDirty is true after mutation")
        func isDirtyTrueAfterMutation() {
            var v = "hello"
            var ctrl = FormController()
            let binding = Binding<String>(get: { v }, set: { v = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let field = Field("pw", binding, ctrlBinding)
            binding.set("world")
            #expect(field.isDirty == true)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "FormTests/FieldTests" 2>&1 | tail -20
```

Expected: compilation error — `FormController`, `Field` not found.

- [ ] **Step 3: Create `Sources/Swiflow/Forms/FormController.swift`**

```swift
package struct AnyInitialValue: @unchecked Sendable {
    package let isDirtyCheck: () -> Bool
    package let reset: () -> Void
}

public struct FormController: @unchecked Sendable {
    public var touched: Set<String>
    package var initialSnapshots: [String: AnyInitialValue]

    public init() {
        touched = []
        initialSnapshots = [:]
    }
}
```

- [ ] **Step 4: Create `Sources/Swiflow/Forms/Field.swift`**

```swift
public struct Field<Value: Equatable> {
    public let key: String
    let binding: Binding<Value>
    let ctrlBinding: Binding<FormController>
    let validators: [Validator<Value>]

    public init(_ key: String, _ binding: Binding<Value>, _ ctrl: Binding<FormController>, _ validators: [Validator<Value>] = []) {
        self.key = key
        self.binding = binding
        self.ctrlBinding = ctrl
        self.validators = validators

        if ctrl.get().initialSnapshots[key] == nil {
            var updated = ctrl.get()
            let initialValue = binding.get()
            updated.initialSnapshots[key] = AnyInitialValue(
                isDirtyCheck: { binding.get() != initialValue },
                reset: { binding.set(initialValue) }
            )
            ctrl.set(updated)
        }
    }

    public init(_ key: String, _ binding: Binding<Value>, _ ctrl: Binding<FormController>, _ validators: Validator<Value>...) {
        self.init(key, binding, ctrl, validators)
    }

    public var touched: Bool { ctrlBinding.get().touched.contains(key) }

    private func firstError() -> String? {
        validators.lazy.compactMap { $0.validate(binding.get()) }.first
    }

    public var error: String? { touched ? firstError() : nil }
    public var isValid: Bool { firstError() == nil }
    public var isDirty: Bool {
        ctrlBinding.get().initialSnapshots[key]?.isDirtyCheck() ?? false
    }

    public func markTouched() {
        var ctrl = ctrlBinding.get()
        ctrl.touched.insert(key)
        ctrlBinding.set(ctrl)
    }
}
```

**Note on the two `init` overloads:** The variadic overload (`Validator<Value>...`) delegates to the array overload. This is needed because `@FieldBuilder` must call Field with a concrete array (or variadic), and both test and production code can pass validators naturally.

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter "FormTests/FieldTests" 2>&1 | tail -20
```

Expected: all 7 Field tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Forms/FormController.swift Sources/Swiflow/Forms/Field.swift Tests/SwiflowTests/Forms/FormTests.swift
git commit -m "feat(forms): FormController + AnyInitialValue + Field<Value> + tests"
```

---

### Task 3: `ErasedField`, `@FieldBuilder`, `Form` + tests

**Files:**
- Create: `Sources/Swiflow/Forms/Form.swift`
- Modify: `Tests/SwiflowTests/Forms/FormTests.swift` (add Form test suite)

**Design notes:**
- `ErasedField` is `package`-internal (used only within the Forms group); all its closure properties are `() -> Bool` or `() -> Void` — they read from bindings/ctrl at call time (not precomputed), so `form.isValid` and `form.isDirty` are always current even when `form` is captured by an event handler closure.
- `Form.reset()` clears only `ctrl.touched` — it does NOT touch `initialSnapshots`, which must survive across resets.
- The `@FieldBuilder` `buildExpression` converts heterogeneous `Field<V>` instances into `ErasedField` via `field.erased`.

- [ ] **Step 1: Add the Form test suite to `Tests/SwiflowTests/Forms/FormTests.swift`**

Append inside the outer `FormTests` struct, after `FieldTests`:

```swift
    @Suite("Form")
    struct FormSuite {

        private func makeForm() -> (
            form: Form,
            pwBinding: Binding<String>,
            emBinding: Binding<String>,
            getCtrl: () -> FormController
        ) {
            var pw = ""
            var em = ""
            var ctrl = FormController()
            let pwBinding = Binding<String>(get: { pw }, set: { pw = $0 })
            let emBinding = Binding<String>(get: { em }, set: { em = $0 })
            let ctrlBinding = Binding<FormController>(get: { ctrl }, set: { ctrl = $0 })
            let pwField = Field("pw", pwBinding, ctrlBinding, .required(), .minLength(3))
            let emField = Field("em", emBinding, ctrlBinding, .required(), .email)
            let form = Form(ctrlBinding) { pwField; emField }
            return (form, pwBinding, emBinding, { ctrl })
        }

        @Test("isValid is false when any field is invalid")
        func isValidFalseWhenInvalid() {
            let (form, _, _, _) = makeForm()
            #expect(form.isValid == false)
        }

        @Test("isValid is true when all fields are valid")
        func isValidTrueWhenAllValid() {
            let (form, pwBinding, emBinding, _) = makeForm()
            pwBinding.set("hello")
            emBinding.set("a@b.com")
            #expect(form.isValid == true)
        }

        @Test("isDirty is false before any mutation")
        func isDirtyFalseBeforeMutation() {
            let (form, _, _, _) = makeForm()
            #expect(form.isDirty == false)
        }

        @Test("isDirty is true after one field changes")
        func isDirtyTrueAfterMutation() {
            let (form, pwBinding, _, _) = makeForm()
            pwBinding.set("hello")
            #expect(form.isDirty == true)
        }

        @Test("touchAll marks all fields as touched")
        func touchAllMarksAllTouched() {
            let (form, _, _, getCtrl) = makeForm()
            form.touchAll()
            #expect(getCtrl().touched.contains("pw"))
            #expect(getCtrl().touched.contains("em"))
        }

        @Test("reset restores all values to initial and clears touched")
        func resetRestoresAndClearsTouched() {
            let (form, pwBinding, emBinding, getCtrl) = makeForm()
            pwBinding.set("hello")
            emBinding.set("a@b.com")
            form.touchAll()
            form.reset()
            #expect(pwBinding.get() == "")
            #expect(emBinding.get() == "")
            #expect(getCtrl().touched.isEmpty)
        }

        @Test("isDirty is false after reset")
        func isDirtyFalseAfterReset() {
            let (form, pwBinding, _, _) = makeForm()
            pwBinding.set("hello")
            form.reset()
            #expect(form.isDirty == false)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "FormTests/FormSuite" 2>&1 | tail -20
```

Expected: compilation error — `Form`, `FieldBuilder` not found.

- [ ] **Step 3: Create `Sources/Swiflow/Forms/Form.swift`**

```swift
struct ErasedField {
    let key: String
    let isValidFn: () -> Bool
    let isDirtyFn: () -> Bool
    let resetFn: () -> Void
}

extension Field {
    var erased: ErasedField {
        ErasedField(
            key: key,
            isValidFn: { self.isValid },
            isDirtyFn: { self.isDirty },
            resetFn: {
                self.ctrlBinding.get().initialSnapshots[self.key]?.reset()
            }
        )
    }
}

@resultBuilder
public enum FieldBuilder {
    public static func buildBlock(_ fields: ErasedField...) -> [ErasedField] {
        Array(fields)
    }

    public static func buildExpression<V: Equatable>(_ field: Field<V>) -> ErasedField {
        field.erased
    }
}

public struct Form {
    private let fields: [ErasedField]
    private let ctrlBinding: Binding<FormController>

    public init(_ ctrl: Binding<FormController>, @FieldBuilder _ build: () -> [ErasedField]) {
        self.ctrlBinding = ctrl
        self.fields = build()
    }

    public var isValid: Bool { fields.allSatisfy { $0.isValidFn() } }
    public var isDirty: Bool { fields.contains { $0.isDirtyFn() } }

    public func touchAll() {
        var ctrl = ctrlBinding.get()
        fields.forEach { ctrl.touched.insert($0.key) }
        ctrlBinding.set(ctrl)
    }

    public func reset() {
        fields.forEach { $0.resetFn() }
        var ctrl = ctrlBinding.get()
        ctrl.touched = []
        ctrlBinding.set(ctrl)
    }
}
```

- [ ] **Step 4: Run all Form tests**

```bash
swift test --filter "FormTests" 2>&1 | tail -30
```

Expected: all Form tests pass (7 Validator + 7 Field + 7 Form = 21 total in the Forms suite).

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
swift test 2>&1 | tail -10
```

Expected: all tests pass (330 existing + 21 new = 351 or similar count).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Forms/Form.swift Tests/SwiflowTests/Forms/FormTests.swift
git commit -m "feat(forms): ErasedField + @FieldBuilder + Form + tests"
```

---

### Task 4: `SignIn` example component + README

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift` (update to match new App.swift)
- Modify: `README.md`

**Context:** `App.swift` currently has `Counter` (the Phase 12a demo) as the root component and `Toast` as a child component. This task adds a `SignIn` component nested inside `Counter`'s body (via conditional toggle) so both Phase 12a and Phase 12b are demonstrated without replacing existing work.

- [ ] **Step 1: Add the `SignIn` component to `examples/HelloWorld/Sources/App/App.swift`**

Read the full file first (`examples/HelloWorld/Sources/App/App.swift`), then append the `SignIn` class after the `Toast` class definition. Also add a toggle to `Counter` to show/hide it.

The `SignIn` component to add (append before the closing of the file or after `Toast`):

```swift
/// SignIn — Phase 12b form validation demo.
///
/// Showcases:
/// - `FormController` + `Field` + `Form` coordinator
/// - Two-field form (email + password) with blur-triggered error messages
/// - Submit disabled until `form.isValid`; `touchAll()` reveals all errors on early click
/// - Reset button restores initial values
final class SignIn: Component {
    @State var email    = ""
    @State var password = ""
    @State var ctrl     = FormController()
    @State var submitted = false

    var body: VNode {
        let em = Field("email",    $email,    $ctrl, .required(), .email)
        let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let form = Form($ctrl) { em; pw }

        div(.style(name: "max-width", value: "320px"),
            .style(name: "margin", value: "2rem auto"),
            .style(name: "font-family", value: "system-ui, sans-serif")) {

            if submitted {
                p("Signed in as \(email)!")
                button("Sign out", .on(.click) {
                    self.submitted = false
                    self.email = ""
                    self.password = ""
                    self.ctrl = FormController()
                })
            } else {
                h2("Sign In")

                div(.style(name: "margin-bottom", value: "1rem")) {
                    label("Email")
                    input(.value($email),
                          .style(name: "display", value: "block"),
                          .style(name: "width", value: "100%"),
                          .style(name: "margin-top", value: "4px"),
                          .on(.blur) { em.markTouched() })
                    if em.touched, let err = em.error {
                        p(.style(name: "color", value: "red"),
                          .style(name: "font-size", value: "0.85rem"),
                          err)
                    }
                }

                div(.style(name: "margin-bottom", value: "1rem")) {
                    label("Password")
                    input(.value($password),
                          .style(name: "display", value: "block"),
                          .style(name: "width", value: "100%"),
                          .style(name: "margin-top", value: "4px"),
                          .on(.blur) { pw.markTouched() })
                    if pw.touched, let err = pw.error {
                        p(.style(name: "color", value: "red"),
                          .style(name: "font-size", value: "0.85rem"),
                          err)
                    }
                }

                button("Sign In",
                       .style(name: "margin-right", value: "0.5rem"),
                       .on(.click) {
                           form.touchAll()
                           guard form.isValid else { return }
                           self.submitted = true
                       })
                button("Reset", .on(.click) { form.reset() })
            }
        }
    }
}
```

In `Counter.body`, add a `@State var showSignIn: Bool = false` property to the class, then add a toggle button and conditional embed of SignIn inside the existing `div` body.

Add to `Counter` class properties:
```swift
@State var showSignIn: Bool = false
```

Inside the `Counter.body` div (after the existing content), add:
```swift
div(.style(name: "margin-top", value: "2rem"),
    .style(name: "border-top", value: "1px solid #eee"),
    .style(name: "padding-top", value: "1.5rem")) {
    button(showSignIn ? "Hide Sign In" : "Show Sign In demo",
           .on(.click) { self.showSignIn.toggle() })
    if showSignIn {
        embed { SignIn() }
    }
}
```

- [ ] **Step 2: Build HelloWorld to catch any compile errors**

```bash
swift build --package-path examples/HelloWorld 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 3: Update `Sources/SwiflowCLI/Templates/Templates.swift`**

The template string in `Templates.swift` is what `swiflow init` generates. Read the file and locate the `helloWorldApp` template string (it mirrors `examples/HelloWorld/Sources/App/App.swift`). Update it to include the `SignIn` component and the `showSignIn` toggle in `Counter`, matching the new `App.swift`.

Read the full file first, then make the minimal changes to keep the template in sync.

- [ ] **Step 4: Update `README.md`**

Find the status line (currently `Phase 12a (Styling & Animation)`) and change it to:

```
Phase 12b (Form Validation)
```

- [ ] **Step 5: Run the full test suite one final time**

```bash
swift test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add examples/HelloWorld/Sources/App/App.swift Sources/SwiflowCLI/Templates/Templates.swift README.md
git commit -m "feat(forms): SignIn demo in HelloWorld + README status Phase 12b"
```
