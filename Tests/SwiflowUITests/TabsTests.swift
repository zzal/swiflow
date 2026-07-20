// Tests/SwiflowUITests/TabsTests.swift
// Tabs is a WAI-ARIA tablist with roving focus + automatic activation. The ID-generic
// surface stays in the thin `Tabs<ID>` free-function facade; the `@Component TabsView`
// underneath is non-generic (labels/panels/selectedIndex/selectIndex/attributes only —
// see Tabs.swift's doc comment for the rationale). These host tests cover (a) the pure
// roving decision table (mirrors DropdownTests' roveTarget table) and (b) the rendered
// tablist/tabpanel structure + click-to-select wiring, built through the public facade.
import Testing
@testable import Swiflow      // HandlerAmbient / HandlerRegistry / EventInfo for the click dispatch
@testable import SwiflowUI
import SwiflowTesting         // live-harness keyboard-roving suite

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                        return s
    case .element(let d):                     return d.children.map(allText).joined()
    case .fragment(let xs):                   return xs.map(allText).joined()
    case .environmentOverride(_, let child):  return allText(child)
    default:                                  return ""
    }
}

@MainActor private func firstWithClass(_ root: ElementData, _ cls: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
}

/// Collects every descendant (document order) whose `attr` attribute equals `value`.
@MainActor private func allWithAttr(_ root: ElementData, attr: String, value: String) -> [ElementData] {
    var results: [ElementData] = []
    func walk(_ d: ElementData) {
        if d.attributes[attr] == value { results.append(d) }
        for c in d.children { if let e = el(c) { walk(e) } }
    }
    walk(root)
    return results
}

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

/// Builds the `Tabs(selection:)` facade and unwraps the embedded `TabsView`'s body —
/// the facade returns a `.component` anchor (its `ID`-generic identity lives only in
/// the facade), so structure tests instantiate it directly, same shape as every other
/// overlay facade's `.component` unwrap (see ModalTests/DropdownTests' `freeFunctionEmbeds`).
@MainActor private func tabsBody<ID: Hashable & Sendable>(
    selection: Binding<ID>,
    @TabBuilder<ID> tabs build: () -> [Tab<ID>]
) -> VNode {
    let node = Tabs(selection: selection, tabs: build)
    guard case .component(let desc) = node else {
        Issue.record("expected an embedded component node, got \(node)")
        return .fragment([])
    }
    return desc.instantiate().instance.body
}

@Suite("Tabs")
@MainActor
struct TabsTests {
    // MARK: - Pure roving decision table (mirrors DropdownTests' roveTarget table)

    @Test("ArrowRight advances to the next tab") func arrowRightAdvances() {
        #expect(TabsView.tabRoveTarget(key: "ArrowRight", current: 0, count: 3) == 1)
    }

    @Test("ArrowRight wraps from the last tab to the first") func arrowRightWraps() {
        #expect(TabsView.tabRoveTarget(key: "ArrowRight", current: 2, count: 3) == 0)
    }

    @Test("ArrowLeft wraps from the first tab to the last") func arrowLeftWraps() {
        #expect(TabsView.tabRoveTarget(key: "ArrowLeft", current: 0, count: 3) == 2)
    }

    @Test("ArrowLeft retreats to the previous tab") func arrowLeftRetreats() {
        #expect(TabsView.tabRoveTarget(key: "ArrowLeft", current: 2, count: 3) == 1)
    }

    @Test("Home jumps to the first tab") func homeJumpsToFirst() {
        #expect(TabsView.tabRoveTarget(key: "Home", current: 1, count: 3) == 0)
    }

    @Test("End jumps to the last tab") func endJumpsToLast() {
        #expect(TabsView.tabRoveTarget(key: "End", current: 0, count: 3) == 2)
    }

    @Test("a non-roving key is not handled", arguments: ["Enter", "a", "Tab"]) func nonRovingKey(_ key: String) {
        #expect(TabsView.tabRoveTarget(key: key, current: 0, count: 3) == nil)
    }

    @Test("a nil key is not handled") func nilKey() {
        #expect(TabsView.tabRoveTarget(key: nil, current: 0, count: 3) == nil)
    }

    @Test("zero tabs never roves, regardless of key") func zeroCount() {
        #expect(TabsView.tabRoveTarget(key: "ArrowRight", current: 0, count: 0) == nil)
        #expect(TabsView.tabRoveTarget(key: "Home", current: 0, count: 0) == nil)
    }

    // MARK: - Structure (built through the public Tabs(selection:) facade)

    private func makeSelection(_ initial: String) -> (binding: Binding<String>, get: () -> String) {
        var value = initial
        let binding = Binding<String>(get: { value }, set: { value = $0 })
        return (binding, { value })
    }

    @Test("root is a tablist container with horizontal orientation") func tablistContainer() {
        let (binding, _) = makeSelection("overview")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
            }
        }
        let root = el(node)!
        let tablist = firstWithClass(root, "sw-tabs__list")!
        #expect(tablist.attributes["role"] == "tablist")
        #expect(tablist.attributes["aria-orientation"] == "horizontal")
    }

    @Test("each tab renders role=tab with a stable per-index id") func tabIDs() {
        let (binding, _) = makeSelection("overview")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
                Tab("Settings", id: "settings") { text("Settings content") }
            }
        }
        let root = el(node)!
        let tabs = allWithAttr(root, attr: "role", value: "tab")
        #expect(tabs.count == 3)
        let prefix = tabs[0].attributes["id"]!.replacingOccurrences(of: "-tab-0", with: "")
        for (i, tab) in tabs.enumerated() {
            #expect(tab.tag == "button")
            #expect(tab.attributes["id"] == "\(prefix)-tab-\(i)")
        }
    }

    @Test("the selected tab is aria-selected=true tabindex=0; the rest are false/-1") func selectedTabState() {
        let (binding, _) = makeSelection("details")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
                Tab("Settings", id: "settings") { text("Settings content") }
            }
        }
        let root = el(node)!
        let tabs = allWithAttr(root, attr: "role", value: "tab")
        #expect(tabs[0].attributes["aria-selected"] == "false")
        #expect(tabs[0].attributes["tabindex"] == "-1")
        #expect(tabs[1].attributes["aria-selected"] == "true")   // "details" is selected
        #expect(tabs[1].attributes["tabindex"] == "0")
        #expect(tabs[2].attributes["aria-selected"] == "false")
        #expect(tabs[2].attributes["tabindex"] == "-1")
    }

    @Test("each tab's aria-controls points at its panel's id") func ariaControls() {
        let (binding, _) = makeSelection("overview")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
            }
        }
        let root = el(node)!
        let tabs = allWithAttr(root, attr: "role", value: "tab")
        let panels = allWithAttr(root, attr: "role", value: "tabpanel")
        #expect(tabs.count == 2)
        #expect(panels.count == 2)
        for (tab, panel) in zip(tabs, panels) {
            #expect(tab.attributes["aria-controls"] == panel.attributes["id"])
        }
    }

    @Test("each panel is aria-labelledby its tab, hidden unless selected") func panelWiring() {
        let (binding, _) = makeSelection("overview")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
            }
        }
        let root = el(node)!
        let tabs = allWithAttr(root, attr: "role", value: "tab")
        let panels = allWithAttr(root, attr: "role", value: "tabpanel")
        for (tab, panel) in zip(tabs, panels) {
            #expect(panel.attributes["aria-labelledby"] == tab.attributes["id"])
            #expect(panel.attributes["tabindex"] == "0")
        }
        #expect(panels[0].attributes["hidden"] == nil)     // overview is selected
        #expect(panels[1].attributes["hidden"] == "")      // details is not — presence-only boolean attr
    }

    @Test("all panels render their content (render-all — state/ARIA stay stable)") func renderAllPanels() {
        let (binding, _) = makeSelection("overview")
        let node = building {
            tabsBody(selection: binding) {
                Tab("Overview", id: "overview") { text("Overview content") }
                Tab("Details", id: "details") { text("Details content") }
            }
        }
        let root = el(node)!
        let panels = allWithAttr(root, attr: "role", value: "tabpanel")
        #expect(allText(.element(panels[0])).contains("Overview content"))
        #expect(allText(.element(panels[1])).contains("Details content"))   // present even though hidden
    }

    @Test("two Tabs instances get distinct id prefixes") func distinctPrefixes() {
        let (b1, _) = makeSelection("a")
        let (b2, _) = makeSelection("x")
        let node1 = building {
            tabsBody(selection: b1) {
                Tab("A", id: "a") { text("A content") }
                Tab("B", id: "b") { text("B content") }
            }
        }
        let node2 = building {
            tabsBody(selection: b2) {
                Tab("X", id: "x") { text("X content") }
                Tab("Y", id: "y") { text("Y content") }
            }
        }
        let tab1 = allWithAttr(el(node1)!, attr: "role", value: "tab").first!
        let tab2 = allWithAttr(el(node2)!, attr: "role", value: "tab").first!
        #expect(tab1.attributes["id"] != tab2.attributes["id"])
    }

    @Test("clicking a tab dispatches through HandlerRegistry and changes the bound selection") func clickChangesSelection() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        let (binding, get) = makeSelection("overview")
        let node = tabsBody(selection: binding) {
            Tab("Overview", id: "overview") { text("Overview content") }
            Tab("Details", id: "details") { text("Details content") }
        }
        let tabs = allWithAttr(el(node)!, attr: "role", value: "tab")
        #expect(get() == "overview")
        registry.dispatch(id: tabs[1].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(get() == "details")
    }

    @Test("stylesheet: tab rail with a token-driven selected indicator") func stylesheet() {
        let css = tabsStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-tabs__list"))
        #expect(css.contains(".sw-tabs__tab"))
        #expect(css.contains("aria-selected"))
        #expect(css.contains("var(--sw-accent)"))
    }

    @Test("the SELECTED tab carries the per-instance anchor-name; the tablist ends with the aria-hidden indicator anchored to it")
    func slidingIndicatorWiring() {
        var sel = "b"
        let binding = Binding<String>(get: { sel }, set: { sel = $0 })
        let body = building { tabsBody(selection: binding) {
            Tab("A", id: "a") { text("pa") }
            Tab("B", id: "b") { text("pb") }
        } }
        let list = firstWithClass(el(body)!, "sw-tabs__list")!
        let tabs = list.children.compactMap(el).filter { $0.attributes["role"] == "tab" }
        // only the selected tab anchors
        #expect(tabs[0].style["anchor-name"] == nil)
        let anchor = tabs[1].style["anchor-name"]
        #expect(anchor?.hasPrefix("--sw-tabs") == true)
        // the indicator is the tablist's last child, decorative, anchored to the same name
        let indicator = el(list.children.last!)!
        #expect(indicator.attributes["class"] == "sw-tabs__indicator")
        #expect(indicator.attributes["aria-hidden"] == "true")
        #expect(indicator.style["position-anchor"] == anchor)
    }

    @Test("stylesheet: the underline slides ease-out via anchored insets, gated on anchor positioning")
    func slidingIndicatorSheet() {
        let css = tabsStyleSheet.cssString(scopeClass: "")
        #expect(css.contains("@supports (anchor-name: --sw-probe)"))
        #expect(css.contains(".sw-tabs__indicator"))
        #expect(css.contains("left: anchor(left)"))
        #expect(css.contains("right: anchor(right)"))
        // THE review ask: animated with ease-out (duration stays on the token so
        // reduced-motion collapses it)
        #expect(css.contains("transition: left var(--sw-duration) ease-out"))
        // supported browsers hand the static underline off to the slider
        #expect(css.contains(".sw-tabs__tab[aria-selected=\"true\"] { border-bottom-color: transparent; }"))
    }
}

// MARK: - Live keyboard roving (harness-mounted)

/// Hosts a real Tabs in the headless harness so keydown drives the FULL
/// path — handleRove's selection move runs on host (only the DOM focus()
/// crossing is arch(wasm32)-gated). Before that gate, a host keydown
/// aborted in JSObject.global with no message, which is why no such test
/// could exist.
@Component
private final class TabsRovingHost {
    @State var selection: String = "one"
    var body: VNode {
        Tabs(selection: $selection) {
            Tab("One", id: "one") { text("first") }
            Tab("Two", id: "two") { text("second") }
            Tab("Three", id: "three") { text("third") }
        }
    }
}

@Suite("Tabs live keyboard roving")
@MainActor
struct TabsRovingTests {

    private func selectedLabel(_ h: TestHarness) -> String? {
        h.findAll(role: "tab").first { $0.attributes["aria-selected"] == "true" }?.text
    }

    @Test("ArrowRight/ArrowLeft/Home/End move the selection (automatic activation), wrapping")
    func arrowKeysMoveSelection() {
        let h = render(TabsRovingHost())
        #expect(selectedLabel(h) == "One")

        h.findAll(role: "tab")[0].press(key: "ArrowRight")
        #expect(selectedLabel(h) == "Two")

        h.findAll(role: "tab")[1].press(key: "End")
        #expect(selectedLabel(h) == "Three")

        h.findAll(role: "tab")[2].press(key: "ArrowRight")   // wraps
        #expect(selectedLabel(h) == "One")

        h.findAll(role: "tab")[0].press(key: "ArrowLeft")    // wraps back
        #expect(selectedLabel(h) == "Three")

        h.findAll(role: "tab")[2].press(key: "Home")
        #expect(selectedLabel(h) == "One")
    }

    @Test("a non-roving key leaves the selection alone")
    func otherKeysIgnored() {
        let h = render(TabsRovingHost())
        h.findAll(role: "tab")[0].press(key: "Enter")
        #expect(selectedLabel(h) == "One")
    }
}
