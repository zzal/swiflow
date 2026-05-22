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
