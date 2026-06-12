// Tests/SwiflowTestingTests/RootRerenderTests.swift
import Testing
import Swiflow
import SwiflowTesting

private final class SharedLabel {
    var value = "before"
}

@MainActor @Component
private final class LabelMutatingChild {
    let model: SharedLabel
    @State var tick: Int = 0
    init(model: SharedLabel) { self.model = model }
    var body: VNode {
        button(.on(.click) {
            self.model.value = "after"
            self.tick += 1
        }) { VNode.text("mutate") }
    }
}

@MainActor @Component
private final class SharedLabelParent {
    let model = SharedLabel()
    var body: VNode {
        div {
            p { VNode.text("label: \(model.value)") }
            embed { LabelMutatingChild(model: self.model) }
        }
    }
}

@Suite
@MainActor
struct RootRerenderTests {

    /// Audit finding (Unit 9 HIGH): a nested component's @State change used to
    /// diff only that subtree; production re-renders from root. The parent's
    /// body reads shared state the child mutates — it must refresh under test
    /// exactly as it does in the browser.
    @Test("A child's @State change re-renders from the root so the parent sees mutated shared state") func parentRefreshesWhenChildMutatesSharedState() {
        let harness = render(SharedLabelParent())
        #expect(harness.find("p")?.text == "label: before")

        harness.click("button")

        #expect(harness.find("p")?.text == "label: after")
    }
}
