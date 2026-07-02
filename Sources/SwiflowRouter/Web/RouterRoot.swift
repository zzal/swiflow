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
    public typealias Mode = RouterMode

    @State private var currentPath: String = "/"
    private let mode: Mode
    private let routes: [RouteDefinition]
    /// Held for ownership clarity (mirrors `RAFScheduler.rafClosure`), not
    /// because it's what keeps the listener callable — `JSClosure.init`
    /// self-registers into JavaScriptKit's static `sharedClosures` table.
    /// What actually stops it from firing is `onDisappear`'s explicit
    /// `removeEventListener` call.
    private var listenerClosure: JSClosure?
    /// The exact `JSValue` registered as the listener in `onAppear`, stored
    /// so `onDisappear`'s `removeEventListener` passes the SAME reference
    /// `addEventListener` got (mirrors `BackgroundRevalidation.focusListener`).
    private var listenerValue: JSValue?
    /// The event name registered alongside `listenerValue`.
    private var listenerEvent: String?

    public init(mode: Mode = .hash, @RouteBuilder routes: () -> [RouteDefinition]) {
        self.mode = mode
        self.routes = routes()
        self.currentPath = Self.readPath(mode: mode)
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
        let value = JSValue.object(closure)
        _ = window.addEventListener!(event.jsValue, value)
        listenerClosure = closure
        listenerValue = value
        listenerEvent = event
    }

    public func onDisappear() {
        if let event = listenerEvent, let value = listenerValue {
            let window = JSObject.global.window.object!
            _ = window.removeEventListener!(event.jsValue, value)
        }
        // Nil the closure AFTER removeEventListener, so the JSClosure stays
        // alive through the remove (mirrors `BackgroundRevalidation.stop()`).
        listenerClosure = nil
        listenerValue = nil
        listenerEvent = nil
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
            // pathname alone loses the query on popstate/refresh — the
            // audit's 'history mode drops query strings' finding. The matcher
            // strips the query for matching; RouterContext.query parses it.
            let pathname = loc["pathname"].string ?? "/"
            let search = loc["search"].string ?? ""
            return pathname + search
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
