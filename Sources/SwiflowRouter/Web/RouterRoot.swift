// Sources/SwiflowRouter/Web/RouterRoot.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The root component of a routed Swiflow app.
///
/// Mounts inside `Swiflow.render(into:_:)` and owns the routing lifecycle:
/// URL reading, browser event listening, route matching, and
/// `@Environment(\.router)` injection.
///
/// ```swift
/// Swiflow.render(into: "#app") {
///     RouterRoot {
///         Route("/") { HomePage() }
///         Route("/about") { AboutPage() }
///         Route("/users/:id") { ctx in UsersPage(id: ctx.param("id")) }
///     } notFound: { ctx in
///         NotFoundPage(path: ctx.path)   // rendered when no route matches
///     }
/// }
/// ```
///
/// Without `notFound:` an unmatched path renders a plain diagnostic text
/// node ("404 — no route matched …") — fine in dev, not what you want to
/// ship. The closure receives a `RouterContext` whose `path` is the
/// unmatched path (params/query are empty), and it renders inside the
/// router environment, so a `Link` home works.
// Explicit @MainActor kept DELIBERATELY (not an oversight from the bare-
// @Component migration): the [weak self] captures in the @Sendable navigate/
// replace closures need the implicit Sendable that class-level @MainActor
// confers — @Component's memberAttribute injection isolates members but does
// not make the class Sendable.
@MainActor @Component
public final class RouterRoot {
    public typealias Mode = RouterMode

    @State private var currentPath: String = "/"
    private let mode: Mode
    private let routes: [RouteDefinition]
    /// The browser crossing (location/history/listeners). Injected package-
    /// side for host tests; the public inits default it to `BrowserNavigator`.
    private let navigator: Navigator

    /// nil = today's built-in diagnostic text. Set via the `notFound:` init.
    private let notFoundFactory: ((RouterContext) -> VNode)?

    public init(mode: Mode = .hash, @RouteBuilder routes: () -> [RouteDefinition]) {
        let navigator = BrowserNavigator()
        self.mode = mode
        self.navigator = navigator
        self.routes = routes()
        self.notFoundFactory = nil
        self.currentPath = mode.readPath(from: navigator)
    }

    /// Routed root with a custom 404: `notFound` renders whenever no route
    /// matches the current path. Mirrors `Route`'s component-factory
    /// ergonomics (the component is embedded for you).
    public init<C: Component>(
        mode: Mode = .hash,
        @RouteBuilder routes: () -> [RouteDefinition],
        notFound: @escaping (RouterContext) -> C
    ) {
        let navigator = BrowserNavigator()
        self.mode = mode
        self.navigator = navigator
        self.routes = routes()
        self.notFoundFactory = { ctx in embed { notFound(ctx) } }
        self.currentPath = mode.readPath(from: navigator)
    }

    /// The seam init — host tests inject a `MockNavigator` here. Package
    /// (not public) on purpose: a testability seam, not user API (the
    /// SwiflowDriver precedent).
    package init(
        mode: Mode = .hash,
        navigator: Navigator,
        @RouteBuilder routes: () -> [RouteDefinition],
        notFound: ((RouterContext) -> VNode)?
    ) {
        self.mode = mode
        self.navigator = navigator
        self.routes = routes()
        self.notFoundFactory = notFound
        self.currentPath = mode.readPath(from: navigator)
    }

    public var body: VNode {
        let router = Router(
            path: currentPath,
            mode: mode,
            navigate: { [weak self] path in
                MainActor.assumeIsolated { self?.push(path) }
            },
            replace:  { [weak self] path in
                MainActor.assumeIsolated { self?.replacePath(path) }
            },
            back: { [weak self] in
                MainActor.assumeIsolated { self?.navigator.back() }
            }
        )
        let matched = matchRoutes(routes, path: currentPath)
        // withEnvironment stays OUTSIDE the fallback decision so a custom
        // 404 page renders with the live router (its Link home works).
        return withEnvironment(\.router, router) {
            Self.resolveContent(matched: matched, path: currentPath, notFound: notFoundFactory)
        }
    }

    /// The fallback decision: matched route → user's `notFound` → the
    /// built-in diagnostic text. Pure and `package` — host-testable without
    /// even constructing RouterRoot (which, since the Navigator seam, is
    /// also possible: inject a mock through the package init).
    package static func resolveContent(
        matched: VNode?,
        path: String,
        notFound: ((RouterContext) -> VNode)?
    ) -> VNode {
        if let matched { return matched }
        if let notFound { return notFound(RouterContext(path: path)) }
        return VNode.text("404 — no route matched \(path)")
    }

    public func onAppear() {
        navigator.startListening(to: mode.changeEvent) { [weak self] in
            self?.sync()
        }
    }

    public func onDisappear() {
        navigator.stopListening()
    }

    // MARK: - Private

    private func sync() {
        currentPath = mode.readPath(from: navigator)
    }

    /// Package (not private) so lifecycle tests can drive navigation without
    /// a browser — the DataTable internal-seam precedent (`cycleSort`,
    /// `visibleWindow`). Production callers reach these only through the
    /// environment `Router`'s closures.
    package func push(_ path: String) {
        switch mode {
        case .hash:
            navigator.setHash(mode.url(for: path))
        case .history:
            navigator.pushState(mode.url(for: path))
            currentPath = path
        }
        // The residual switch is DELIBERATE: setHash-vs-pushState are
        // different browser APIs, and history mode must update currentPath
        // imperatively while hash mode waits for the hashchange event —
        // the asymmetry audit item #8 (commit choke point) unifies.
    }

    package func replacePath(_ path: String) {
        navigator.replaceState(mode.url(for: path))
        currentPath = path
    }
}
#endif
