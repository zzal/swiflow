// Sources/SwiflowUI/Modifiers.swift
import Swiflow

public extension VNode {
    /// Adds (or overwrites) `padding` using a `--sw-space-*` token (or raw
    /// length). Thin wrapper over the core `VNode.style(_:_:)` postfix modifier;
    /// a no-op on non-element nodes (the existing diagnostic path).
    func padding(_ s: Spacing) -> VNode { style("padding", s.css) }

    /// Adds (or overwrites) `gap` using a `--sw-space-*` token (or raw length).
    func gap(_ s: Spacing) -> VNode { style("gap", s.css) }
}
