// Tests/SwiflowTests/DSL/EventModifierAmbientTests.swift
import Testing
@testable import Swiflow

// Sets the @MainActor HandlerAmbient.current global with defer-restore, but
// both test bodies are synchronous @MainActor — they run atomically with no
// suspension points, so the ambient cannot leak across tests and no
// .serialized is needed.
@Suite("Event modifiers via ambient registry")
@MainActor
struct EventModifierAmbientTests {

    @Test func postfixOnRegistersThroughAmbientRegistry() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }

        var fired = false
        let node = div { VNode.text("hi") }.on(.click) { fired = true }

        guard case .element(let data) = node,
              let handler = data.handlers["click"] else {
            Issue.record("expected a click handler on the element")
            return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test func attributeOnRegistersThroughAmbientRegistry() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }

        var received: EventInfo? = nil
        let attr = Attribute.on(.input) { info in received = info }

        guard case .handler(_, let handler) = attr else {
            Issue.record("expected .handler attribute")
            return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "input", targetValue: "x"))
        #expect(received?.targetValue == "x")
    }
}
