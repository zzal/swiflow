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
/// `FormController` holds state for exactly ONE record at a time. Each
/// `Field` seeds `initialSnapshots[key]` on its FIRST construction against a
/// given controller instance (see `Field.init`) and never updates it again;
/// `reset()`-style restores (via `AnyInitialValue.reset`) always go back to
/// that first-seen snapshot, not to whatever record is currently bound.
///
/// If the identity of the edited record changes — switching from "new" to
/// "editing record A", or from record A to record B — don't keep mutating
/// the existing controller: REPLACE it (`self.ctrl = FormController()`).
/// A fresh controller has no snapshots, so the next `Field` construction
/// against it re-seeds from the new record's current values. See
/// `examples/HelloWorld/Sources/App/SignIn.swift` for the pattern.
public struct FormController: @unchecked Sendable {
    public internal(set) var touched: Set<String>
    package var initialSnapshots: [String: AnyInitialValue]

    public init() {
        touched = []
        initialSnapshots = [:]
    }
}
