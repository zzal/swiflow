// ErasedField is a public opaque type — no public init, no public members.
// Users never construct it directly; only Field.erased (package-visible) does.
public struct ErasedField {
    let key: String
    let isValidFn: () -> Bool
    let isDirtyFn: () -> Bool
    let resetFn: () -> Void
}

extension Field {
    // Closes over self (a struct copy) — safe because Binding's get/set closures share the original captured variables by reference
    package var erased: ErasedField {
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
        fields
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
