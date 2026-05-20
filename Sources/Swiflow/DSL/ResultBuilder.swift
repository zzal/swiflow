// Sources/Swiflow/DSL/ResultBuilder.swift

/// Builds a `[VNode]` from a SwiftUI-style trailing-closure block. Supports
/// single expressions, multiple statements, optional branches, either-or
/// (`if/else`), and `for` loops.
@resultBuilder
public enum ChildrenBuilder {
    /// Empty block produces no children.
    public static func buildBlock() -> [VNode] { [] }

    /// Concatenates per-statement child arrays in source order.
    public static func buildBlock(_ children: [VNode]...) -> [VNode] {
        children.flatMap { $0 }
    }

    /// Lifts a single `VNode` expression into a one-element array.
    public static func buildExpression(_ expression: VNode) -> [VNode] {
        [expression]
    }

    /// Passes through a `[VNode]` expression (e.g. a spread of pre-built
    /// children).
    public static func buildExpression(_ expression: [VNode]) -> [VNode] {
        expression
    }

    /// Resolves an `if`-without-`else` branch: present children, or none.
    public static func buildOptional(_ component: [VNode]?) -> [VNode] {
        component ?? []
    }

    /// Resolves the `if` branch of an `if/else`.
    public static func buildEither(first component: [VNode]) -> [VNode] {
        component
    }

    /// Resolves the `else` branch of an `if/else`.
    public static func buildEither(second component: [VNode]) -> [VNode] {
        component
    }

    /// Flattens children produced by a `for` loop into a single array.
    public static func buildArray(_ children: [[VNode]]) -> [VNode] {
        children.flatMap { $0 }
    }
}
