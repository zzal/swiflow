// Sources/SwiflowUI/Dropdown.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// Where the menu opens relative to its trigger (CSS Anchor Positioning `position-area`).
public enum DropdownPlacement: Equatable {
    case bottomStart, bottomEnd, topStart, topEnd
    var positionArea: String {
        switch self {
        case .bottomStart: return "bottom span-right"   // below, left edges aligned
        case .bottomEnd:   return "bottom span-left"     // below, right edges aligned
        case .topStart:    return "top span-right"
        case .topEnd:      return "top span-left"
        }
    }
}

/// Visual treatment of a `DropdownItem`.
public enum DropdownItemVariant: Equatable {
    case normal, danger
    var modifierClass: String { self == .danger ? "danger" : "normal" }
}

/// Render-time channel passing the open menu's id down to its `DropdownItem`s so
/// each can declaratively close the menu on select (`popovertargetaction="hide"`),
/// without the caller threading the id by hand. Same shape as `HandlerAmbient`:
/// set synchronously while the items builder runs, then restored.
@MainActor
enum DropdownAmbient {
    static var currentMenuID: String?
}

/// A **menu** of actions (WAI-ARIA `role="menu"`): a trigger button that reveals an anchored
/// popover of `role="menuitem"` items.
///
/// Native-first and lifecycle-free — no runtime state. (It's a `@Component` only to pin a stable
/// popover id across re-renders; see `DropdownMenu` below.) Built on the Popover API
/// (`popover="auto"`) + CSS Anchor Positioning, so it gets top-layer rendering, ESC + click-outside
/// dismissal, and trigger-anchored placement for free; each item closes the menu on select via
/// `popovertargetaction="hide"`.
///
/// **Keyboard (roving tabindex — the APG menu pattern):** Enter/Space on the trigger opens the
/// menu and focus lands on the first item (native `autofocus`); ↑/↓ move between items and wrap;
/// Home/End jump to the first/last; Enter/Space activate the focused item and close; Esc closes and
/// returns focus to the trigger; Tab closes the menu. Disabled items are `inert` and skipped.
///
///     Dropdown("Actions") {
///         DropdownItem("Edit") { edit() }
///         DropdownItem("Duplicate") { duplicate() }
///         DropdownDivider()
///         DropdownItem("Delete", variant: .danger) { delete() }
///     }
///
/// Caller `Attribute...`/`.class` land on the trigger button.
///
/// > Note: `label`/`placement` and the `items` builder are captured when the dropdown is
/// > first mounted (the component is `embed`-reused, to keep a stable popover id across
/// > re-renders). For a dropdown whose label or items change while mounted, pass a `key:`
/// > that changes with them so the menu is rebuilt with fresh props.
///
/// > Anchor positioning is Baseline-newer (Chromium/Safari; not yet Firefox). Where it's
/// > unsupported the menu still opens (a centered popover), just not anchored to the trigger.
@MainActor
public func Dropdown(
    _ label: String,
    placement: DropdownPlacement = .bottomStart,
    _ attributes: Attribute...,
    key: String? = nil,
    @ChildrenBuilder items: @escaping () -> [VNode]
) -> VNode {
    embedKeyed(key) { DropdownMenu(label: label, placement: placement, triggerAttrs: attributes, items: items) }
}

/// The implementation behind `Dropdown`. A `@Component` purely so the popover id is
/// generated ONCE (in `init`) and stays stable across re-renders — a stateless free
/// function would regenerate it every render via `nextSwID`, breaking the
/// trigger↔menu `popovertarget` pairing and the popover's open/close state. No
/// lifecycle/JS: open/close/anchor are all native (Popover API + anchor positioning).
@Component
final class DropdownMenu {
    private let label: String
    private let placement: DropdownPlacement
    private let triggerAttrs: [Attribute]
    private let items: () -> [VNode]
    private let menuID: String

    init(label: String, placement: DropdownPlacement, triggerAttrs: [Attribute], items: @escaping () -> [VNode]) {
        self.label = label
        self.placement = placement
        self.triggerAttrs = triggerAttrs
        self.items = items
        self.menuID = nextSwID("sw-dropdown")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-button", buttonStyleSheet)   // the trigger reuses .sw-btn styling
        installControlSheet(id: "sw-dropdown", dropdownStyleSheet)

        let anchor = "--\(menuID)"   // per-instance dashed-ident, so dropdowns don't cross-anchor

        // Items read the menu id from the ambient to wire close-on-select.
        let prev = DropdownAmbient.currentMenuID
        DropdownAmbient.currentMenuID = menuID
        let rawItems = items()
        DropdownAmbient.currentMenuID = prev
        let itemNodes = rovingMenuItems(rawItems)

        let (callerClasses, callerRest) = splitClasses(triggerAttrs)
        let triggerClass = (["sw-btn", "sw-btn--secondary", "sw-btn--md", "sw-dropdown__trigger"] + callerClasses)
            .joined(separator: " ")

        let trigger = element("button", attributes: [
            .class(triggerClass),
            .attr("type", "button"),
            .attr("popovertarget", menuID),
            .attr("aria-haspopup", "menu"),
            .style("anchor-name", anchor),
        ] + callerRest, children: [
            text(label),
            // Empty — the chevron is drawn by masking the shared SVG (see the sheet).
            element("span", attributes: [.class("sw-dropdown__caret"), .attr("aria-hidden", "true")]),
        ])

        let menu = element("div", attributes: [
            .class("sw-dropdown__menu"),
            .attr("role", "menu"),
            .attr("popover", "auto"),
            .attr("id", menuID),
            .style("position-anchor", anchor),
            .style("position-area", placement.positionArea),
        ], children: itemNodes)

        return element("div", attributes: [.class("sw-dropdown")], children: [trigger, menu])
    }

    /// Post-process the built item nodes into a roving WAI-ARIA menu. Every menu item gets
    /// `role="menuitem"`, `tabindex="-1"`, and a stable id (`<menuID>-item-<n>`); the first
    /// ENABLED item gets `autofocus` (the Popover API focuses it when the menu opens); every
    /// enabled item gets a keydown handler that roves focus. Disabled items are `inert` —
    /// skipped (no autofocus, no handler, excluded from the roving order). Dividers and any
    /// non-item nodes pass through untouched. Only the menu knows item order/count, so the
    /// assembly lives here rather than in `DropdownItem`.
    private func rovingMenuItems(_ nodes: [VNode]) -> [VNode] {
        // Pass 1: assign each menu item a stable id; collect the enabled ids in order.
        var idForNode: [String?] = []
        var enabledIDs: [String] = []
        var itemIndex = 0
        for node in nodes {
            if isDropdownMenuItem(node) {
                let id = "\(menuID)-item-\(itemIndex)"
                itemIndex += 1
                idForNode.append(id)
                if isEnabledDropdownItem(node) { enabledIDs.append(id) }
            } else {
                idForNode.append(nil)
            }
        }
        // Pass 2: inject menu semantics; first enabled item autofocuses; enabled items rove.
        var firstEnabledAssigned = false
        return nodes.enumerated().map { index, node in
            guard let id = idForNode[index] else { return node }   // non-item → untouched
            var item = node
                .attr("role", "menuitem")
                .attr("tabindex", -1)
                .id(id)
            if isEnabledDropdownItem(node) {
                if !firstEnabledAssigned {
                    item = item.attr("autofocus", true)
                    firstEnabledAssigned = true
                }
                let currentID = id
                let order = enabledIDs
                let owningMenuID = menuID
                item = item.on(.keydown) { (e: EventInfo) in
                    DropdownMenu.rove(e, current: currentID, order: order, menuID: owningMenuID)
                }
            }
            return item
        }
    }

    /// The outcome of a roving keydown — which item id gets focus, or that
    /// the menu closes. Pure value so the decision table is host-testable
    /// apart from its JS focus effect (audit V Wave-2 #4, the DataTable
    /// seam pattern).
    enum RoveAction: Equatable {
        case focus(String)
        case closeMenu
    }

    /// The pure roving decision. ↑/↓ wrap; Home/End jump to the ends; Tab
    /// closes. Enter/Space/Escape are intentionally NOT handled — they are
    /// native (`<button>` activation + `popovertargetaction="hide"`, and
    /// popover light-dismiss with focus return). `nil` = not a roving key
    /// (or no roving context) — the event passes through untouched.
    static func roveTarget(key: String?, current: String, order: [String]) -> RoveAction? {
        guard let key, !order.isEmpty,
              let idx = order.firstIndex(of: current) else { return nil }
        let count = order.count
        switch key {
        case "ArrowDown": return .focus(order[(idx + 1) % count])
        case "ArrowUp":   return .focus(order[(idx + count - 1) % count])
        case "Home":      return .focus(order[0])
        case "End":       return .focus(order[count - 1])
        // Tab: close and let the browser's native Tab focus progression continue (we can't
        // preventDefault — the no-event-preventDefault project invariant). The menu closes and
        // focus moves to the next tabbable element outside it, NOT back to the trigger (Escape
        // does that, via the Popover API's native focus-return).
        case "Tab":       return .closeMenu
        default:          return nil
        }
    }

    /// The imperative half: apply the roving decision through the DOM.
    /// `#if canImport(JavaScriptKit)`-guarded (a no-op on host), mirroring
    /// Autocomplete's focus-by-id.
    private static func rove(_ e: EventInfo, current: String, order: [String], menuID: String) {
        guard let action = roveTarget(key: e.key, current: current, order: order) else { return }
        #if canImport(JavaScriptKit)
        guard let doc = JSObject.global.document.object else { return }
        switch action {
        case .closeMenu:
            _ = doc.getElementById?(menuID).object?.hidePopover?()
        case .focus(let id):
            if let el = doc.getElementById?(id).object { _ = el.focus?() }
        }
        #endif
    }
}

/// One actionable row in a `Dropdown`. Renders a `<button>`; the parent `Dropdown` injects the
/// `role="menuitem"`, roving `tabindex`, and stable id. Runs `action` and closes the menu on
/// select. `disabled: true` renders the button `inert` — removed from focus, pointer events, and
/// the accessibility tree, and skipped by keyboard roving. Use inside a `Dropdown { … }` builder.
@MainActor
public func DropdownItem(
    _ label: String,
    variant: DropdownItemVariant = .normal,
    disabled: Bool = false,
    _ attributes: Attribute...,
    action: @escaping @MainActor () -> Void
) -> VNode {
    let (callerClasses, callerRest) = splitClasses(attributes)
    let cls = (["sw-dropdown__item", "sw-dropdown__item--\(variant.modifierClass)"] + callerClasses)
        .joined(separator: " ")

    var attrs: [Attribute] = [.class(cls), .attr("type", "button")]
    if disabled {
        attrs.append(.attr("inert", true))   // not focusable, removed from the a11y tree; no action/close
    } else {
        attrs.append(.on(.click, perform: action))
        // Close the menu on select (declarative), when rendered inside a Dropdown.
        if let menuID = DropdownAmbient.currentMenuID {
            attrs.append(.attr("popovertarget", menuID))
            attrs.append(.attr("popovertargetaction", "hide"))
        }
    }
    attrs += callerRest
    return element("button", attributes: attrs, children: [text(label)])
}

/// A thin separator between groups of `DropdownItem`s.
@MainActor
public func DropdownDivider() -> VNode {
    element("div", attributes: [.class("sw-dropdown__divider"), .attr("role", "separator")])
}

/// True when `node` is a Dropdown menu item button (enabled or disabled). Dividers
/// (`sw-dropdown__divider`) and non-element nodes are excluded.
@MainActor
private func isDropdownMenuItem(_ node: VNode) -> Bool {
    guard case .element(let data) = node else { return false }
    return (data.attributes["class"] ?? "").contains("sw-dropdown__item")
}

/// True when `node` is a Dropdown menu item that is NOT inert (focusable/actionable).
/// Inert items are stored with a presence-only `inert` attribute (empty-string value).
@MainActor
private func isEnabledDropdownItem(_ node: VNode) -> Bool {
    guard case .element(let data) = node else { return false }
    return (data.attributes["class"] ?? "").contains("sw-dropdown__item")
        && data.attributes["inert"] == nil
}

/// Global `.sw-dropdown*` sheet. The menu is a Popover-API panel anchored to the trigger;
/// entry/exit read `--sw-duration` (reduced-motion → instant). Token-driven throughout.
let dropdownStyleSheet: CSSSheet = css {
    raw("""
    /* Non-selectable chrome — trigger/caret/menu/items read as native UI, not text.
       Inherits to the menu too: it's a DOM descendant even though it renders top-layer. */
    .sw-dropdown { display: inline-block; user-select: none; -webkit-user-select: none; }

    /* The trigger's anchor-name is set per-instance as an inline style (a dashed-ident
       derived from the menu id) — no class rule here, so nothing can shadow it. */
    /* The same chevron as Select's ::picker-icon (shared SVG), masked so it takes a
       token color. Rotates on open via :has() (the menu is a DOM child of .sw-dropdown). */
    .sw-dropdown__caret {
      display: inline-block;
      width: 1em;
      height: 1em;
      background-color: var(--sw-text-muted);
      -webkit-mask: url("\(swChevronDownSVG)") center / contain no-repeat;
      mask: url("\(swChevronDownSVG)") center / contain no-repeat;
      transition: rotate var(--sw-duration) var(--sw-ease);
    }
    .sw-dropdown:has(.sw-dropdown__menu:popover-open) .sw-dropdown__caret { rotate: 180deg; }

    .sw-dropdown__menu {
      /* popover top-layer reset + the anchored panel */
      margin: 0;
      inset: auto;                        /* let position-area place it; avoid the UA's centering */
      min-width: 11rem;
      max-width: min(90vw, 18rem);
      padding: var(--sw-space-xs);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      box-shadow: var(--sw-shadow);
      /* anchored a touch below/above the trigger */
      margin-block: var(--sw-space-xs);
    }
    /* entry/exit animation — the shared quartet (see PopoverTransition.swift) */
    \(popoverTransitionCSS(
        base: ".sw-dropdown__menu", open: ".sw-dropdown__menu:popover-open",
        closedTransform: "translateY(-4px)", openTransform: "translateY(0)",
        openExtras: "\n      display: flex;\n      flex-direction: column;\n      gap: 2px;"))

    .sw-dropdown__item {
      display: flex;
      align-items: center;
      gap: var(--sw-space-sm);
      width: 100%;
      text-align: left;
      padding: var(--sw-space-sm) var(--sw-space-md);
      border: none;
      background: transparent;
      color: var(--sw-text);
      border-radius: var(--sw-radius-sm);
      font: inherit;
      cursor: pointer;
    }
    .sw-dropdown__item:hover:not([inert]) { background-color: var(--sw-surface-2); }
    .sw-dropdown__item:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: -2px;
    }
    .sw-dropdown__item--danger { color: var(--sw-danger-strong); }
    .sw-dropdown__item[inert] { opacity: var(--sw-disabled-opacity); cursor: not-allowed; }

    .sw-dropdown__divider {
      height: var(--sw-border-width);
      background-color: var(--sw-border);
      margin: var(--sw-space-xs) 0;
    }
    """)
}
