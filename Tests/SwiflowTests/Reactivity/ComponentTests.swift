// Tests/SwiflowTests/Reactivity/ComponentTests.swift
import Testing
@testable import Swiflow

@Suite("Component")
struct ComponentTests {

    final class Counter: Component {
        var clickCount = 0
        var body: VNode { .text("count=\(clickCount)") }
    }

    final class Greeter: Component {
        var body: VNode { .text("hi") }
    }

    @Test("AnyComponent erases concrete type but preserves identity")
    func anyComponentIdentity() {
        let counter = Counter()
        let erased = AnyComponent(counter)
        #expect(erased.typeID == ObjectIdentifier(Counter.self))
        #expect(erased.instance === counter)
    }

    @Test("Default lifecycle hooks are no-ops (Counter doesn't override)")
    func defaultLifecycleNoops() {
        let counter = Counter()
        counter.onMount()
        counter.onUpdate(prev: counter)
        counter.onUnmount()
        // No assertion needed — just verifying these compile and don't crash.
        #expect(counter.clickCount == 0)
    }

    @Test("ComponentDescription captures typeID and key for diff identity")
    func descriptionIdentity() {
        let d1 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { AnyComponent(Counter()) })
        let d2 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { AnyComponent(Counter()) })
        let d3 = ComponentDescription(typeID: ObjectIdentifier(Greeter.self), key: nil, factory: { AnyComponent(Greeter()) })
        let d4 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: "a", factory: { AnyComponent(Counter()) })
        #expect(d1 == d2)
        #expect(d1 != d3)
        #expect(d1 != d4)
    }

    @Test("ComponentDescription.instantiate() invokes the factory and returns AnyComponent")
    func instantiateProducesAnyComponent() {
        let desc = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { AnyComponent(Counter()) })
        let any1 = desc.instantiate()
        let any2 = desc.instantiate()
        #expect(any1.typeID == ObjectIdentifier(Counter.self))
        #expect(any1.instance !== any2.instance, "Each instantiate() must produce a fresh instance")
    }
}
