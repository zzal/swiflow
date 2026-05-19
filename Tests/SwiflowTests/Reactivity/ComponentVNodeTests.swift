// Tests/SwiflowTests/Reactivity/ComponentVNodeTests.swift
import Testing
@testable import Swiflow

@Suite("VNode.component")
struct ComponentVNodeTests {

    final class Counter: Component {
        var body: VNode { .text("0") }
    }

    final class Greeter: Component {
        var body: VNode { .text("hi") }
    }

    @Test("VNode.component is constructable and Equatable by typeID + key")
    func componentCaseEquatable() {
        let a = VNode.component(.init(Counter.self) { Counter() })
        let b = VNode.component(.init(Counter.self) { Counter() })
        let c = VNode.component(.init(Greeter.self) { Greeter() })
        let d = VNode.component(.init(Counter.self, key: "list-row") { Counter() })

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("DSL `component(_:key:)` produces a VNode.component case")
    func dslComponentFreeFunction() {
        let v = component({ Counter() })
        guard case .component(let desc) = v else {
            Issue.record("Expected .component case, got \(v)")
            return
        }
        #expect(desc.typeID == ObjectIdentifier(Counter.self))
        #expect(desc.key == nil)
    }

    @Test("DSL accepts key argument")
    func dslComponentWithKey() {
        let v = component({ Counter() }, key: "row-7")
        guard case .component(let desc) = v else {
            Issue.record("Expected .component case")
            return
        }
        #expect(desc.key == "row-7")
    }

    @Test("ResultBuilder accepts component children alongside element children")
    func builderMixesElementsAndComponents() {
        let parent = div {
            h1("Heading")
            component({ Counter() })
            p("Footer")
        }
        guard case .element(let data) = parent else {
            Issue.record("Expected .element"); return
        }
        #expect(data.children.count == 3)
        guard case .component(let desc) = data.children[1] else {
            Issue.record("Expected children[1] to be .component, got \(data.children[1])")
            return
        }
        #expect(desc.typeID == ObjectIdentifier(Counter.self))
    }
}
