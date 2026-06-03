// Sources/SwiflowUI/Stack.swift
import Swiflow

/// Vertical flex container. Lowers to a `<div>` with inline flex styles using
/// token vars for the spacing axis. Capitalized to distinguish SwiflowUI
/// primitives from lowercase raw HTML element factories (`div`).
@MainActor
public func VStack(
    spacing: Spacing    = .none,
    align:   CrossAlign = .stretch,
    justify: MainAlign  = .start,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    stack(direction: "column", spacing: spacing, align: align, justify: justify,
          attributes: attributes, children: children())
}

/// Horizontal flex container. See `VStack`.
@MainActor
public func HStack(
    spacing: Spacing    = .none,
    align:   CrossAlign = .stretch,
    justify: MainAlign  = .start,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    stack(direction: "row", spacing: spacing, align: align, justify: justify,
          attributes: attributes, children: children())
}

/// Shared lowering: ensure tokens are injected, build inline flex styles in a
/// deterministic order, then let caller `attributes` win (they come last, and
/// `applyAttributes` is last-write-wins).
@MainActor
private func stack(
    direction: String,
    spacing: Spacing,
    align: CrossAlign,
    justify: MainAlign,
    attributes: [Attribute],
    children: [VNode]
) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [
        .style("display", "flex"),
        .style("flex-direction", direction),
        .style("align-items", align.css),
        .style("justify-content", justify.css),
    ]
    if spacing != .none {
        styles.append(.style("gap", spacing.css))
    }
    return element("div", attributes: styles + attributes, children: children)
}
