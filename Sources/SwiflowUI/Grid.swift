// Sources/SwiflowUI/Grid.swift
import Swiflow

/// Track sizing for `Grid`'s columns. `.count(n)` lays out `n` equal columns
/// (`repeat(n, minmax(0, 1fr))` — the `minmax(0, …)` floor stops a wide child
/// from blowing the track past the container, the usual CSS-grid footgun);
/// `.template` passes a raw `grid-template-columns` value through untouched.
/// Integer and string literals map to `.count` / `.template`, so callers write
/// `Grid(columns: 3)` or `Grid(columns: "1fr 2fr")` directly.
public enum GridColumns: Equatable, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    case count(Int)
    case template(String)

    public init(integerLiteral value: Int) { self = .count(value) }
    public init(stringLiteral value: String) { self = .template(value) }

    public var css: String {
        switch self {
        case .count(let n):    return "repeat(\(n), minmax(0, 1fr))"
        case .template(let t): return t
        }
    }
}

/// CSS-grid container. Lowers to a `<div>` with `display: grid` and an inline
/// `grid-template-columns`, using a `--sw-space-*` token for the gap. Kept
/// deliberately 2-D-thin: `columns` + `spacing` only. Per-item alignment in a
/// grid (`justify-items` / `place-items`) is nuanced enough that it's left to
/// explicit `.style(…)` overrides rather than guessing a stack-style mapping.
/// Capitalized to distinguish SwiflowUI primitives from raw HTML factories.
@MainActor
public func Grid(
    columns: GridColumns,
    spacing: Spacing = .none,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [
        .style("display", "grid"),
        .style("grid-template-columns", columns.css),
    ]
    if spacing != .none {
        styles.append(.style("gap", spacing.css))
    }
    // Caller attributes come last: last-write-wins (see `applyAttributes`).
    return element("div", attributes: styles + attributes, children: children())
}
