// Thread isolation: Swiflow is single-threaded wasm — these closures are
// only ever created and invoked from @MainActor form code. `@unchecked
// Sendable` lets the closures live inside a value type without forcing
// their (arbitrary, form-field-specific) captures to be Sendable.
package struct AnyInitialValue: @unchecked Sendable {
    package let isDirtyCheck: () -> Bool
    package let reset: () -> Void
}

// Thread isolation: see `AnyInitialValue` above — single-threaded wasm,
// MainActor-only access; `@unchecked Sendable` avoids propagating Sendable
// requirements onto `AnyInitialValue`'s non-Sendable closures.
public struct FormController: @unchecked Sendable {
    public internal(set) var touched: Set<String>
    package var initialSnapshots: [String: AnyInitialValue]

    public init() {
        touched = []
        initialSnapshots = [:]
    }
}
