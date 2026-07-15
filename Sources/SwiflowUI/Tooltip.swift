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
///     Tooltip("Points at me", arrow: true) { Button("Arrow") {} }
///
/// `arrow: true` draws a small triangle on the bubble's target-facing edge (the CSS
/// border trick, colored `--sw-tooltip-bg` so it always matches the bubble) and offsets
/// the bubble by the arrow's height so the triangle occupies the gap.
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
    arrow: Bool = false,
    _ attributes: Attribute...,
    content: @escaping () -> VNode
) -> VNode {
    // arrow is part of the key: keyed embeds freeze factory props at first mount,
    // so toggling it must rebuild (the message/placement precedent).
    embedKeyed("\(placement.modifierClass):\(arrow):\(message)") {
        TooltipView(message: message, placement: placement, arrow: arrow,
                    attributes: attributes, content: content)
    }
}

/// Implementation behind `Tooltip`. A `@Component` so the bubble id is pinned in `init` (stable
/// across re-renders). No lifecycle/JS — reveal is pure CSS.
@Component
final class TooltipView {
    private let message: String
    private let placement: TooltipPlacement
    private let arrow: Bool
    private let attributes: [Attribute]
    private let content: () -> VNode
    private let tipID: String

    init(message: String, placement: TooltipPlacement, arrow: Bool, attributes: [Attribute],
         content: @escaping () -> VNode) {
        self.message = message
        self.placement = placement
        self.arrow = arrow
        self.attributes = attributes
        self.content = content
        self.tipID = nextSwID("sw-tip")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-tooltip", tooltipStyleSheet)

        let trigger = addingDescribedBy(tipID, to: content())
        var bubbleClasses = ["sw-tooltip", "sw-tooltip--\(placement.modifierClass)"]
        if arrow { bubbleClasses.append("sw-tooltip--arrow") }
        let bubble = element("span", attributes: [
            .class(bubbleClasses.joined(separator: " ")),
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
    /* Inverted bubble: --sw-tooltip-bg/-text are white-on-dark-gray in BOTH schemes
       (see Theme.swift) — no border needed on a dark bubble. */
    .sw-tooltip {
      position: absolute;
      z-index: 50;
      width: max-content;
      max-width: 16rem;
      padding: var(--sw-space-xs) var(--sw-space-sm);
      font-size: 0.8125rem;
      line-height: 1.4;
      color: var(--sw-tooltip-text);
      background: var(--sw-tooltip-bg);
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
    /* A 3px standoff so the bubble never sits flush against its trigger. The
       --arrow variants below override it with the arrow's height (same property,
       higher specificity) — the triangle occupies the gap instead. Crossing the
       gap keeps the bubble hoverable: the hide transition is delayed 120ms. */
    .sw-tooltip--top      { bottom: 100%; left: 50%; transform: translateX(-50%); margin-bottom: 3px; }
    .sw-tooltip--bottom   { top: 100%; left: 50%; transform: translateX(-50%); margin-top: 3px; }
    .sw-tooltip--leading  { inset-inline-end: 100%; top: 50%; transform: translateY(-50%); margin-inline-end: 3px; }
    .sw-tooltip--trailing { inset-inline-start: 100%; top: 50%; transform: translateY(-50%); margin-inline-start: 3px; }

    /* Optional arrow: the CSS border-triangle on the bubble's target-facing edge,
       colored by the same bg token so it can't drift from the bubble. The --arrow
       margin offsets the bubble by the arrow's height (0.375em) so the triangle
       occupies the gap and visibly touches the trigger. Logical properties keep
       leading/trailing correct under RTL. */
    .sw-tooltip--arrow::after {
      content: "";
      position: absolute;
      border: 0.375em solid transparent;
    }
    .sw-tooltip--top.sw-tooltip--arrow { margin-bottom: 0.375em; }
    .sw-tooltip--top.sw-tooltip--arrow::after {
      top: 100%;
      left: 50%;
      transform: translateX(-50%);
      border-bottom-width: 0;
      border-top-color: var(--sw-tooltip-bg);
    }
    .sw-tooltip--bottom.sw-tooltip--arrow { margin-top: 0.375em; }
    .sw-tooltip--bottom.sw-tooltip--arrow::after {
      bottom: 100%;
      left: 50%;
      transform: translateX(-50%);
      border-top-width: 0;
      border-bottom-color: var(--sw-tooltip-bg);
    }
    .sw-tooltip--leading.sw-tooltip--arrow { margin-inline-end: 0.375em; }
    .sw-tooltip--leading.sw-tooltip--arrow::after {
      inset-inline-start: 100%;
      top: 50%;
      transform: translateY(-50%);
      border-inline-end-width: 0;
      border-inline-start-color: var(--sw-tooltip-bg);
    }
    .sw-tooltip--trailing.sw-tooltip--arrow { margin-inline-start: 0.375em; }
    .sw-tooltip--trailing.sw-tooltip--arrow::after {
      inset-inline-end: 100%;
      top: 50%;
      transform: translateY(-50%);
      border-inline-start-width: 0;
      border-inline-end-color: var(--sw-tooltip-bg);
    }
    """)
}
