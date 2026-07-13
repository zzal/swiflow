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

/// The declarations that re-derive the accent FAMILY (hover / active / strong /
/// text) and the focus ring FROM `--sw-accent`. These live at `:root`
/// (`baseStyleSheet`), so a *scoped* `--sw-accent` override doesn't re-resolve
/// them on its own — a registered custom property computes its `var(--sw-accent)`
/// at the point it's declared (`:root`), not where it's used. Re-emitting them
/// wherever `--sw-accent` is re-pointed makes the whole family cascade in that
/// subtree: focused borders and the focus ring (`--sw-focus-shadow` reads
/// `var(--sw-focus-ring)` at *use* time, so re-declaring the ring is enough) and
/// button hover/active — not just the direct-`var(--sw-accent)` fills. `Theme`
/// does this automatically for `.accent(_:)`; a raw inline override should fold
/// these in too (the catalog playground does). Keep in lockstep with the matching
/// derivations in `baseStyleSheet` — `ThemeScopeTests` guards it.
public let swAccentFamilyDerivations: [(name: String, value: String)] = [
    ("--sw-accent-hover",  "light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h), oklch(from var(--sw-accent) calc(l + 0.08) c h))"),
    ("--sw-accent-active", "light-dark(oklch(from var(--sw-accent) calc(l - 0.16) c h), oklch(from var(--sw-accent) calc(l + 0.16) c h))"),
    ("--sw-accent-text",   "contrast-color(var(--sw-accent))"),
    ("--sw-accent-strong", "light-dark(oklch(from var(--sw-accent) 0.40 c h), oklch(from var(--sw-accent) 0.80 c h))"),
    ("--sw-focus-ring",    "var(--sw-accent)"),
]

/// Scope a set of `--sw-*` token overrides to a subtree. Renders a `display: contents`
/// wrapper carrying the overrides as inline custom properties: the wrapper's box is
/// removed (children participate in the parent's layout directly), but the element stays
/// in the DOM tree so its custom properties inherit to descendants. Zero layout impact,
/// no new stylesheet, no runtime color math — it just re-points explicit token values.
///
/// When `.accent(_:)` is among the overrides, the accent family (hover/active/strong/
/// text) and the focus ring re-derive here too (see `swAccentFamilyDerivations`), so
/// the branded accent cascades to focus rings and borders, not only direct fills.
///
///     Theme(.accent("#7c3aed"), .radius("12px")) {
///         Card { Button("Branded") { … } }    // accent family + radius re-skinned here
///     }
@MainActor
public func Theme(
    _ tokens: ThemeToken...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    Theme(tokens, children: children)
}

/// Array-taking twin of `Theme(_:children:)`, for a token list built at runtime.
@MainActor
public func Theme(
    _ tokens: [ThemeToken],
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    var styleAttrs: [Attribute] = [.style("display", "contents")] + tokens.map { .style($0.name, $0.value) }
    if tokens.contains(where: { $0.name == Token.accent.name }) {
        styleAttrs += swAccentFamilyDerivations.map { .style($0.name, $0.value) }
    }
    return element("div", attributes: styleAttrs, children: children())
}
