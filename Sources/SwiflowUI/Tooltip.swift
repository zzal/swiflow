// Sources/SwiflowUI/Tooltip.swift
import Swiflow

/// Placement of a `Tooltip` bubble relative to its trigger. `.leading`/`.trailing` use logical
/// offsets, so they flip under RTL.
public enum TooltipPlacement: Equatable {
    case top, bottom, leading, trailing
    var modifierClass: String {
        switch self {
        case .top:      return "top"
        case .bottom:   return "bottom"
        case .leading:  return "leading"
        case .trailing: return "trailing"
        }
    }
}

/// A descriptive overlay shown on hover and keyboard focus of its trigger. CSS-only — no JS:
/// `:hover`/`:focus-within` on the wrapper reveal a `role="tooltip"` bubble, and `aria-describedby`
/// links the trigger to it so screen readers announce it on focus.
///
///     Tooltip("Delete permanently") { Button("Delete", variant: .danger) { delete() } }
///     Tooltip("Appears below", placement: .bottom) { Button("Below") {} }
///
/// Caller `Attribute...`/`.class` merge onto the WRAPPER. The bubble is a text label only.
///
/// Backed by a `@Component` purely so the bubble's id is generated ONCE (in `init`) and stays
/// stable across re-renders — a bare free function would mint a fresh `nextSwID` every render,
/// churning the bubble `id` + the trigger's `aria-describedby` (re-announcing on focus). The embed
/// key is derived from the message + placement, so changing either rebuilds with a fresh bubble
/// (no stale-prop pitfall).
///
/// > A11y: revealed on hover AND focus, and "hoverable" (the pointer can move onto the bubble). It
/// > does NOT support Escape-to-dismiss (CSS can't handle keys), so it does not fully meet WCAG
/// > 1.4.13; a future JS-driven variant would add dismissal. Positioned with plain absolute offsets
/// > (every engine); not in the top layer, so an `overflow: hidden`/`clip` ancestor can crop it.
@MainActor
public func Tooltip(
    _ message: String,
    placement: TooltipPlacement = .top,
    _ attributes: Attribute...,
    content: @escaping () -> VNode
) -> VNode {
    embedKeyed("\(placement.modifierClass):\(message)") {
        TooltipView(message: message, placement: placement, attributes: attributes, content: content)
    }
}

/// Implementation behind `Tooltip`. A `@Component` so the bubble id is pinned in `init` (stable
/// across re-renders). No lifecycle/JS — reveal is pure CSS.
@MainActor @Component
final class TooltipView {
    private let message: String
    private let placement: TooltipPlacement
    private let attributes: [Attribute]
    private let content: () -> VNode
    private let tipID: String

    init(message: String, placement: TooltipPlacement, attributes: [Attribute],
         content: @escaping () -> VNode) {
        self.message = message
        self.placement = placement
        self.attributes = attributes
        self.content = content
        self.tipID = nextSwID("sw-tip")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-tooltip", tooltipStyleSheet)

        let trigger = addingDescribedBy(tipID, to: content())
        let bubble = element("span", attributes: [
            .class("sw-tooltip sw-tooltip--\(placement.modifierClass)"),
            .attr("role", "tooltip"),
            .attr("id", tipID),
        ], children: [.text(message)])

        let (callerClasses, callerRest) = splitClasses(attributes)
        let wrapClass = (["sw-tooltip-wrap"] + callerClasses).joined(separator: " ")
        return element("span", attributes: [.class(wrapClass)] + callerRest,
                       children: [trigger, bubble])
    }
}

/// Add `aria-describedby` to a single-element trigger so SR announces the bubble on focus.
/// Non-element triggers (component anchors, text, fragments) are returned unchanged — the
/// visual tooltip still works; only the explicit SR link is skipped.
func addingDescribedBy(_ id: String, to node: VNode) -> VNode {
    guard case .element(var data) = node else { return node }
    if let existing = data.attributes["aria-describedby"], !existing.isEmpty {
        data.attributes["aria-describedby"] = existing + " " + id
    } else {
        data.attributes["aria-describedby"] = id
    }
    return .element(data)
}

let tooltipStyleSheet: CSSSheet = css {
    raw("""
    .sw-tooltip-wrap {
      position: relative;
      display: inline-block;
    }
    .sw-tooltip {
      position: absolute;
      z-index: 50;
      width: max-content;
      max-width: 16rem;
      padding: var(--sw-space-xs) var(--sw-space-sm);
      font-size: 0.8125rem;
      line-height: 1.4;
      color: var(--sw-text);
      background: var(--sw-surface);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius-sm);
      box-shadow: var(--sw-shadow);
      opacity: 0;
      visibility: hidden;
      transition: opacity var(--sw-duration) var(--sw-ease),
                  visibility var(--sw-duration) var(--sw-ease);
      transition-delay: 120ms;
    }
    .sw-tooltip-wrap:hover .sw-tooltip,
    .sw-tooltip-wrap:focus-within .sw-tooltip {
      opacity: 1;
      visibility: visible;
      transition-delay: 0s;
    }
    .sw-tooltip--top      { bottom: 100%; left: 50%; transform: translateX(-50%); }
    .sw-tooltip--bottom   { top: 100%; left: 50%; transform: translateX(-50%); }
    .sw-tooltip--leading  { inset-inline-end: 100%; top: 50%; transform: translateY(-50%); }
    .sw-tooltip--trailing { inset-inline-start: 100%; top: 50%; transform: translateY(-50%); }
    """)
}
