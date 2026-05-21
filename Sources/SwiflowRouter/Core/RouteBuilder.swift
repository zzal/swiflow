// Sources/SwiflowRouter/Core/RouteBuilder.swift
import Swiflow

/// Accumulates `RouteDefinition` values from a trailing-closure block.
/// Mirrors `ChildrenBuilder` from `Swiflow` but produces
/// `[RouteDefinition]` instead of `[VNode]`.
@resultBuilder
public enum RouteBuilder {
    public static func buildBlock(_ components: [RouteDefinition]...) -> [RouteDefinition] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: RouteDefinition) -> [RouteDefinition] {
        [expression]
    }
    public static func buildOptional(_ component: [RouteDefinition]?) -> [RouteDefinition] {
        component ?? []
    }
    public static func buildEither(first component: [RouteDefinition]) -> [RouteDefinition] {
        component
    }
    public static func buildEither(second component: [RouteDefinition]) -> [RouteDefinition] {
        component
    }
    public static func buildArray(_ components: [[RouteDefinition]]) -> [RouteDefinition] {
        components.flatMap { $0 }
    }
}

// MARK: - Route DSL

/// Leaf route whose component factory ignores the router context.
///
/// ```swift
/// Route("/about") { AboutPage() }
/// ```
public func Route<C: Component>(
    _ path: String,
    _ factory: @escaping () -> C
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path)) { _ in
        embed { factory() }
    }
}

/// Leaf route whose component factory receives the router context
/// (useful for reading `:param` captures and query params).
///
/// ```swift
/// Route("/users/:id") { ctx in UserPage(id: ctx.params["id"] ?? "") }
/// ```
public func Route<C: Component>(
    _ path: String,
    _ factory: @escaping (RouterContext) -> C
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path)) { ctx in
        embed { factory(ctx) }
    }
}

/// Namespace route — groups child routes under a common path prefix.
///
/// ```swift
/// Route("/users") {
///     Route("/") { UserListPage() }
///     Route("/:id") { ctx in UserDetailPage(id: ctx.params["id"] ?? "") }
/// }
/// ```
public func Route(
    _ path: String,
    @RouteBuilder _ children: () -> [RouteDefinition]
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { _ in .text("") }, children: children())
}
