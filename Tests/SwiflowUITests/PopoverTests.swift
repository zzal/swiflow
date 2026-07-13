// Tests/SwiflowUITests/PopoverTests.swift
// Popover reuses Dropdown's native recipe (Popover API + CSS anchor positioning), but
// generalizes the panel to arbitrary caller content and lets the caller supply their own
// single trigger element (instead of a baked button). These host tests cover structure +
// the id/anchor/popovertarget wiring; open/close + anchoring are native, browser-verified
// on the demo.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func firstWithClass(_ root: ElementData, _ cls: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
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

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

#if DEBUG
/// Runs `body` with the diagnostic override installed (so diagnostics are captured
/// instead of trapping the process) and returns the captured messages. Mirrors
/// `FieldChromeDiagnosticTests`'s seam.
@MainActor private func capturingDiagnostics(_ body: () -> Void) -> [String] {
    var captured: [String] = []
    let prior = _swiflowDiagnosticOverride
    _swiflowDiagnosticOverride = { captured.append($0) }
    defer { _swiflowDiagnosticOverride = prior }
    body()
    return captured
}
#endif

// The PopoverPanel @Component body (what the Popover free fn embeds).
@MainActor private func pop(
    placement: PopoverPlacement = .bottom,
    panelAttrs: [Attribute] = [],
    trigger: @escaping () -> [VNode],
    content: @escaping () -> [VNode]
) -> VNode {
    PopoverPanel(placement: placement, panelAttrs: panelAttrs, trigger: trigger, content: content).body
}

@Suite("Popover")
@MainActor
struct PopoverTests {
    @Test("renders a root wrapping the trigger + an anchored popover panel, wired by a shared id") func renders() {
        let node = building { pop(trigger: { [Button("Open") {}] }, content: { [text("Details")] }) }
        let root = el(node)!
        #expect(root.attributes["class"] == "sw-popover-root")
        let panel = firstWithClass(root, "sw-popover")!
        #expect(panel.tag == "div")
        #expect(panel.attributes["popover"] == "auto")
        let panelID = panel.attributes["id"]!

        let trigger = el(root.children[0])!
        #expect(trigger.tag == "button")
        #expect(trigger.attributes["class"]?.contains("sw-btn") == true)   // caller's own class survives
        #expect(trigger.attributes["popovertarget"] == panelID)
        #expect(trigger.style["anchor-name"] == "--\(panelID)")
        #expect(panel.style["position-anchor"] == "--\(panelID)")
        #expect(allText(node).contains("Details"))
    }

    @Test("the panel id is stable across re-renders (the reason it's a @Component)") func stableID() {
        let panel = PopoverPanel(placement: .bottom, panelAttrs: [], trigger: { [Button("Open") {}] }, content: { [text("x")] })
        let id1 = building { firstWithClass(el(panel.body)!, "sw-popover")!.attributes["id"]! }
        let id2 = building { firstWithClass(el(panel.body)!, "sw-popover")!.attributes["id"]! }
        #expect(id1 == id2)   // same instance → same id across body() calls
    }

    @Test("two Popovers get distinct ids") func distinctIDs() {
        let a = building { pop(trigger: { [Button("A") {}] }, content: { [text("a")] }) }
        let b = building { pop(trigger: { [Button("B") {}] }, content: { [text("b")] }) }
        let idA = firstWithClass(el(a)!, "sw-popover")!.attributes["id"]!
        let idB = firstWithClass(el(b)!, "sw-popover")!.attributes["id"]!
        #expect(idA != idB)
    }

    @Test("placement maps to the panel's position-area") func placement() {
        func area(_ p: PopoverPlacement) -> String? {
            firstWithClass(el(building { pop(placement: p, trigger: { [Button("Open") {}] }, content: { [text("x")] }) })!, "sw-popover")!.style["position-area"]
        }
        #expect(area(.top) == "top")
        #expect(area(.bottom) == "bottom")
        #expect(area(.leading) == "inline-start")
        #expect(area(.trailing) == "inline-end")
    }

    @Test("caller panel attributes apply") func panelAttributes() {
        let node = building {
            pop(panelAttrs: [.attr("data-testid", "my-panel")], trigger: { [Button("Open") {}] }, content: { [text("x")] })
        }
        let panel = firstWithClass(el(node)!, "sw-popover")!
        #expect(panel.attributes["data-testid"] == "my-panel")
    }

    @Test("the public Popover(...) free function lowers to an embedded component") func freeFunctionEmbeds() {
        let node = building { Popover(trigger: { [Button("Open") {}] }, content: { [text("x")] }) }
        if case .component = node {} else { Issue.record("expected an embedded component node, got \(node)") }
    }

    @Test("stylesheet: anchored popover panel with token-driven entry animation") func stylesheet() {
        let css = popoverStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-popover"))
        #expect(css.contains(":popover-open"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("var(--sw-duration)"))          // → reduced-motion collapses the animation
        #expect(css.contains("var(--sw-surface)"))
    }

    #if DEBUG
    @Test("DEBUG: a trigger builder yielding zero nodes fires a diagnostic") func zeroNodesDiagnostic() {
        let msgs = capturingDiagnostics {
            building { _ = pop(trigger: { [] }, content: { [text("x")] }) }
        }
        #expect(msgs.contains { $0.contains("trigger") })
    }

    @Test("DEBUG: a trigger builder yielding two nodes fires a diagnostic") func twoNodesDiagnostic() {
        let msgs = capturingDiagnostics {
            building { _ = pop(trigger: { [Button("A") {}, Button("B") {}] }, content: { [text("x")] }) }
        }
        #expect(msgs.contains { $0.contains("trigger") })
    }

    @Test("DEBUG: a non-element trigger node fires a diagnostic") func nonElementDiagnostic() {
        let msgs = capturingDiagnostics {
            building { _ = pop(trigger: { [text("just text")] }, content: { [text("x")] }) }
        }
        #expect(msgs.contains { $0.contains("trigger") })
    }
    #endif
}
