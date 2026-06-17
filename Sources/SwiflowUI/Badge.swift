// Sources/SwiflowUI/Badge.swift
import Swiflow

/// Visual style of a `Badge`. `.neutral` is muted; `.accent`/`.danger`/`.success`
/// are soft tints of the matching token. Maps to a `sw-badge--<variant>` class.
public enum BadgeVariant: Equatable {
    case neutral, accent, danger, success
    var modifierClass: String {
        switch self {
        case .neutral: return "neutral"
        case .accent:  return "accent"
        case .danger:  return "danger"
        case .success: return "success"
        }
    }
}

/// A small status / count pill. Stateless free function: a styled `<span>`.
/// Variants are *soft* (a `color-mix` tint of the token as background + the token
/// as text), so the label stays readable in light and dark without needing
/// per-variant text tokens. Caller `Attribute...`/`.class` merge onto the badge.
///
///     Badge("New", variant: .accent)
///     Badge("3")
@MainActor
public func Badge(_ label: String, variant: BadgeVariant = .neutral, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-badge", badgeStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-badge", "sw-badge--\(variant.modifierClass)"] + callerClasses)
        .joined(separator: " ")
    return element("span", attributes: [.class(classValue)] + callerRest, children: [text(label)])
}

let badgeStyleSheet: CSSSheet = css {
    raw("""
    .sw-badge {
      display: inline-flex;
      align-items: center;
      gap: var(--sw-space-xs);
      padding: 0.15em 0.6em;
      border-radius: 1em;
      font-size: 0.8125rem;
      font-weight: 500;
      line-height: 1.4;
      white-space: nowrap;
    }
    /* Soft tint bg + the "-strong" text token: the base token is mid-tone in light
       mode and would fail WCAG on the pale tint; -strong darkens it there. */
    .sw-badge--neutral { background-color: var(--sw-surface-2); color: var(--sw-text-muted); }
    .sw-badge--accent  { background-color: color-mix(in oklab, var(--sw-accent) 15%, var(--sw-surface)); color: var(--sw-accent-strong); }
    .sw-badge--danger  { background-color: color-mix(in oklab, var(--sw-danger) 15%, var(--sw-surface)); color: var(--sw-danger-strong); }
    .sw-badge--success { background-color: color-mix(in oklab, var(--sw-success) 15%, var(--sw-surface)); color: var(--sw-success-strong); }
    """)
}
