// Tests/SwiflowTestingTests/LifecycleHarnessTests.swift
import Testing
import Swiflow
import SwiflowTesting

@MainActor @Component
private final class LifecycleProbe {
    @State var n: Int = 0
    var log: [String] = []
    var body: VNode {
        div {
            p { VNode.text("count \(n)") }
            button(.on(.click) { self.n += 1 }) { VNode.text("inc") }
        }
    }
    func onAppear() { log.append("appear") }
    func onChange() { log.append("change") }
    func onDisappear() { log.append("disappear") }
}

@Suite
@MainActor
struct LifecycleHarnessTests {

    @Test func lifecycleHooksFireUnderTest() {
        let probe = LifecycleProbe()
        let harness = render(probe)

        #expect(probe.log == ["appear"], "onAppear must fire on mount, as in the browser")

        harness.click("button")
        #expect(probe.log == ["appear", "change"], "onChange must fire on re-render")

        harness.unmount()
        #expect(probe.log == ["appear", "change", "disappear"], "onDisappear must fire on unmount")
    }
}
