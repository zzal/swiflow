// Sources/Swiflow/DSL/EnvironmentDSL.swift

/// Overrides an environment value for a subtree.
///
/// ```swift
/// var body: VNode {
///     withEnvironment(\.locale, "fr") {
///         embed { Sidebar() }
///     }
/// }
/// ```
///
/// For multiple overrides, nest calls:
/// ```swift
/// withEnvironment(\.locale, "fr") {
///     withEnvironment(\.colorScheme, .dark) {
///         embed { Sidebar() }
///     }
/// }
/// ```
public func withEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    _ value: Value,
    content: () -> VNode
) -> VNode {
    var overrides = EnvironmentValues()
    overrides[keyPath: keyPath] = value
    return .environmentOverride(overrides, content())
}

public extension VNode {
    /// Wraps this VNode in an `.environmentOverride` node, injecting a single
    /// environment value for the subtree rooted at this node.
    ///
    /// ```swift
    /// embed { Sidebar() }.environment(\.locale, "fr")
    /// ```
    func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> VNode {
        var overrides = EnvironmentValues()
        overrides[keyPath: keyPath] = value
        return .environmentOverride(overrides, self)
    }
}
