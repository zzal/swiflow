// Sources/SwiflowUI/ThemeScope.swift
//
// `Theme { }` — scope a set of `--sw-*` token overrides to a subtree. See the
// `Theme` component below; `ThemeToken` is its typed override vocabulary.

import Swiflow

/// A single `--sw-*` override for a `Theme` region. Use the typed statics for the
/// commonly-branded tokens, or `.token(_:_:)` for anything else.
public struct ThemeToken: Equatable, Sendable {
    public let name: String     // e.g. "--sw-accent"
    public let value: String

    public static func accent(_ v: String)  -> ThemeToken { .init(name: "--sw-accent",  value: v) }
    public static func radius(_ v: String)  -> ThemeToken { .init(name: "--sw-radius",  value: v) }
    public static func surface(_ v: String) -> ThemeToken { .init(name: "--sw-surface", value: v) }
    public static func text(_ v: String)    -> ThemeToken { .init(name: "--sw-text",    value: v) }
    public static func border(_ v: String)  -> ThemeToken { .init(name: "--sw-border",  value: v) }
    public static func danger(_ v: String)  -> ThemeToken { .init(name: "--sw-danger",  value: v) }
    public static func success(_ v: String) -> ThemeToken { .init(name: "--sw-success", value: v) }

    /// Escape hatch for any other token (spacing scale, motion, overlay, custom props).
    public static func token(_ name: String, _ value: String) -> ThemeToken { .init(name: name, value: value) }
}

/// Scope a set of `--sw-*` token overrides to a subtree. Renders a `display: contents`
/// wrapper carrying the overrides as inline custom properties: the wrapper's box is
/// removed (children participate in the parent's layout directly), but the element stays
/// in the DOM tree so its custom properties inherit to descendants. Zero layout impact,
/// no new stylesheet, no runtime color math — it just re-points explicit token values.
///
///     Theme(.accent("#7c3aed"), .radius("12px")) {
///         Card { Button("Branded") { … } }    // accent family + radius re-skinned here
///     }
@MainActor
public func Theme(
    _ tokens: ThemeToken...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    let styleAttrs: [Attribute] = [.style("display", "contents")] + tokens.map { .style($0.name, $0.value) }
    return element("div", attributes: styleAttrs, children: children())
}
