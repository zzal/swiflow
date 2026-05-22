// Tests/SwiflowTestingTests/TestHarnessTests.swift
import Testing
@testable import SwiflowTesting
import Swiflow

// Minimal inline component used by Task 2–4 tests.
// Expanded to full Counter + SignIn in Task 5.
@MainActor
private final class MinimalCounter: Component {
    @State var count: Int = 0
    @State var label: String = "Swiflow"

    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
            input(.attr("type", "text"),
                  .on(.input) { info in self.label = info.targetValue ?? self.label })
            p("Hello, \(self.label)!")
        }
    }
}

@Suite("TestHarness — allText")
@MainActor
struct AllTextTests {
    @Test("allText includes initial state")
    func allTextInitial() {
        let r = render(MinimalCounter())
        #expect(r.allText.contains("Count: 0"))
    }
}

@Suite("TestHarness — queries")
@MainActor
struct QueryTests {
    @Test("find returns the first matching element with correct fields")
    func findReturnsFirstMatch() {
        let r = render(MinimalCounter())
        let node = r.find("p", text: "Count: 0")
        #expect(node != nil)
        #expect(node?.tag == "p")
        #expect(node?.text == "Count: 0")
    }

    @Test("find returns nil when no match")
    func findReturnsNil() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Count: 99") == nil)
        #expect(r.find("h1") == nil)
    }

    @Test("find without text matches first element with that tag")
    func findByTagOnly() {
        let r = render(MinimalCounter())
        let node = r.find("p")
        #expect(node != nil)
        #expect(node?.tag == "p")
    }

    @Test("findAll returns all matching elements")
    func findAllReturnsAll() {
        let r = render(MinimalCounter())
        let ps = r.findAll("p")
        #expect(ps.count == 2)
        #expect(ps[0].text == "Count: 0")
        #expect(ps[1].text == "Hello, Swiflow!")
    }

    @Test("exists returns true iff at least one match")
    func existsReturnsTrueAndFalse() {
        let r = render(MinimalCounter())
        #expect(r.exists("p", text: "Count: 0") == true)
        #expect(r.exists("p", text: "Count: 99") == false)
        #expect(r.exists("button") == true)
        #expect(r.exists("h1") == false)
    }
}

@Suite("TestHarness — interactions")
@MainActor
struct InteractionTests {
    @Test("click fires the handler and state updates")
    func clickIncrementsCount() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Count: 0") != nil)
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 1") != nil)
        #expect(r.find("p", text: "Count: 0") == nil)
    }

    @Test("multiple clicks accumulate")
    func multipleClicks() {
        let r = render(MinimalCounter())
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 3") != nil)
    }

    @Test("input fires the input handler and state updates")
    func inputUpdatesLabel() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Hello, Swiflow!") != nil)
        r.input(value: "World")
        #expect(r.find("p", text: "Hello, World!") != nil)
        #expect(r.find("p", text: "Hello, Swiflow!") == nil)
    }

    @Test("click is a no-op when no handler is registered")
    func clickNoHandlerIsNoOp() {
        let r = render(MinimalCounter())
        r.click("p")     // <p> has no click handler — must not crash
        #expect(r.find("p", text: "Count: 0") != nil)
    }

    @Test("input at out-of-bounds index is a no-op")
    func inputOutOfBoundsIsNoOp() {
        let r = render(MinimalCounter())
        r.input(at: 99, value: "boom")   // no crash
        #expect(r.find("p", text: "Hello, Swiflow!") != nil)
    }
}
