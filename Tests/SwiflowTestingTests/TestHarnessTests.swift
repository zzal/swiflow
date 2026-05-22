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
