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
}
