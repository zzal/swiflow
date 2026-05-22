// Tests/SwiflowTestingTests/TestHarnessTests.swift
import Testing
@testable import SwiflowTesting
import Swiflow

// Minimal inline component used by Task 2 tests.
// Expanded to full Counter + SignIn in Task 5.
@MainActor
private final class MinimalCounter: Component {
    @State var count: Int = 0
    var body: VNode { p("Count: \(count)") }
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
        #expect(ps.count == 1)
        #expect(ps[0].text == "Count: 0")
    }

    @Test("exists returns true iff at least one match")
    func existsReturnsTrueAndFalse() {
        let r = render(MinimalCounter())
        #expect(r.exists("p", text: "Count: 0") == true)
        #expect(r.exists("p", text: "Count: 99") == false)
        #expect(r.exists("button") == false)
    }
}
