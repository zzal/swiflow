// Tests/SwiflowTestingTests/LiveNodeTests.swift
//
// Audit VI Wave-2 #2: live, scopable, actable found nodes. TestNode was a
// dead flat snapshot — no children, no handlers, no actions — forcing
// find-then-positional-address and going silently stale after a re-render.
// It now wraps the live MountNode (a class the diff mutates in place):
// reads reflect the CURRENT tree, actions dispatch on THE found element,
// scoped find searches its subtree, and an action on a node the diff has
// since detached records an Issue instead of firing a ghost handler.
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class Inbox {
    @State var query: String = ""
    @State var submitted: String = "none"
    @State var showBanner: Bool = true
    var body: VNode {
        div {
            element("label", attributes: [], children: [
                element("span", attributes: [], children: [text("Search")]),
                element("input", attributes: [
                    .prop("value", .string(query)),
                    .on(.input) { (e: EventInfo) in self.query = e.targetValue ?? "" },
                    .on(.blur) { _ in self.submitted = self.query },
                ], children: []),
            ])
            p("submitted: \(submitted)")
            if showBanner {
                element("section", attributes: [.attr("class", "banner")], children: [
                    p("Welcome!"),
                    button("Dismiss", .on(.click) { self.showBanner = false }),
                ])
            }
            element("footer", attributes: [], children: [
                button("Refresh", .on(.click) { self.submitted = "refreshed" }),
            ])
        }
    }
}

@Suite("live TestNode — reads current, acts on the found element")
@MainActor
struct LiveNodeTests {

    @Test("the audit's shape: find(role:label:).type(_:).blur() chains")
    func typeAndBlurChain() {
        let h = render(Inbox())
        h.find(role: "textbox", label: "Search")!.type("swiflow").blur()
        #expect(h.find("p")?.text == "submitted: swiflow")
    }

    @Test("reads are LIVE: the same node reflects the tree after a re-render")
    func liveReads() {
        let h = render(Inbox())
        let field = h.find(role: "textbox")!
        #expect(field.properties["value"] == "")
        field.type("hello")
        #expect(field.properties["value"] == "hello",
                "the bound value re-rendered; the held node sees it")
    }

    @Test("actions dispatch on THE found element, not first-in-document-order")
    func actsOnFoundElement() {
        let h = render(Inbox())
        // "Refresh" is the SECOND button in document order — the exact
        // pitfall that mis-clicked Alert's Cancel in the #199 liveness test.
        h.find(role: "button", label: "Refresh")!.click()
        #expect(h.find("p")?.text == "submitted: refreshed")
    }

    @Test("scoped find searches only the node's subtree")
    func scopedFind() {
        let h = render(Inbox())
        let banner = h.find(class: "banner")!
        #expect(banner.find("button")?.text == "Dismiss")
        #expect(banner.find("footer") == nil)
        let footer = h.find("footer")!
        #expect(footer.find("button")?.text == "Refresh")
    }

    @Test("STRICT: an action on a detached node records an Issue")
    func detachedActionRecords() {
        let h = render(Inbox())
        let dismiss = h.find(role: "button", label: "Dismiss")!
        dismiss.click()                      // removes the banner subtree
        #expect(h.find(class: "banner") == nil)
        withKnownIssue {
            dismiss.click()                  // the held node is now detached
        }
    }

    @Test("STRICT: an action with no matching handler records an Issue")
    func noHandlerRecords() {
        let h = render(Inbox())
        withKnownIssue {
            h.find("p")!.click()
        }
    }
}
