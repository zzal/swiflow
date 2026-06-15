// Sources/SwiflowUI/Card.swift
import Swiflow

/// Visual style of a `Card`: `.elevated` (a `--sw-shadow` drop shadow) or
/// `.outlined` (a `--sw-border` outline). Maps to a `sw-card--<variant>` class.
public enum CardVariant: Equatable {
    case elevated, outlined
    public var modifierClass: String { self == .elevated ? "elevated" : "outlined" }
}

/// A surfaced container. Stateless free function: a `<div>` with `--sw-surface`
/// background, `--sw-radius`, padding, and either elevation (`--sw-shadow`) or an
/// outline (`--sw-border`). Everything reads tokens, so it re-skins and honors the
/// media layers (dark/contrast) for free. Caller `Attribute...`/`.class` merge onto
/// the card root.
///
///     Card { h3("Title"); p("Body") }
///     Card(variant: .outlined) { … }
@MainActor
public func Card(
    variant: CardVariant = .elevated,
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-card", cardStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-card", "sw-card--\(variant.modifierClass)"] + callerClasses)
        .joined(separator: " ")
    return element("div", attributes: [.class(classValue)] + callerRest, children: children())
}

let cardStyleSheet: CSSSheet = css {
    raw("""
    .sw-card {
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border-radius: var(--sw-radius);
      padding: var(--sw-space-lg);
    }
    /* hairline edge + the big soft drop (matches the HelloWorld card lift) */
    .sw-card--elevated { box-shadow: 0 1px 0 var(--sw-border), var(--sw-shadow); }
    .sw-card--outlined { border: var(--sw-border-width) solid var(--sw-border); }
    """)
}
