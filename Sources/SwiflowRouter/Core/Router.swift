import Swiflow

/// How the router encodes routes in the browser URL. Lives in Core (not
/// Web) so `Link` can render mode-correct hrefs from the environment value
/// without importing the browser layer.
public enum RouterMode: Sendable, Equatable {
    case hash, history
}

// MARK: - Mode behavior

/// The mode's behavior lives ON the mode (audit IV Wave-2 #7) — before
/// this, the dispatch was open-coded at five sites and the URL-string
/// conventions had drifted into two forms. `package`: implementation
/// vocabulary for RouterRoot/Router, not user API.
extension RouterMode {
    /// The window event that signals an external URL change in this mode.
    package var changeEvent: String {
        switch self {
        case .hash: return "hashchange"
        case .history: return "popstate"
        }
    }

    /// The canonical URL string for `path` in this mode — THE one
    /// construction site. Everything the router writes (push, replace) or
    /// renders (href) goes through here, so the conventions cannot drift
    /// apart again.
    package func url(for path: String) -> String {
        switch self {
        case .hash: return "#" + path
        case .history: return path
        }
    }

    /// The current route path per this mode's URL source.
    @MainActor
    package func readPath(from navigator: Navigator) -> String {
        switch self {
        case .hash:
            let hash = navigator.hash
            let path = hash.hasPrefix("#") ? String(hash.dropFirst()) : ""
            return path.isEmpty ? "/" : path
        case .history:
            // pathname alone loses the query on popstate/refresh — the
            // audit's 'history mode drops query strings' finding. The matcher
            // strips the query for matching; RouterContext.query parses it.
            return navigator.pathname + navigator.search
        }
    }
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
        mode.url(for: path)
    }
}
