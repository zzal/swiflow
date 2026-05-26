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
///         Route("/users/:id") { ctx in UsersPage(id: ctx.params["id"] ?? "") }
///     }
/// }
/// ```
@MainActor @Component
public final class RouterRoot {
    public enum Mode { case hash, history }

    @State private var currentPath: String = "/"
    private let mode: Mode
    private let routes: [RouteDefinition]
    /// Strong reference so the JS event listener keeps its Swift callback alive
    /// for the component's lifetime. Matches the `rafClosure` pattern in
    /// `RAFScheduler`.
    private var listenerClosure: JSClosure?

    public init(mode: Mode = .hash, @RouteBuilder routes: () -> [RouteDefinition]) {
        self.mode = mode
        self.routes = routes()
        self.currentPath = Self.readPath(mode: mode)
    }

    public var body: VNode {
        let router = Router(
            path: currentPath,
            navigate: { [weak self] path in
                MainActor.assumeIsolated { self?.push(path) }
            },
            replace:  { [weak self] path in
                MainActor.assumeIsolated { self?.replacePath(path) }
            },
            back: {
                MainActor.assumeIsolated {
                    let history = JSObject.global.history.object!
                    _ = history.back!()
                }
            }
        )
        let matched = matchRoutes(routes, path: currentPath)
        return withEnvironment(\.router, router) {
            matched ?? VNode.text("404 — no route matched \(currentPath)")
        }
    }

    public func onAppear() {
        let closure = JSClosure { [weak self] _ -> JSValue in
            self?.sync()
            return .undefined
        }
        let event = mode == .hash ? "hashchange" : "popstate"
        let window = JSObject.global.window.object!
        _ = window.addEventListener!(event.jsValue, JSValue.object(closure))
        listenerClosure = closure
    }

    // MARK: - Private

    private func sync() {
        currentPath = Self.readPath(mode: mode)
    }

    private static func readPath(mode: Mode) -> String {
        let loc = JSObject.global.window.object!["location"].object!
        switch mode {
        case .hash:
            let hash = loc["hash"].string ?? ""
            let path = hash.hasPrefix("#") ? String(hash.dropFirst()) : ""
            return path.isEmpty ? "/" : path
        case .history:
            return loc["pathname"].string ?? "/"
        }
    }

    private func push(_ path: String) {
        switch mode {
        case .hash:
            JSObject.global.window.object!["location"].object!["hash"] = path.jsValue
        case .history:
            let history = JSObject.global.history.object!
            _ = history.pushState!(JSValue.null, "".jsValue, path.jsValue)
            currentPath = path
        }
    }

    private func replacePath(_ path: String) {
        let history = JSObject.global.history.object!
        switch mode {
        case .hash:
            _ = history.replaceState!(JSValue.null, "".jsValue, ("#" + path).jsValue)
        case .history:
            _ = history.replaceState!(JSValue.null, "".jsValue, path.jsValue)
        }
        currentPath = path
    }
}
#endif
