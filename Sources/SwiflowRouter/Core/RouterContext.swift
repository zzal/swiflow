import Swiflow

/// The runtime context injected into route factory closures.
/// Carries the matched path, extracted `:param` captures, and
/// parsed `?key=value` query parameters.
///
/// Prefer `param(_:)` / `param(_:as:)` over raw `params[...]` access: a
/// matched route guarantees its declared `:param` captures are present,
/// so the accessors skip the `?? fallback` ritual and DEBUG-warn when a
/// name was never declared (a typo). Unparseable values for the typed
/// accessor return `nil` silently — the URL is user input.
public struct RouterContext: Sendable {
    public let path: String
    public let params: [String: String]
    public let query: [String: String]

    public init(
        path: String,
        params: [String: String] = [:],
        query: [String: String] = [:]
    ) {
        self.path = path
        self.params = params
        self.query = query
    }

    /// Non-optional access to a declared `:param` capture.
    ///
    /// A matched route guarantees every declared param is present, so a
    /// missing key means the NAME is wrong (typo'd or never declared) —
    /// a programmer error: DEBUG-warns and returns `""`.
    ///
    /// ```swift
    /// Route("/users/:id") { ctx in UserPage(id: ctx.param("id")) }
    /// ```
    public func param(_ name: String) -> String {
        guard let value = params[name] else {
            warnUndeclaredParam(name)
            return ""
        }
        return value
    }

    /// Shared by both `param` accessors so the wording cannot drift
    /// (sibling-inconsistency is the audit's dominant defect shape).
    private func warnUndeclaredParam(_ name: String) {
        let declared = params.keys.sorted().joined(separator: ", ")
        swiflowWarn(
            "Route param '\(name)' was never declared by the matched route "
                + "(path: \(path), declared params: \(declared.isEmpty ? "(none)" : declared)). "
                + "Check the pattern's ':param' names — accessing an undeclared "
                + "param returns \"\" (or nil for typed access)."
        )
    }
}
