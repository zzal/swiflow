import Testing
import Swiflow
@testable import Swiflow    // HandlerAmbient / HandlerRegistry — Button needs an ambient registry
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}
@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                       return s
    case .element(let d):                    return d.children.map(allText).joined()
    case .fragment(let xs):                  return xs.map(allText).joined()
    case .environmentOverride(_, let child): return allText(child)
    default:                                  return ""
    }
}

// Button registers a click handler, which requires an ambient HandlerRegistry.
// Provide one for the duration of each call that constructs a Button trigger.
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

// The TooltipView @Component body (what the Tooltip free fn embeds).
@MainActor private func tip(
    _ message: String,
    placement: TooltipPlacement = .top,
    attributes: [Attribute] = [],
    content: @escaping () -> VNode
) -> VNode {
    TooltipView(message: message, placement: placement, attributes: attributes, content: content).body
}

@MainActor
@Suite("Tooltip")
struct TooltipTests {
    @Test("wraps the trigger, wires aria-describedby to a role=tooltip bubble") func wiresAria() {
        let node = building { tip("Delete permanently") { Button("Delete") {} } }
        let wrap = el(node)
        #expect(wrap?.attributes["class"]?.contains("sw-tooltip-wrap") == true)
        let kids = wrap?.children ?? []
        #expect(kids.count == 2)
        let trigger = el(kids[0]); let bubble = el(kids[1])
        let tipID = bubble?.attributes["id"]
        #expect(tipID?.isEmpty == false)
        #expect(bubble?.attributes["role"] == "tooltip")
        #expect(trigger?.attributes["aria-describedby"] == tipID)
        #expect(allText(kids[1]) == "Delete permanently")
    }

    @Test("placement sets the bubble modifier class") func placement() {
        let node = building { tip("hi", placement: .bottom) { Button("x") {} } }
        let bubble = el(el(node)?.children[1])
        #expect(bubble?.attributes["class"]?.contains("sw-tooltip--bottom") == true)
    }

    @Test("non-element trigger: no crash, no aria link, bubble still role=tooltip") func nonElementTrigger() {
        let node = tip("hi") { VNode.text("plain") }
        let kids = el(node)?.children ?? []
        #expect(kids.count == 2)
        #expect(el(kids[1])?.attributes["role"] == "tooltip")
    }

    @Test("emitted sheet has reveal selectors + token styling + all placements") func sheet() {
        let css = tooltipStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-tooltip-wrap:hover .sw-tooltip"))
        #expect(css.contains(":focus-within"))
        #expect(css.contains("var(--sw-surface)"))
        #expect(css.contains(".sw-tooltip--top"))
        #expect(css.contains(".sw-tooltip--bottom"))
        #expect(css.contains(".sw-tooltip--leading"))
        #expect(css.contains(".sw-tooltip--trailing"))
    }
}
