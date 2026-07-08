// Sources/SwiflowUI/ThemeScope.swift
//
// `Theme { }` — scope a set of `--sw-*` token overrides to a subtree. See the
// `Theme` component below; `ThemeToken` is its typed override vocabulary.

import Swiflow

/// A single `--sw-*` override for a `Theme` region. Use the typed statics for the
/// commonly-branded tokens, `.set(_:_:)` for any other `Token`, or `.token(_:_:)`
/// for app-custom properties. The branded statics route through the shared
/// `Token` constants, so the write vocabulary can't drift from the read one.
public struct ThemeToken: Equatable, Sendable {
    public let name: String     // e.g. "--sw-accent"
    public let value: String

    public static func accent(_ v: String)  -> ThemeToken { .set(.accent,  v) }
    public static func radius(_ v: String)  -> ThemeToken { .set(.radius,  v) }
    public static func surface(_ v: String) -> ThemeToken { .set(.surface, v) }
    public static func text(_ v: String)    -> ThemeToken { .set(.text,    v) }
    public static func border(_ v: String)  -> ThemeToken { .set(.border,  v) }
    public static func danger(_ v: String)  -> ThemeToken { .set(.danger,  v) }
    public static func success(_ v: String) -> ThemeToken { .set(.success, v) }

    /// Override any typed token — the vocabulary door beyond the branded
    /// shortcuts, without falling back to a stringly name.
    public static func set(_ token: Token, _ value: String) -> ThemeToken {
        .init(name: token.name, value: value)
    }

    /// Escape hatch for app-custom properties (anything outside the `--sw-*`
    /// vocabulary — custom props your own CSS reads).
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
