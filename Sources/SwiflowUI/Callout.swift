// Sources/SwiflowUI/Callout.swift
import Swiflow

/// Severity of a `Callout`, mapped to an accent color + a live-region politeness —
/// same shape as `ToastVariant` (see Toast.swift). `.danger` is announced assertively.
public enum CalloutVariant: Equatable {
    case info, success, warning, danger
    var modifierClass: String {
        switch self {
        case .info:    return "info"
        case .success: return "success"
        case .warning: return "warning"
        case .danger:  return "danger"
        }
    }
    /// Danger interrupts (role=alert + aria-live=assertive); info/success/warning are polite.
    var isAssertive: Bool { self == .danger }
}

/// A stateless semantic status banner — a bordered, soft-tinted `<div>` with an
/// optional title, a message, and an optional actions slot. Unlike `Badge` (a soft
/// pill for compact status) or `Toast` (a transient, self-dismissing queue item),
/// `Callout` is a persistent, in-flow banner: reach for it to surface a standing
/// notice inline in a page (an empty-state hint, a form-level error, a success
/// confirmation after a save). No icon — that lands in M14.
///
///     Callout("Your session will expire soon.", variant: .warning, title: "Heads up")
///     Callout("Changes saved.", variant: .success)
///     Callout("Couldn't reach the server.", variant: .danger) {
///         Button("Retry") { retry() }
///     }
@MainActor
public func Callout(
    _ message: String,
    variant: CalloutVariant = .info,
    title: String? = nil,
    _ attributes: Attribute...,
    @ChildrenBuilder actions: () -> [VNode] = { [] }
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-callout", calloutStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-callout", "sw-callout--\(variant.modifierClass)"] + callerClasses)
        .joined(separator: " ")

    var children: [VNode] = []
    if let title {
        children.append(h3(title, .class("sw-callout__title")))
    }
    children.append(p(message, .class("sw-callout__message")))
    let actionNodes = actions()
    if !actionNodes.isEmpty {
        children.append(element("div", attributes: [.class("sw-callout__actions")], children: actionNodes))
    }

    return element("div", attributes: [
        .class(classValue),
        .attr("role", variant.isAssertive ? "alert" : "status"),
        .attr("aria-live", variant.isAssertive ? "assertive" : "polite"),
    ] + callerRest, children: children)
}

/// Global `.sw-callout*` sheet. A bordered banner (unlike Badge's soft-tint pill):
/// a per-variant accent rail (`border-inline-start`) plus a very light 8% tint
/// background. `--sw-text` stays readable on that tint (8% is near-`--sw-surface`,
/// so it doesn't hit the light-mode soft-tint contrast trap Badge's 15% pill would —
/// see [[swiflowui-soft-tint-contrast]]); the title uses the matching `-strong` token
/// for its colored emphasis, mirroring Badge.
let calloutStyleSheet: CSSSheet = css {
    raw("""
    .sw-callout {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-xs);
      padding: var(--sw-space-md);
      border-radius: var(--sw-radius);
      border-inline-start: 3px solid var(--sw-info);
      background-color: color-mix(in oklab, var(--sw-info) 8%, var(--sw-surface));
      color: var(--sw-text);
    }
    .sw-callout__title { margin: 0; font-size: 0.9375rem; font-weight: 600; color: var(--sw-info-strong); }
    .sw-callout__message { margin: 0; color: var(--sw-text); }
    .sw-callout__actions { display: flex; gap: var(--sw-space-sm); margin-top: var(--sw-space-xs); }
    .sw-callout--success { border-inline-start-color: var(--sw-success); background-color: color-mix(in oklab, var(--sw-success) 8%, var(--sw-surface)); }
    .sw-callout--success .sw-callout__title { color: var(--sw-success-strong); }
    .sw-callout--warning { border-inline-start-color: var(--sw-warning); background-color: color-mix(in oklab, var(--sw-warning) 8%, var(--sw-surface)); }
    .sw-callout--warning .sw-callout__title { color: var(--sw-warning-strong); }
    .sw-callout--danger  { border-inline-start-color: var(--sw-danger);  background-color: color-mix(in oklab, var(--sw-danger) 8%, var(--sw-surface)); }
    .sw-callout--danger .sw-callout__title { color: var(--sw-danger-strong); }
    """)
}
