// Tests/SwiflowTestingTests/FirePressSettleTests.swift
//
// Audit VI Wave-1: the general event APIs (fire/press) that end the
// dig-the-handler-out-of-the-body ritual (AutocompleteTests hand-invoked
// keydown handlers 9×), and settle()'s flush-first fix (a direct @State
// mutation from test code no longer needs a manual flush() before settle).
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class KeyEcho {
    @State var last: String = "none"
    var body: VNode {
        div {
            p("last: \(last)")
            element("input", attributes: [
                .attr("type", "text"),
                .on(.keydown) { (e: EventInfo) in self.last = e.key ?? "?" },
                .on(.custom("focusin")) { _ in self.last = "focused" },
            ], children: [])
        }
    }
}

@Component
private final class DirectMutation {
    @State var n: Int = 0
    var body: VNode { p("n: \(n)") }
}

@Suite("fire/press + settle flush-first")
@MainActor
struct FirePressSettleTests {

    @Test("press dispatches keydown with the key passed through verbatim")
    func pressPassesKey() {
        let h = render(KeyEcho())
        h.press(key: "ArrowDown")
        #expect(h.find("p")?.text == "last: ArrowDown")
        h.press(key: "Escape")
        #expect(h.find("p")?.text == "last: Escape")
    }

    @Test("fire dispatches arbitrary event types — no more handler digging")
    func fireArbitraryEvent() {
        let h = render(KeyEcho())
        h.fire("focusin", on: "input")
        #expect(h.find("p")?.text == "last: focused")
    }

    @Test("STRICT: press on an element without a keydown handler records")
    func pressStrict() {
        let h = render(DirectMutation())
        withKnownIssue {
            h.press("p", key: "Enter")
        }
    }

    @Test("settle() flushes first — direct @State mutation needs no manual flush()")
    func settleFlushesFirst() async throws {
        let component = DirectMutation()
        let h = AsyncTestHarness(component)
        try await h.settle()
        #expect(h.find("p")?.text == "n: 0")

        component.n = 42          // direct mutation from test code: dirty mark queued, no task started
        try await h.settle()      // pre-fix this required h.flush() first
        #expect(h.find("p")?.text == "n: 42")
    }
}
