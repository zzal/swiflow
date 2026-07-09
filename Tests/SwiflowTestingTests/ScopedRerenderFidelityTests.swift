// Tests/SwiflowTestingTests/ScopedRerenderFidelityTests.swift
//
// Audit VI Wave-3: the headline fidelity drift. Since PR #90 the browser
// takes a SCOPED re-render for the common single-dirty case (planRerender →
// scopedRerender) — the harness always full-root diffed, so it green-lit
// cross-component propagation production doesn't deliver and could never
// catch scoped-path regressions. TestRenderer.flushDirty now runs the SAME
// shared planRerender/scopedRerender the browser runs.
//
// This file REPLACES RootRerenderTests, whose one test enshrined the
// pre-#90 semantics ("a child's @State change re-renders from the root so
// the parent sees mutated shared state" — the browser has not done that
// since scoped re-rendering shipped).
import Testing
import Swiflow
@testable import SwiflowTesting

private final class SharedLabel {
    var value = "before"
}

@MainActor
private enum EvalProbe {
    static var parentEvals = 0
}

@Component
private final class LabelMutatingChild {
    let model: SharedLabel
    @State var tick: Int = 0
    init(model: SharedLabel) { self.model = model }
    var body: VNode {
        button(.on(.click) {
            self.model.value = "after"
            self.tick += 1
        }) { VNode.text("mutate \(tick)") }
    }
}

@Component
private final class SharedLabelParent {
    let model = SharedLabel()
    @State var own: Int = 0
    var body: VNode {
        EvalProbe.parentEvals += 1
        return div {
            p("label: \(model.value), own: \(own)")
            embed { LabelMutatingChild(model: self.model) }
            element("footer", attributes: [], children: [
                button("parent bump", .on(.click) { self.own += 1 }),
            ])
        }
    }
}

@Suite("scoped re-render fidelity — the harness takes the browser's path")
@MainActor
struct ScopedRerenderFidelityTests {

    @Test("a child-only @State change is SCOPED: the parent body does not re-evaluate")
    func childDirtyIsScoped() {
        let h = render(SharedLabelParent())
        EvalProbe.parentEvals = 0

        h.click("button", text: "mutate")

        #expect(EvalProbe.parentEvals == 0,
                "production's scoped path never re-evaluates the parent")
        #expect(h.find("p")?.text.contains("label: before") == true,
                "shared mutable state read by the parent is NOT refreshed — exactly the browser behavior since PR #90")
        #expect(h.find("button", text: "mutate")?.text == "mutate 1",
                "the child's own subtree DID re-render")
    }

    @Test("a root-dirty change takes the full path and refreshes everything")
    func rootDirtyIsFull() {
        let h = render(SharedLabelParent())
        EvalProbe.parentEvals = 0

        h.click("button", text: "parent bump")

        #expect(EvalProbe.parentEvals == 1)
        #expect(h.find("p")?.text.contains("own: 1") == true)
    }

    @Test("after a child mutates shared state, the NEXT full render shows it — the deferred-propagation shape apps actually get")
    func sharedStateShowsOnNextFullRender() {
        let h = render(SharedLabelParent())
        h.click("button", text: "mutate")
        #expect(h.find("p")?.text.contains("label: before") == true)

        h.click("button", text: "parent bump")   // root-dirty → full render
        #expect(h.find("p")?.text.contains("label: after") == true)
    }
}
