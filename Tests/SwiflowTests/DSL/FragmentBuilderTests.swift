// Tests/SwiflowTests/DSL/FragmentBuilderTests.swift
import Testing
@testable import Swiflow

@Suite("DSL — fragment slots")
@MainActor
struct FragmentBuilderTests {
    @Test("A false `if` produces one empty fragment slot, not zero children")
    func falseIfIsOneEmptySlot() {
        let show = false
        let v: VNode = div {
            p("always")
            if show { p("maybe") }
        }
        guard case .element(let data) = v else { Issue.record("expected element"); return }
        #expect(data.children.count == 2)              // <p> + fragment slot
        guard case .fragment(let inner) = data.children[1] else { Issue.record("slot 1 not a fragment"); return }
        #expect(inner.isEmpty)
    }

    @Test("A true `if` produces one fragment slot holding its content")
    func trueIfIsOneFullSlot() {
        let show = true
        let v: VNode = div {
            p("always")
            if show { p("maybe") }
        }
        guard case .element(let data) = v, case .fragment(let inner) = data.children[1] else {
            Issue.record("expected element with fragment slot"); return
        }
        #expect(inner.count == 1)
        #expect(data.children.count == 2)
    }

    @Test("A for-loop produces one fragment slot holding all items")
    func forLoopIsOneSlot() {
        let v: VNode = ul {
            for i in 0..<3 { li("\(i)") }
        }
        guard case .element(let data) = v else { Issue.record("expected element"); return }
        #expect(data.children.count == 1)             // one fragment slot for the loop
        guard case .fragment(let inner) = data.children[0] else { Issue.record("not a fragment"); return }
        #expect(inner.count == 3)
    }
}
