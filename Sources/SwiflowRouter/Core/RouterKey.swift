import Swiflow

private enum RouterKey: EnvironmentKey {
    static let defaultValue = Router(
        path: "/",
        navigate: { _ in },
        replace: { _ in },
        back: {}
    )
}

public extension EnvironmentValues {
    /// The active router. Read with `@Environment(\.router) var router`.
    /// Defaults to a no-op router with `path == "/"` when no `RouterRoot`
    /// is present — useful for snapshot tests and components rendered
    /// outside a router context.
    var router: Router {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
