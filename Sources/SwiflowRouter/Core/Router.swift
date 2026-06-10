import Swiflow

/// How the router encodes routes in the browser URL. Lives in Core (not
/// Web) so `Link` can render mode-correct hrefs from the environment value
/// without importing the browser layer.
public enum RouterMode: Sendable, Equatable {
    case hash, history
}

/// The value injected into `@Environment(\.router)`.
/// Gives components read access to the current path and write
/// access via `navigate`, `replace`, and `back`.
public struct Router: Sendable {
    public let path: String
    public let mode: RouterMode
    public let navigate: @Sendable (String) -> Void
    public let replace: @Sendable (String) -> Void
    public let back: @Sendable () -> Void

    public init(
        path: String,
        mode: RouterMode = .hash,
        navigate: @escaping @Sendable (String) -> Void,
        replace: @escaping @Sendable (String) -> Void,
        back: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.mode = mode
        self.navigate = navigate
        self.replace = replace
        self.back = back
    }

    /// The `href` a link to `path` should carry under this router's mode:
    /// hash mode's canonical URL is `#/about` (so cmd/middle-click and
    /// "copy link address" resolve to the route, not a server path);
    /// history mode uses the path itself.
    public func href(forPath path: String) -> String {
        switch mode {
        case .hash: return "#" + path
        case .history: return path
        }
    }
}
