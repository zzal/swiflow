// Tests/SwiflowUITests/RadioGroupCollisionTests.swift
//
// Audit V Wave-1 (final item): the RadioGroup name-collision registry.
// Two same-label groups slug to the same native radio `name` → the browser
// treats them as ONE group (selection + arrow roving cross). A DEBUG-only
// mount sentinel gives the stateless free function the lifecycle identity
// a registry needs — these tests drive it through the REAL harness, whose
// TestRenderer fires the same onAppear/onDisappear the browser does.
//
// .serialized: the registry is process-global; only this suite mounts
// RadioGroups (the legacy VNode-walker tests never mount), but the suite's
// own tests must not interleave on it.
import Testing
import Swiflow
@testable import SwiflowUI
@testable import SwiflowTesting

@Component
private final class TwoGroupsPage {
    let secondName: String?
    init(secondName: String? = nil) { self.secondName = secondName }
    var body: VNode {
        div {
            RadioGroup("Collision Role", selection: Binding(get: { "a" }, set: { _ in }),
                       options: ["a", "b"])
            RadioGroup("Collision Role", selection: Binding(get: { "a" }, set: { _ in }),
                       options: ["a", "b"], name: secondName)
        }
    }
}

@Component
private final class DistinctGroupsPage {
    var body: VNode {
        div {
            RadioGroup("Collision Plan", selection: Binding(get: { "x" }, set: { _ in }), options: ["x"])
            RadioGroup("Collision Tier", selection: Binding(get: { "x" }, set: { _ in }), options: ["x"])
        }
    }
}

@Component
private final class OneGroupPage {
    @State var tick: Int = 0
    var body: VNode {
        div {
            p("tick \(tick)")
            RadioGroup("Collision Solo", selection: Binding(get: { "x" }, set: { _ in }), options: ["x"])
            button(.on(.click) { self.tick += 1 }) { VNode.text("bump") }
        }
    }
}

@Suite("RadioGroup name-collision registry", .serialized)
struct RadioGroupCollisionTests {

    @MainActor
    private func captureWarnings(_ body: () -> Void) -> [String] {
        RadioNameRegistry._reset()
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    @Test("two same-label groups on one page warn once, naming both and the fix")
    @MainActor
    func sameLabelWarns() {
        let warnings = captureWarnings {
            let h = render(TwoGroupsPage())
            _ = h
        }
        #expect(warnings.count == 1)
        let msg = warnings.first ?? ""
        #expect(msg.contains("Collision Role"), "names the colliding groups")
        #expect(msg.contains("collision-role"), "names the shared native name")
        #expect(msg.contains("name:"), "points at the explicit-name fix")
    }

    @Test("distinct labels stay silent")
    @MainActor
    func distinctLabelsSilent() {
        let warnings = captureWarnings { _ = render(DistinctGroupsPage()) }
        #expect(warnings.isEmpty)
    }

    @Test("same label with an explicit distinct name: stays silent — the documented fix")
    @MainActor
    func explicitNameSilent() {
        let warnings = captureWarnings { _ = render(TwoGroupsPage(secondName: "role-2")) }
        #expect(warnings.isEmpty)
    }

    @Test("unmount unregisters — a fresh same-name group after teardown never warns")
    @MainActor
    func unmountUnregisters() {
        let warnings = captureWarnings {
            let first = render(OneGroupPage())
            first.unmount()
            _ = render(OneGroupPage())   // same slugged name, prior owner gone
        }
        #expect(warnings.isEmpty)
    }

    @Test("re-render without unmount does not re-register — onAppear is mount-only")
    @MainActor
    func rerenderNoDuplicateWarn() {
        let warnings = captureWarnings {
            let h = render(OneGroupPage())
            h.click("button")            // state change → re-render, same instance
            h.click("button")
        }
        #expect(warnings.isEmpty)
    }
}
