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
    ///
    /// NOTE: a raw `[VNode]` spread is flattened, NOT wrapped in a stable slot
    /// (unlike `if`/`for`, which become one `.fragment` slot each). If the array
    /// is dynamically sized and has siblings, a length change will shift those
    /// siblings — wrap it in a `for` loop (and `.key(...)` the items) so the
    /// slot stays positionally stable.
    public static func buildExpression(_ expression: [VNode]) -> [VNode] {
        expression
    }

    /// An `if`-without-`else` is one stable slot: its content, or an empty
    /// fragment when false (the slot persists so siblings never shift).
    public static func buildOptional(_ component: [VNode]?) -> [VNode] {
        [.fragment(component ?? [])]
    }

    /// The `if` branch of an `if/else` — one stable slot holding the branch.
    /// The slot occupies the same child index whichever branch is active, so a
    /// condition flip updates the one fragment in place and never shifts later
    /// siblings.
    public static func buildEither(first component: [VNode]) -> [VNode] {
        [.fragment(component)]
    }

    /// The `else` branch of an `if/else` — one stable slot holding the branch.
    /// Same index as the `if` branch (see `buildEither(first:)`).
    public static func buildEither(second component: [VNode]) -> [VNode] {
        [.fragment(component)]
    }

    /// A `for` loop is one stable slot holding all its items. Key items with
    /// `.key(...)` so they keep identity across reorders.
    public static func buildArray(_ children: [[VNode]]) -> [VNode] {
        [.fragment(children.flatMap { $0 })]
    }

    @available(*, unavailable, message: "Use text(\"...\") to display a String")
    public static func buildExpression(_ expression: String) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(n) to display an integer")
    public static func buildExpression<I: BinaryInteger>(_ expression: I) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(n) to display a floating-point number")
    public static func buildExpression<F: BinaryFloatingPoint>(_ expression: F) -> [VNode] { [] }

    @available(*, unavailable, message: "Use text(flag) to display a Bool")
    public static func buildExpression(_ expression: Bool) -> [VNode] { [] }
}
