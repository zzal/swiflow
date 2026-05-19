// Sources/Swiflow/Reactivity/Diagnostics.swift

/// Single entry point for the framework's debug-only diagnostic checks.
///
/// In debug builds (`-c debug`, the default), calling this function
/// invokes `fatalError(message)` — the test suite's exit-test cases
/// detect the crash and verify the message substring. In release builds
/// (`-c release`), the call is compiled to nothing: zero CPU cost, zero
/// binary footprint.
///
/// Message convention: framework concept first, then location/cause,
/// then guidance. React-style.
///
/// Example:
/// `swiflowDiagnostic("Duplicate key 'foo' among siblings of <ul>. Keys must be unique within a parent. Offending positions: 1 and 3.")`
///
/// **When to use:** programming errors that produce silent wrong behaviour
/// in production (duplicate keys, infinite component recursion, mixed
/// keyed/unkeyed children). NOT for runtime conditions a well-formed
/// application might legitimately hit (network errors, user input
/// validation, XSS attempts — those should LOG, not crash).
@inlinable
public func swiflowDiagnostic(_ message: @autoclosure () -> String) {
    #if DEBUG
    fatalError("Swiflow diagnostic: \(message())")
    #endif
}
