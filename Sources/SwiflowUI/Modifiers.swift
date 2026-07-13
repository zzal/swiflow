// Sources/SwiflowUI/Modifiers.swift
import Swiflow

public extension VNode {
    /// Adds (or overwrites) padding on the given `edges` using a `--sw-space-*` token (or raw
    /// length). Edges are logical (RTL-aware); defaults to `.all`, so `.padding(.md)` is unchanged.
    /// Emits the four atomic logical longhands (`padding-block-start/-end`, `padding-inline-start/-end`)
    /// — never a shorthand — so chained calls compose deterministically:
    /// `.padding(.lg).padding(.md, .horizontal)` ⇒ block `lg`, inline `md`. A no-op on non-element
    /// nodes (the core `style(_:_:)` diagnostic path).
    func padding(_ s: Spacing, _ edges: Edge = .all) -> VNode {
        var node = self
        for side in edges.logicalSides {
            node = node.style("padding-\(side)", s.css)
        }
        return node
    }

    /// Adds (or overwrites) `gap` using a `--sw-space-*` token (or raw length).
    func gap(_ s: Spacing) -> VNode { style("gap", s.css) }

    /// Makes this item span `n` columns of a `Grid` — sets `grid-column: span n`.
    /// `n` is clamped to at least 1 (a non-positive span is treated as no span).
    /// Meaningful on a direct child of a CSS grid; a no-op on non-element nodes.
    ///
    ///     Grid(columns: 3, spacing: .md) {
    ///         card("Wide").colSpan(2)   // takes two of the three columns
    ///         card("Normal")
    ///     }
    func colSpan(_ n: Int) -> VNode { style("grid-column", "span \(max(1, n))") }

    /// Makes this item span `n` rows of a `Grid` — sets `grid-row: span n`.
    /// `n` is clamped to at least 1. See `colSpan(_:)`.
    func rowSpan(_ n: Int) -> VNode { style("grid-row", "span \(max(1, n))") }
}
