import Swiflow

/// The value injected into `@Environment(\.router)`.
/// Gives components read access to the current path and write
/// access via `navigate`, `replace`, and `back`.
public struct Router: Sendable {
    public let path: String
    public let navigate: @Sendable (String) -> Void
    public let replace: @Sendable (String) -> Void
    public let back: @Sendable () -> Void

    public init(
        path: String,
        navigate: @escaping @Sendable (String) -> Void,
        replace: @escaping @Sendable (String) -> Void,
        back: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.navigate = navigate
        self.replace = replace
        self.back = back
    }
}
