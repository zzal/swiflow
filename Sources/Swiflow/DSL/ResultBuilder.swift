// Sources/Swiflow/DSL/ResultBuilder.swift

/// Builds a `[VNode]` from a SwiftUI-style trailing-closure block. Supports
/// single expressions, multiple statements, optional branches, either-or
/// (`if/else`), and `for` loops.
@resultBuilder
public enum ChildrenBuilder {
    public static func buildBlock() -> [VNode] { [] }

    public static func buildBlock(_ components: [VNode]...) -> [VNode] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: VNode) -> [VNode] {
        [expression]
    }

    public static func buildExpression(_ expression: [VNode]) -> [VNode] {
        expression
    }

    public static func buildOptional(_ component: [VNode]?) -> [VNode] {
        component ?? []
    }

    public static func buildEither(first component: [VNode]) -> [VNode] {
        component
    }

    public static func buildEither(second component: [VNode]) -> [VNode] {
        component
    }

    public static func buildArray(_ components: [[VNode]]) -> [VNode] {
        components.flatMap { $0 }
    }
}
