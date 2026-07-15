// Sources/SwiflowUI/Tabs.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// One tab in a `Tabs(selection:)` group: a label, a stable `id` (matched against the
/// bound selection), and its panel content. Content is captured lazily — see `Tabs`,
/// which builds ALL tabs' panels up front (render-all, so panel state/ARIA stay stable
/// across selection changes).
public struct Tab<ID: Hashable> {
    let label: String
    let id: ID
    let content: () -> [VNode]

    public init(_ label: String, id: ID, @ChildrenBuilder content: @escaping () -> [VNode]) {
        self.label = label
        self.id = id
        self.content = content
    }
}

/// Collects `[Tab<ID>]` from a trailing-closure block, supporting `if`/`else`/`for`.
/// Mirrors `ColumnBuilder` exactly (same `build*` method set).
@resultBuilder
public enum TabBuilder<ID: Hashable> {
    public static func buildExpression(_ tab: Tab<ID>) -> [Tab<ID>] { [tab] }
    public static func buildExpression(_ tabs: [Tab<ID>]) -> [Tab<ID>] { tabs }
    public static func buildBlock(_ parts: [Tab<ID>]...) -> [Tab<ID>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [Tab<ID>]?) -> [Tab<ID>] { part ?? [] }
    public static func buildEither(first: [Tab<ID>]) -> [Tab<ID>] { first }
    public static func buildEither(second: [Tab<ID>]) -> [Tab<ID>] { second }
    public static func buildArray(_ parts: [[Tab<ID>]]) -> [Tab<ID>] { parts.flatMap { $0 } }
}

/// A **tablist** (WAI-ARIA `role="tablist"`, horizontal, automatic activation): a row of
/// tabs bound to a `Binding<ID>` selection, each revealing its own panel.
///
///     @State var tab = "overview"
///     …
///     Tabs(selection: $tab) {
///         Tab("Overview", id: "overview") { Text("...") }
///         Tab("Details", id: "details") { Text("...") }
///         Tab("Settings", id: "settings") { Text("...") }
///     }
///
/// **Keyboard (roving tabindex, automatic activation):** ←/→ move between tabs and wrap;
/// Home/End jump to the first/last. Moving focus IMMEDIATELY selects the target tab (its
/// panel swaps and focus follows) — the APG "automatic activation" pattern, as opposed to
/// "manual activation" (focus moves, a separate Enter/Space activates). Tab is deliberately
/// NOT handled by roving: it leaves the tablist for the next tabbable element, same as any
/// other widget (Swiflow handlers can't `preventDefault`, so hijacking Tab isn't possible
/// anyway) — only ArrowLeft/ArrowRight/Home/End move focus within the tablist.
///
/// **Orientation:** horizontal only in this release; a `.vertical` variant (Up/Down instead
/// of Left/Right, `aria-orientation="vertical"`) is deferred.
///
/// **Panels render ALL tabs' content**, always — the inactive ones are simply `hidden`
/// (not omitted), so panel-local state and ARIA wiring stay stable across selection
/// changes instead of being torn down and rebuilt.
///
/// Caller `Attribute...`/`.class` land on the root `.sw-tabs` container.
///
/// The `ID`-generic surface lives ONLY here, in this thin facade: it resolves `selection`
/// to a plain `Int` index and hands a non-generic `@Component` (`TabsView`) the resolved
/// labels/panels/index/callback — see `TabsView`'s doc comment for why.
@MainActor
public func Tabs<ID: Hashable & Sendable>(
    selection: Binding<ID>,
    _ attributes: Attribute...,
    key: String? = nil,
    @TabBuilder<ID> tabs build: () -> [Tab<ID>]
) -> VNode {
    let tabs = build()
    let labels = tabs.map(\.label)
    let panels = tabs.map { $0.content() }
    let selectedIndex = tabs.firstIndex { $0.id == selection.get() } ?? 0
    let selectIndex: (Int) -> Void = { i in
        guard tabs.indices.contains(i) else { return }
        selection.set(tabs[i].id)
    }
    return embedKeyed(key, {
        TabsView(labels: labels, panels: panels, selectedIndex: selectedIndex,
                 selectIndex: selectIndex, attributes: attributes)
    }, refresh: { view in
        view.labels = labels
        view.panels = panels
        view.selectedIndex = selectedIndex
        view.selectIndex = selectIndex
        view.attributes = attributes
    })
}

/// The implementation behind `Tabs`. Deliberately NON-generic — `@Component` on a
/// generic class would tie the framework's reflection-driven state wiring to a
/// per-`ID` specialization, and the roving/id logic below never actually needs to
/// know what `ID` is. All `Hashable`/`Binding` work happens in the `Tabs<ID>` facade
/// above; this component only ever sees a resolved `Int` index.
@Component
final class TabsView {
    var labels: [String]
    var panels: [[VNode]]
    var selectedIndex: Int
    var selectIndex: (Int) -> Void
    var attributes: [Attribute]

    /// Stable id prefix for `<prefix>-tab-<i>` / `<prefix>-panel-<i>`, generated ONCE in
    /// `init` (the `DropdownMenu`/`nextSwID` rationale) so it stays stable across
    /// re-renders and never collides between two `Tabs` instances.
    private let idPrefix: String

    init(labels: [String], panels: [[VNode]], selectedIndex: Int,
         selectIndex: @escaping (Int) -> Void, attributes: [Attribute]) {
        self.labels = labels
        self.panels = panels
        self.selectedIndex = selectedIndex
        self.selectIndex = selectIndex
        self.attributes = attributes
        self.idPrefix = nextSwID("sw-tabs")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-tabs", tabsStyleSheet)

        // Per-instance anchor for the sliding underline: the SELECTED tab carries the
        // anchor-name, so the indicator (anchored to it) follows selection — and its
        // inset transition animates the slide. idPrefix-derived: stable + collision-free.
        let anchorName = "--\(idPrefix)-active"

        let tabNodes: [VNode] = labels.indices.map { i in
            let tabID = "\(idPrefix)-tab-\(i)"
            let panelID = "\(idPrefix)-panel-\(i)"
            let selected = (i == selectedIndex)
            var tabAttrs: [Attribute] = [
                .class("sw-tabs__tab"),
                .attr("type", "button"),
                .attr("role", "tab"),
                .id(tabID),
                .attr("aria-selected", selected ? "true" : "false"),
                .attr("aria-controls", panelID),
                .attr("tabindex", selected ? 0 : -1),
                .on(.click) { self.selectIndex(i) },
                .on(.keydown) { e in self.handleRove(e, current: i) },
            ]
            if selected { tabAttrs.append(.style("anchor-name", anchorName)) }
            return element("button", attributes: tabAttrs, children: [text(labels[i])])
        }

        // The sliding underline (anchor-positioning browsers only; see the sheet).
        // Decorative — the selection semantics live on aria-selected.
        let indicator = element("span", attributes: [
            .class("sw-tabs__indicator"),
            .attr("aria-hidden", "true"),
            .style("position-anchor", anchorName),
        ], children: [])

        let tablist = element("div", attributes: [
            .class("sw-tabs__list"),
            .attr("role", "tablist"),
            .attr("aria-orientation", "horizontal"),
        ], children: tabNodes + [indicator])

        let panelNodes: [VNode] = panels.indices.map { i in
            let tabID = "\(idPrefix)-tab-\(i)"
            let panelID = "\(idPrefix)-panel-\(i)"
            var panelAttrs: [Attribute] = [
                .class("sw-tabs__panel"),
                .attr("role", "tabpanel"),
                .id(panelID),
                .attr("aria-labelledby", tabID),
                .attr("tabindex", 0),
            ]
            if i != selectedIndex { panelAttrs.append(.attr("hidden", true)) }
            return element("div", attributes: panelAttrs, children: panels[i])
        }

        let (callerClasses, callerRest) = splitClasses(attributes)
        let rootClass = (["sw-tabs"] + callerClasses).joined(separator: " ")

        return element("div", attributes: [.class(rootClass)] + callerRest,
                        children: [tablist] + panelNodes)
    }

    /// The pure roving decision: which tab index a keydown should move focus/selection
    /// to. ←/→ wrap; Home/End jump to the ends. `nil` = not a roving key (or no tabs) —
    /// the event passes through untouched. Host-testable apart from its JS focus effect
    /// (the `Dropdown.roveTarget` pattern). Tab is intentionally NOT a case here — see
    /// `Tabs`'s doc comment on the no-preventDefault project invariant.
    static func tabRoveTarget(key: String?, current: Int, count: Int) -> Int? {
        guard let key, count > 0 else { return nil }
        switch key {
        case "ArrowRight": return (current + 1) % count
        case "ArrowLeft":  return (current + count - 1) % count
        case "Home":       return 0
        case "End":        return count - 1
        default:           return nil
        }
    }

    /// The imperative half: on a roving key, select the target tab (automatic
    /// activation — re-renders, moving `tabindex`/`hidden`), then move DOM focus onto
    /// it. `#if canImport(JavaScriptKit)`-guarded (a no-op on host), mirroring
    /// `DropdownMenu.rove`.
    private func handleRove(_ e: EventInfo, current: Int) {
        guard let target = TabsView.tabRoveTarget(key: e.key, current: current, count: labels.count) else { return }
        selectIndex(target)
        #if canImport(JavaScriptKit)
        guard let doc = JSObject.global.document.object else { return }
        if let el = doc.getElementById?("\(idPrefix)-tab-\(target)").object { _ = el.focus?() }
        #endif
    }
}

/// Global `.sw-tabs*` sheet. A flex-row tab rail with a bottom border, the selected tab
/// picked out by an accent bottom-border + text color; panels get comfortable
/// block padding and a focus-visible outline (they're `tabindex="0"` — focusable
/// containers, per the APG tabpanel pattern). All tokens.
let tabsStyleSheet: CSSSheet = css {
    raw("""
    .sw-tabs__list {
      position: relative;              /* containing block for the sliding indicator */
      display: flex;
      flex-direction: row;
      gap: var(--sw-space-sm);
      border-bottom: var(--sw-border-width) solid var(--sw-border);
    }

    .sw-tabs__tab {
      display: inline-flex;
      align-items: center;
      padding: var(--sw-space-sm) var(--sw-space-md);
      background: transparent;
      border: none;
      border-bottom: 2px solid transparent;
      color: var(--sw-text-muted);
      font: inherit;
      cursor: pointer;
      margin-bottom: -1px;
      border-radius: var(--sw-radius-sm) var(--sw-radius-sm) 0 0;
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-tabs__tab:hover { color: var(--sw-text); }
    .sw-tabs__tab:focus-visible {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    .sw-tabs__tab[aria-selected="true"] {
      color: var(--sw-accent);
      border-bottom-color: var(--sw-accent);
    }

    /* Animated underline (the Reshaped slide): one indicator span, anchored to
       whichever tab carries the per-instance anchor-name (the selected one — the
       component moves it on selection). When the anchor moves, the indicator's
       resolved left/right change and the transition slides it, ease-out per the
       design ask; --sw-duration keeps reduced-motion instant. Gated on anchor
       positioning: unsupported browsers (Firefox) keep the static accent
       underline above; supported ones hand it off to the slider. */
    .sw-tabs__indicator { display: none; }
    @supports (anchor-name: --sw-probe) {
      .sw-tabs__indicator {
        display: block;
        position: absolute;
        left: anchor(left);
        right: anchor(right);
        bottom: calc(-1 * var(--sw-border-width));   /* sit on the rail, like the tab underline */
        height: 2px;
        background-color: var(--sw-accent);
        pointer-events: none;
        transition: left var(--sw-duration) ease-out,
                    right var(--sw-duration) ease-out;
      }
      .sw-tabs__tab[aria-selected="true"] { border-bottom-color: transparent; }
    }

    .sw-tabs__panel {
      padding-block: var(--sw-space-md);
      border-radius: var(--sw-radius-sm);
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-tabs__panel:focus-visible {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    """)
}
