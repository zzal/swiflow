// Tests/SwiflowUITests/CalloutTests.swift
// Callout is a stateless semantic status banner — mirrors Badge's soft-tint sheet
// approach (as a bordered banner rather than a pill) and Toast's variant → role/aria-live
// mapping (danger is assertive; info/success/warning are polite). No Icon (M14).
import Testing
import Swiflow
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

@Suite("Callout")
@MainActor
struct CalloutTests {
    @Test("renders a div with the default info variant class") func renders() {
        let node = Callout("Heads up")
        let c = el(node)!
        #expect(c.tag == "div")
        #expect(c.attributes["class"] == "sw-callout sw-callout--info")
        #expect(allText(node).contains("Heads up"))
    }

    @Test("variant maps to the modifier class") func variant() {
        #expect(el(Callout("x", variant: .success))!.attributes["class"] == "sw-callout sw-callout--success")
        #expect(el(Callout("x", variant: .warning))!.attributes["class"] == "sw-callout sw-callout--warning")
        #expect(el(Callout("x", variant: .danger))!.attributes["class"] == "sw-callout sw-callout--danger")
    }

    @Test("danger is assertive (role=alert/aria-live=assertive)") func dangerAssertive() {
        let c = el(Callout("Boom", variant: .danger))!
        #expect(c.attributes["role"] == "alert")
        #expect(c.attributes["aria-live"] == "assertive")
    }

    @Test("info/success/warning are polite (role=status/aria-live=polite)") func othersPolite() {
        for variant: CalloutVariant in [.info, .success, .warning] {
            let c = el(Callout("x", variant: variant))!
            #expect(c.attributes["role"] == "status")
            #expect(c.attributes["aria-live"] == "polite")
        }
    }

    @Test("optional title renders a .sw-callout__title node with the title text") func titlePresent() {
        let c = el(Callout("Body copy", title: "Heads up"))!
        let titleNode = firstWithClass(c, "sw-callout__title")
        #expect(titleNode != nil)
        #expect(allText(.element(titleNode!)) == "Heads up")
    }

    @Test("title node is absent when title is nil") func titleAbsent() {
        let c = el(Callout("Body copy"))!
        #expect(firstWithClass(c, "sw-callout__title") == nil)
    }

    @Test("message renders in .sw-callout__message") func message() {
        let c = el(Callout("Something happened"))!
        let messageNode = firstWithClass(c, "sw-callout__message")
        #expect(messageNode != nil)
        #expect(allText(.element(messageNode!)) == "Something happened")
    }

    @Test("actions builder output lands in a .sw-callout__actions container") func actionsPresent() {
        let c = el(Callout("Body") {
            element("button", attributes: [.class("sw-callout-test-action")], children: [text("Undo")])
        })!
        let actionsNode = firstWithClass(c, "sw-callout__actions")
        #expect(actionsNode != nil)
        #expect(firstWithClass(c, "sw-callout-test-action") != nil)
    }

    @Test("actions container is absent when the builder yields no children") func actionsAbsentWhenEmpty() {
        let c = el(Callout("Body"))!
        #expect(firstWithClass(c, "sw-callout__actions") == nil)
    }

    @Test("caller attributes and class merge onto the callout") func callerMerge() {
        let c = el(Callout("x", .class("hero"), .attr("id", "banner")))!
        #expect(c.attributes["class"] == "sw-callout sw-callout--info hero")
        #expect(c.attributes["id"] == "banner")
    }

    @Test("stylesheet: bordered banner with per-variant accent rail + soft tint bg, title uses -strong text") func stylesheet() {
        let css = calloutStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-callout"))
        #expect(css.contains("border-inline-start: 3px solid var(--sw-info)"))
        #expect(css.contains("color-mix(in oklab, var(--sw-info) 8%, var(--sw-surface))"))
        #expect(css.contains(".sw-callout__title"))
        #expect(css.contains("var(--sw-info-strong)"))
        #expect(css.contains(".sw-callout--success"))
        #expect(css.contains("var(--sw-success-strong)"))
        #expect(css.contains(".sw-callout--warning"))
        #expect(css.contains("var(--sw-warning-strong)"))
        #expect(css.contains(".sw-callout--danger"))
        #expect(css.contains("var(--sw-danger-strong)"))
        #expect(css.contains(".sw-callout__actions"))
    }
}
