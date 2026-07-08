// Sources/SwiflowUI/Card.swift
import Swiflow

/// Visual style of a `Card`: `.elevated` (a `--sw-shadow` drop shadow),
/// `.outlined` (a `--sw-border` outline), or `.plain` — the bare padded
/// surface, nothing added (the base `.sw-card` class is already
/// background + radius + padding; use it for the surface/radius tile
/// otherwise hand-written with `.style` pairs). Maps to a
/// `sw-card--<variant>` class.
public enum CardVariant: Equatable {
    case elevated, outlined, plain
    var modifierClass: String {
        switch self {
        case .elevated: return "elevated"
        case .outlined: return "outlined"
        case .plain:    return "plain"
        }
    }
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
      /* Own the internal rhythm via gap rather than children's UA margins:
         the base reset zeroes heading/paragraph block margins, so a plain
         block card would collapse its title onto its body. Matches the
         flex-column-gap pattern used by Field/Toast/Prompt. */
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-md);
    }
    /* hairline edge + the big soft drop (matches the HelloWorld card lift) */
    .sw-card--elevated { box-shadow: 0 1px 0 var(--sw-border), var(--sw-shadow); }
    .sw-card--outlined { border: var(--sw-border-width) solid var(--sw-border); }
    """)
}
