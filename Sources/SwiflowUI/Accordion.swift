// Sources/SwiflowUI/Accordion.swift
import Swiflow

/// One collapsible section: native `<details>`/`<summary>` disclosure, no JS. `open`
/// sets the initial (and, since `<details>` is uncontrolled, ongoing) expanded state —
/// the browser owns toggling from here. Use inside an `Accordion { … }` builder (or
/// standalone — it's a plain stateless free function, not tied to the facade).
///
///     AccordionItem("Shipping", open: true) {
///         p("Ships within two business days.")
///     }
///
/// Caller `Attribute...`/`.class` land on the `<details>` root.
@MainActor
public func AccordionItem(
    _ title: String,
    open: Bool = false,
    _ attributes: Attribute...,
    @ChildrenBuilder content: () -> [VNode]
) -> VNode {
    let (callerClasses, callerRest) = splitClasses(attributes)
    let cls = (["sw-accordion__item"] + callerClasses).joined(separator: " ")
    return element("details", attributes: [.class(cls), .attr("open", open)] + callerRest, children: [
        summary(title, .class("sw-accordion__summary")),
        element("div", attributes: [.class("sw-accordion__panel")], children: content()),
    ])
}

/// A group of `AccordionItem`s (WAI-ARIA-free — native `<details>` already carries
/// disclosure semantics to assistive tech).
///
///     Accordion {
///         AccordionItem("Shipping") { p("...") }
///         AccordionItem("Returns") { p("...") }
///     }
///
/// `exclusive: true` groups every `<details>` child under the SAME native `<details
/// name="...">` value, so the platform enforces one-open-at-a-time (Baseline 2024) —
/// opening one closes the others, no JS. `exclusive: false` (the default) leaves items
/// independent — any number can be open together.
///
/// Caller `Attribute...`/`.class` land on the root `.sw-accordion` container.
///
/// It's a `@Component` facade purely so the `exclusive` group name is generated ONCE
/// (in `init`) and stays stable across re-renders — a bare free function would mint a
/// fresh `nextSwID` every render, breaking the shared-name grouping (the
/// `DropdownMenu`/`Tabs` precedent). See `AccordionView` below.
@MainActor
public func Accordion(
    exclusive: Bool = false,
    _ attributes: Attribute...,
    key: String? = nil,
    @ChildrenBuilder items: @escaping () -> [VNode]
) -> VNode {
    embedKeyed(key, {
        AccordionView(exclusive: exclusive, items: items, attributes: attributes)
    }, refresh: { view in
        view.exclusive = exclusive
        view.items = items
        view.attributes = attributes
    })
}

/// The implementation behind `Accordion`. Non-generic (there's no `ID`-generic surface
/// to resolve here, unlike `TabsView`) — just a stable group name plus a post-process
/// pass over the built items.
@Component
final class AccordionView {
    var exclusive: Bool
    var items: () -> [VNode]
    var attributes: [Attribute]

    /// Stable `<details name>` value, generated ONCE in `init` (the `DropdownMenu`
    /// `nextSwID` rationale) so it stays stable across re-renders and never collides
    /// between two `Accordion(exclusive: true)` instances.
    private let groupName: String

    init(exclusive: Bool, items: @escaping () -> [VNode], attributes: [Attribute]) {
        self.exclusive = exclusive
        self.items = items
        self.attributes = attributes
        self.groupName = nextSwID("sw-accordion")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-accordion", accordionStyleSheet)

        let rawItems = items()
        let itemNodes = exclusive ? groupedItems(rawItems) : rawItems

        let (callerClasses, callerRest) = splitClasses(attributes)
        let rootClass = (["sw-accordion"] + callerClasses).joined(separator: " ")

        return element("div", attributes: [.class(rootClass)] + callerRest, children: itemNodes)
    }

    /// Post-process the built item nodes: every `<details>` child gets the shared
    /// group name so the browser enforces exclusive opening; non-`<details>` nodes
    /// pass through untouched (the `DropdownMenu.rovingMenuItems` map-over-children
    /// pattern).
    private func groupedItems(_ nodes: [VNode]) -> [VNode] {
        nodes.map { node in
            guard case .element(let data) = node, data.tag == "details" else { return node }
            return node.attr("name", groupName)
        }
    }
}

/// Global `.sw-accordion*` sheet. Items stack with a small gap, each bordered/rounded;
/// the summary drops the native marker in favor of the shared chevron (masked so it
/// takes a token color), rotating open via the `<details>` `[open]` attribute. All tokens.
let accordionStyleSheet: CSSSheet = css {
    raw("""
    .sw-accordion {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-sm);
    }

    .sw-accordion__item {
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      overflow: hidden;
    }

    .sw-accordion__summary {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--sw-space-sm);
      padding: var(--sw-space-sm) var(--sw-space-md);
      cursor: pointer;
      list-style: none;
      font-weight: var(--sw-font-weight-medium);
      color: var(--sw-text);
    }
    .sw-accordion__summary::-webkit-details-marker { display: none; }
    .sw-accordion__summary:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: -2px;
    }
    /* The same chevron as Select/Dropdown (shared SVG mask), rotating on the
       <details>'s native [open] attribute — no JS. */
    .sw-accordion__summary::after {
      content: "";
      display: inline-block;
      flex: none;
      width: 1em;
      height: 1em;
      background-color: var(--sw-text-muted);
      -webkit-mask: url("\(swChevronDownSVG)") center / contain no-repeat;
      mask: url("\(swChevronDownSVG)") center / contain no-repeat;
      transition: rotate var(--sw-duration) var(--sw-ease);
    }
    .sw-accordion__item[open] > .sw-accordion__summary::after { rotate: 180deg; }

    .sw-accordion__panel {
      padding: var(--sw-space-sm) var(--sw-space-md) var(--sw-space-md);
    }
    """)
}
