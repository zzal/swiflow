// Sources/SwiflowUI/Popover.swift
import Swiflow

/// Where a `Popover` panel opens relative to its trigger (CSS Anchor Positioning
/// `position-area`). Unlike `DropdownPlacement` (which pairs a side with a start/end
/// alignment for a menu that must not overhang the trigger), a `Popover` panel is
/// free-form content, so each case is a single side, centered on the trigger.
public enum PopoverPlacement: Equatable {
    case top, bottom, leading, trailing
    var positionArea: String {
        switch self {
        case .top:      return "top"
        case .bottom:   return "bottom"
        case .leading:  return "inline-start"
        case .trailing: return "inline-end"
        }
    }
    /// The margin property that pushes the panel AWAY from its anchor for this
    /// placement — how `offset:` lowers (a margin insets within the position-area).
    var offsetMarginProperty: String {
        switch self {
        case .top:      return "margin-bottom"
        case .bottom:   return "margin-top"
        case .leading:  return "margin-inline-end"
        case .trailing: return "margin-inline-start"
        }
    }
}

/// A general-purpose **anchored panel**: any caller trigger reveals any caller content
/// in a top-layer popover, positioned relative to the trigger. Where `Dropdown` bakes in
/// a specific shape (a button trigger + a `role="menu"` list of actions), `Popover` is the
/// escape hatch — arbitrary trigger, arbitrary content, from a details flyout to a mini
/// form. Built on the same Popover API (`popover="auto"`) + CSS Anchor Positioning as
/// `Dropdown`, so it gets top-layer rendering, ESC + light-dismiss for free.
///
///     Popover(placement: .bottom) {
///         Button("Details…", variant: .secondary) {}
///     } content: {
///         p("Extra information about this row.")
///         Link("/docs", "Learn more")
///     }
///
/// `offset:` (px, default 0 — flush) pushes the panel away from its trigger along the
/// placement axis, e.g. `offset: 3` for the same small standoff Tooltip uses.
///
/// Caller `Attribute...`/`.class` land on the PANEL (applied last, after the panel's own
/// classes/attrs) — for the trigger's own styling, style the element you pass to
/// `trigger:` directly (its classes/attrs are preserved; see the note below).
///
/// > Note: `placement`/`attributes`/`trigger`/`content` update LIVE — the facade pushes
/// > them into the reused panel on every parent re-render (mirrors `Modal`/`Alert`).
/// > `key:` remains available for a full remount instead (fresh entry animation).
///
/// > The `trigger` builder must yield exactly **one** element — `Popover` rebuilds that
/// > element with `popovertarget`/`anchor-name` appended, preserving its own classes and
/// > attributes untouched. Wrap multiple nodes in a single container element.
///
/// > Anchor positioning is Baseline-newer (Chromium/Safari; not yet Firefox). Where it's
/// > unsupported the panel still opens (a centered popover), just not anchored to the
/// > trigger.
@MainActor
public func Popover(
    placement: PopoverPlacement = .bottom,
    offset: Double = 0,
    _ attributes: Attribute...,
    key: String? = nil,
    @ChildrenBuilder trigger: @escaping () -> [VNode],
    @ChildrenBuilder content: @escaping () -> [VNode]
) -> VNode {
    embedKeyed(key, {
        PopoverPanel(placement: placement, offset: offset, panelAttrs: attributes,
                     trigger: trigger, content: content)
    }, refresh: { panel in
        // Thread the display props LIVE into the reused instance, mirroring
        // Alert/Modal (audit V Wave-2 #6).
        panel.placement = placement
        panel.offset = offset
        panel.panelAttrs = attributes
        panel.trigger = trigger
        panel.content = content
    })
}

/// The implementation behind `Popover`. A `@Component` purely so the popover id is
/// generated ONCE (in `init`) and stays stable across re-renders — a stateless free
/// function would regenerate it every render via `nextSwID`, breaking the
/// trigger↔panel `popovertarget` pairing and the popover's open/close state. No
/// lifecycle/JS: open/close/anchor are all native (Popover API + anchor positioning) —
/// same rationale as `DropdownMenu`.
@Component
final class PopoverPanel {
    var placement: PopoverPlacement
    var offset: Double
    var panelAttrs: [Attribute]
    var trigger: () -> [VNode]
    var content: () -> [VNode]
    private let panelID: String

    init(placement: PopoverPlacement, offset: Double, panelAttrs: [Attribute],
         trigger: @escaping () -> [VNode], content: @escaping () -> [VNode]) {
        self.placement = placement
        self.offset = offset
        self.panelAttrs = panelAttrs
        self.trigger = trigger
        self.content = content
        self.panelID = nextSwID("sw-popover")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-popover", popoverStyleSheet)

        let anchor = "--\(panelID)"   // per-instance dashed-ident, so popovers don't cross-anchor

        let triggerNodes = wiredTrigger(trigger(), panelID: panelID, anchor: anchor)

        var panelStyles: [Attribute] = [
            .style("position-anchor", anchor),
            .style("position-area", placement.positionArea),
        ]
        // offset: push away from the anchor along the placement axis (the sheet's
        // `margin: 0` stays for the other three sides; inline wins for this one).
        if offset > 0 {
            panelStyles.append(.style(placement.offsetMarginProperty, "\(formatControlNumber(offset))px"))
        }

        let panel = element("div", attributes: [
            .class("sw-popover"),
            .attr("popover", "auto"),
            .attr("id", panelID),
        ] + panelStyles + panelAttrs, children: content())

        return element("div", attributes: [.class("sw-popover-root")], children: triggerNodes + [panel])
    }
}

/// Post-processes the `trigger` builder's output into the single element `popovertarget`
/// pairs with the panel: appends `.attr("popovertarget", panelID)` +
/// `.style("anchor-name", anchor)`, rebuilding the element (the `rovingMenuItems` pattern
/// in `Dropdown.swift`) so its own classes/attrs are preserved untouched — only those two
/// keys are added/overwritten.
///
/// DEBUG-diagnoses when the builder didn't yield exactly one element: `Popover` can only
/// wire a single DOM node to `popovertarget`/`anchor-name`, so multiple nodes or a
/// non-element (text, fragment, component) can't be popover-anchored. Degrades in
/// release: the raw node(s) pass through unwired — the panel still renders (just not
/// triggered/anchored by this content), the same tolerant-degrade style as Tooltip's
/// `addingDescribedBy`.
@MainActor
private func wiredTrigger(_ nodes: [VNode], panelID: String, anchor: String) -> [VNode] {
    guard nodes.count == 1, case .element = nodes[0] else {
        swiflowDiagnostic("SwiflowUI Popover: the `trigger` builder must yield exactly one element (got \(nodes.count) node(s)) so Popover can wire `popovertarget`/`anchor-name` onto it. Wrap multiple nodes in a single container element.")
        return nodes
    }
    return [nodes[0].attr("popovertarget", panelID).style("anchor-name", anchor)]
}

/// Global `.sw-popover*` sheet. The panel is a Popover-API panel anchored to the trigger;
/// entry/exit read `--sw-duration` (reduced-motion → instant). Token-driven throughout.
let popoverStyleSheet: CSSSheet = css {
    raw("""
    .sw-popover-root { display: inline-block; }

    .sw-popover {
      margin: 0;
      inset: auto;                        /* let position-area place it; avoid the UA's centering */
      max-width: min(90vw, 20rem);
      padding: var(--sw-space-md);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      box-shadow: var(--sw-shadow);
    }
    /* entry/exit animation — the shared quartet (see PopoverTransition.swift) */
    \(popoverTransitionCSS(
        base: ".sw-popover", open: ".sw-popover:popover-open",
        closedTransform: "translateY(4px) scale(0.98)", openTransform: "translateY(0) scale(1)"))
    """)
}
