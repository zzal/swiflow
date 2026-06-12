import Testing
@testable import Swiflow

@MainActor
struct TaskModifierTests {

    @Test("ElementData equality ignores taskBindings") func taskBindingsAreExcludedFromEquality() {
        // Two ElementData identical except for taskBindings must compare equal
        // (closures aren't Equatable; taskBindings is out-of-band, like refBindings).
        let a = ElementData(tag: "div")
        var b = ElementData(tag: "div")
        b.taskBindings = [TaskBinding(dependency: nil, body: {})]
        #expect(a == b)
    }

    @Test("A fresh element has no task bindings") func taskBindingsDefaultEmpty() {
        #expect(ElementData(tag: "div").taskBindings.isEmpty)
    }

    private func bindings(of node: VNode) -> [TaskBinding] {
        guard case .element(let data) = node else { return [] }
        return data.taskBindings
    }

    @Test(".task without rerunOn records a binding with a nil dependency") func bareTaskAppendsBindingWithNoDependency() {
        let node = div { }.task { }
        let bs = bindings(of: node)
        #expect(bs.count == 1)
        #expect(bs[0].dependency == nil)
    }

    @Test(".task(rerunOn:) records a dependency that compares equal only to the same value") func taskRerunOnAppendsBindingWithDependency() {
        let node = div { }.task(rerunOn: 7) { }
        let bs = bindings(of: node)
        #expect(bs.count == 1)
        #expect(bs[0].dependency != nil)
        #expect(bs[0].dependency?.equals(AnyEquatableBox(7)) == true)
        #expect(bs[0].dependency?.equals(AnyEquatableBox(8)) == false)
    }

    @Test("Chained .task modifiers append bindings in declaration order") func multipleTasksStackInOrder() {
        let node = div { }.task(rerunOn: 1) { }.task { }
        #expect(bindings(of: node).count == 2)
        #expect(bindings(of: node)[0].dependency != nil)
        #expect(bindings(of: node)[1].dependency == nil)
    }

    @Test(".task on a non-element node emits a diagnostic and returns the node unchanged") func taskOnNonElementIsDiagnosedAndPassesThrough() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let node = VNode.text("hi").task { }
        #expect(captured.count == 1)
        if case .text(let s) = node { #expect(s == "hi") } else { Issue.record("expected text node") }
    }
}
