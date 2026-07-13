// Tests/SwiflowUITests/AccordionTests.swift
// Accordion is native <details>/<summary> disclosure: AccordionItem is a stateless free
// function (a <details> wrapping a <summary> label + a panel <div>); Accordion is a
// @Component facade purely so its `exclusive` group name is stable across re-renders —
// the DropdownMenu/Tabs `nextSwID`-in-`init` precedent. When `exclusive`, every <details>
// child gets the SAME `name` attribute (native `<details name>` grouping, Baseline 2024);
// otherwise none do. These host tests cover structure + the grouping/id wiring; open/close
// itself is native (no JS).
import Testing
@testable import Swiflow
@testable import SwiflowUI

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

/// Collects every descendant (document order) with the given tag.
@MainActor private func allWithTag(_ root: ElementData, _ tag: String) -> [ElementData] {
    var results: [ElementData] = []
    func walk(_ d: ElementData) {
        if d.tag == tag { results.append(d) }
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

/// Builds the `Accordion(...)` facade and unwraps the embedded `AccordionView`'s body —
/// same `.component` unwrap as TabsTests/DropdownTests.
@MainActor private func accordionBody(
    exclusive: Bool = false,
    @ChildrenBuilder items: @escaping () -> [VNode]
) -> VNode {
    let node = Accordion(exclusive: exclusive, items: items)
    guard case .component(let desc) = node else {
        Issue.record("expected an embedded component node, got \(node)")
        return .fragment([])
    }
    return desc.instantiate().instance.body
}

@Suite("Accordion")
@MainActor
struct AccordionTests {
    // MARK: - AccordionItem (stateless free function)

    @Test("renders a <details class=sw-accordion__item> wrapping a <summary> label + a panel <div>")
    func itemStructure() {
        let node = AccordionItem("Section one") { [text("Body copy")] }
        let details = el(node)!
        #expect(details.tag == "details")
        #expect(details.attributes["class"] == "sw-accordion__item")
        #expect(details.children.count == 2)

        let summary = el(details.children[0])!
        #expect(summary.tag == "summary")
        #expect(summary.attributes["class"] == "sw-accordion__summary")
        #expect(allText(details.children[0]) == "Section one")

        let panel = el(details.children[1])!
        #expect(panel.tag == "div")
        #expect(panel.attributes["class"] == "sw-accordion__panel")
        #expect(allText(details.children[1]) == "Body copy")
    }

    @Test("open: true adds the open attribute") func openTrueAddsAttribute() {
        let node = AccordionItem("Section", open: true) { [text("x")] }
        #expect(el(node)!.attributes["open"] == "")
    }

    @Test("open: false (the default) omits the open attribute") func openFalseOmitsAttribute() {
        let node = AccordionItem("Section") { [text("x")] }
        #expect(el(node)!.attributes["open"] == nil)
    }

    // MARK: - Accordion (facade wrapping items in .sw-accordion)

    @Test("wraps items in a <div class=sw-accordion> container") func wrapsInContainer() {
        let node = building {
            accordionBody {
                [AccordionItem("One") { [text("1")] }, AccordionItem("Two") { [text("2")] }]
            }
        }
        let root = el(node)!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-accordion")
        #expect(allWithTag(root, "details").count == 2)
    }

    @Test("exclusive: true — every <details> child gets a name attribute, all sharing the same value")
    func exclusiveSharesOneName() {
        let node = building {
            accordionBody(exclusive: true) {
                [AccordionItem("One") { [text("1")] },
                 AccordionItem("Two") { [text("2")] },
                 AccordionItem("Three") { [text("3")] }]
            }
        }
        let root = el(node)!
        let items = allWithTag(root, "details")
        #expect(items.count == 3)
        let names = items.map { $0.attributes["name"] }
        #expect(names.allSatisfy { $0 != nil })
        #expect(Set(names.compactMap { $0 }).count == 1)   // all the SAME value
    }

    @Test("exclusive: false (the default) — no <details> child gets a name attribute")
    func nonExclusiveHasNoName() {
        let node = building {
            accordionBody {
                [AccordionItem("One") { [text("1")] }, AccordionItem("Two") { [text("2")] }]
            }
        }
        let root = el(node)!
        let items = allWithTag(root, "details")
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.attributes["name"] == nil })
    }

    @Test("two separate Accordion(exclusive: true) instances get DIFFERENT group names")
    func distinctGroupsAcrossInstances() {
        let node1 = building { accordionBody(exclusive: true) { [AccordionItem("A") { [text("a")] }] } }
        let node2 = building { accordionBody(exclusive: true) { [AccordionItem("B") { [text("b")] }] } }
        let name1 = allWithTag(el(node1)!, "details")[0].attributes["name"]!
        let name2 = allWithTag(el(node2)!, "details")[0].attributes["name"]!
        #expect(name1 != name2)
    }

    @Test("the group name is stable across two body calls of the same instance (init-captured)")
    func stableAcrossBodyCalls() {
        let view = AccordionView(exclusive: true, items: { [AccordionItem("A") { [text("a")] }] }, attributes: [])
        let name1 = building { allWithTag(el(view.body)!, "details")[0].attributes["name"]! }
        let name2 = building { allWithTag(el(view.body)!, "details")[0].attributes["name"]! }
        #expect(name1 == name2)
    }

    @Test("non-<details> children pass through untouched (no name attribute injected)")
    func nonDetailsChildrenPassThrough() {
        let node = building {
            accordionBody(exclusive: true) {
                [AccordionItem("One") { [text("1")] }, text("a stray text node"), div { text("a stray div") }]
            }
        }
        let root = el(node)!
        #expect(allText(node).contains("a stray text node"))
        #expect(allText(node).contains("a stray div"))
        let strayDiv = root.children.compactMap { el($0) }.first { $0.tag == "div" }!
        #expect(strayDiv.attributes["name"] == nil)
    }

    @Test("stylesheet: token-driven, marker-free summary with a rotating chevron") func stylesheet() {
        let css = accordionStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-accordion"))
        #expect(css.contains(".sw-accordion__item"))
        #expect(css.contains(".sw-accordion__summary"))
        #expect(css.contains(".sw-accordion__panel"))
        #expect(css.contains("::-webkit-details-marker"))
        #expect(css.contains("[open]"))
        #expect(css.contains("var(--sw-duration)"))
    }
}
