// Tests/SwiflowTestingTests/DidMountHookTests.swift
//
// Audit IV Wave-2 #5: the framework mount hook @Persisted hydration rides.
// A protocol REQUIREMENT (not a plain extension method) because the diff
// calls it through `any Component` — an extension method would statically
// dispatch to the no-op and synthesized overrides would never run.
import Testing
import Swiflow
import SwiflowTesting

@Component
private final class HookProbe {
    @State var n: Int = 0
    var log: [String] = []
    var body: VNode {
        div {
            p { VNode.text("count \(n)") }
            button(.on(.click) { self.n += 1 }) { VNode.text("inc") }
        }
    }
    func _swiflowDidMount() { log.append("didMount") }
    func onAppear() { log.append("onAppear") }
    func onChange() { log.append("onChange") }
}

/// Hand-rolled (non-macro) Component — the protocol default must cover it.
@MainActor
private final class PlainComponent: Component {
    var body: VNode { .text("plain") }
}

@Suite("Component._swiflowDidMount")
@MainActor
struct DidMountHookTests {

    @Test("fires once on mount, BEFORE onAppear; never on re-render")
    func firesOnceBeforeOnAppear() {
        let probe = HookProbe()
        let h = render(probe)
        #expect(probe.log == ["didMount", "onAppear"],
                "the hook precedes onAppear so hydration is in flight before user mount code runs")

        h.click("button")
        #expect(probe.log == ["didMount", "onAppear", "onChange"],
                "re-renders take the onChange branch — the hook is mount-only")
    }

    @Test("a component without the hook mounts fine on the protocol default")
    func defaultNoOpCovers() {
        let h = render(PlainComponent())
        #expect(h.allText == "plain")
    }
}
