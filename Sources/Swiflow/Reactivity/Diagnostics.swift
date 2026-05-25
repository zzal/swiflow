// Sources/Swiflow/Reactivity/Diagnostics.swift

/// Single entry point for the framework's debug-only diagnostic checks.
///
/// In debug builds (`-c debug`, the default), calling this function
/// invokes `preconditionFailure(message)` — the test suite's exit-test cases
/// detect the crash and verify the message substring. In release builds
/// (`-c release`), the call is compiled to nothing: zero CPU cost, zero
/// binary footprint.
///
/// **Test override:** tests that need to assert on the *message* (rather
/// than just "the process crashed") can install
/// `_swiflowDiagnosticOverride` to capture messages without trapping.
/// See the underscore-prefixed declaration below.
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
    if let override = _swiflowDiagnosticOverride {
        override(message())
        return
    }
    preconditionFailure("Swiflow diagnostic: \(message())")
    #endif
}

#if DEBUG
/// Test-side override for capturing `swiflowDiagnostic` messages.
///
/// Set to a non-nil closure from inside a test to redirect diagnostics
/// (which otherwise `preconditionFailure` and tear down the process) into a
/// capture buffer; restore to `nil` before the test exits.
///
/// The leading underscore flags this as framework-internal — user code
/// should never touch it. Available only in DEBUG builds.
///
/// **Thread isolation:** declared `nonisolated(unsafe)` to mirror the
/// isolation of `swiflowDiagnostic` itself (which is callable from any
/// context — diff, VNode modifiers, etc.). In practice the framework's
/// diagnostic call-sites all run on the main actor; tests installing
/// the override should do the same and restore the prior value before
/// returning to avoid cross-test bleed.
///
/// Usage:
/// ```swift
/// var captured: [String] = []
/// let prior = _swiflowDiagnosticOverride
/// _swiflowDiagnosticOverride = { captured.append($0) }
/// defer { _swiflowDiagnosticOverride = prior }
/// // ... exercise code that may fire diagnostics ...
/// #expect(captured.contains { $0.contains("expected substring") })
/// ```
nonisolated(unsafe) public var _swiflowDiagnosticOverride: ((String) -> Void)?
#endif
