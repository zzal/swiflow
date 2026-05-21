// Sources/SwiflowRouter/Core/RouteDefinition.swift
import Swiflow

/// Internal unit of the route tree. Callers build these through the
/// `Route(...)` DSL free functions — never directly.
package struct RouteDefinition {
    package let pattern: RoutePattern
    /// Called by `matchRoutes` when this route's pattern matches the
    /// current path. Returns the VNode to render. Non-`@MainActor`
    /// because the closure is created from `@MainActor` context and
    /// called from `RouterRoot.body` (also `@MainActor`).
    package let factory: (RouterContext) -> VNode
    /// Non-empty for namespace routes created with `Route("/prefix") { children }`.
    package let children: [RouteDefinition]

    package init(
        pattern: RoutePattern,
        factory: @escaping (RouterContext) -> VNode,
        children: [RouteDefinition] = []
    ) {
        self.pattern = pattern
        self.factory = factory
        self.children = children
    }
}
