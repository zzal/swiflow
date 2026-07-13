// Sources/SwiflowUI/Badge.swift
import Swiflow

/// Visual style of a `Badge`. `.neutral` is muted; `.accent`/`.danger`/`.success`
/// are soft tints of the matching token. Maps to a `sw-badge--<variant>` class.
public enum BadgeVariant: Equatable {
    case neutral, accent, danger, success, info, warning
    var modifierClass: String {
        switch self {
        case .neutral: return "neutral"
        case .accent:  return "accent"
        case .danger:  return "danger"
        case .success: return "success"
        case .info:    return "info"
        case .warning: return "warning"
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
///     Badge("beta", size: .sm)              // shared ControlSize scale (.xs/.sm/.md/.lg)
@MainActor
public func Badge(_ label: String, variant: BadgeVariant = .neutral,
                  size: ControlSize = .md, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-badge", badgeStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-badge", "sw-badge--\(variant.modifierClass)", "sw-badge--\(size.modifierClass)"]
        + callerClasses).joined(separator: " ")
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
      font-weight: 500;
      line-height: 1.4;
      white-space: nowrap;
    }
    /* Size = font-size only; padding/radius are em-based, so the whole pill scales. */
    .sw-badge--xs { font-size: 0.6875rem; }
    .sw-badge--sm { font-size: 0.75rem; }
    .sw-badge--md { font-size: 0.8125rem; }
    .sw-badge--lg { font-size: 0.9375rem; }
    /* Soft tint bg + the "-strong" text token: the base token is mid-tone in light
       mode and would fail WCAG on the pale tint; -strong darkens it there. */
    .sw-badge--neutral { background-color: var(--sw-surface-2); color: var(--sw-text-muted); }
    .sw-badge--accent  { background-color: color-mix(in oklab, var(--sw-accent) 15%, var(--sw-surface)); color: var(--sw-accent-strong); }
    .sw-badge--danger  { background-color: color-mix(in oklab, var(--sw-danger) 15%, var(--sw-surface)); color: var(--sw-danger-strong); }
    .sw-badge--success { background-color: color-mix(in oklab, var(--sw-success) 15%, var(--sw-surface)); color: var(--sw-success-strong); }
    .sw-badge--info    { background-color: color-mix(in oklab, var(--sw-info) 15%, var(--sw-surface)); color: var(--sw-info-strong); }
    .sw-badge--warning { background-color: color-mix(in oklab, var(--sw-warning) 15%, var(--sw-surface)); color: var(--sw-warning-strong); }
    """)
}
