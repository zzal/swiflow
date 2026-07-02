/// `Field.init` has a side effect: on the FIRST construction for a given
/// `key` against a given `FormController`, it writes the field's current
/// value into `ctrl.initialSnapshots[key]` through the `ctrl` binding — a
/// write-through-a-binding performed inside an `init`, which is unusual for
/// this codebase (most types are side-effect-free to construct). Because
/// `Field`s are typically rebuilt every render (see `SignIn.swift`'s `body`),
/// this only fires once per key per controller instance: the `nil` guard
/// means subsequent constructions with the same key are no-ops against
/// `initialSnapshots`.
///
/// This is also why a `FormController` is a ONE-RECORD-AT-A-TIME piece of
/// state: `initialSnapshots` freezes the first value seen for each key, and
/// `reset()` (see `FormController`) restores THAT snapshot — not whatever
/// record is currently bound. If the edited record's identity changes (e.g.
/// switching from "add" to "edit", or from editing record A to record B),
/// don't keep reusing the same `FormController` — replace it wholesale
/// (`self.ctrl = FormController()`) so the next `Field` construction
/// re-snapshots against the new record. See `examples/HelloWorld/Sources/
/// App/SignIn.swift`'s "Sign out" handler for the pattern.
public struct Field<Value: Equatable> {
    public let key: String
    package let binding: Binding<Value>
    package let ctrlBinding: Binding<FormController>
    package let validators: [Validator<Value>]

    public init(_ key: String, _ binding: Binding<Value>, _ ctrl: Binding<FormController>, _ validators: [Validator<Value>] = []) {
        self.key = key
        self.binding = binding
        self.ctrlBinding = ctrl
        self.validators = validators

        // First construction for this key: snapshot initial value into FormController (triggers one extra render)
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
