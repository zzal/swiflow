// Tests/SwiflowTests/Binding/ValueBindingTests.swift
//
// Task C — Phase 7 / Phase 15 refresh. Validates the two pieces that
// together make `.value(_:Binding<...>)` work without depending on
// SwiflowWeb (which is gated behind `#if canImport(JavaScriptKit)` and
// unavailable to host-side tests):
//
//   1. `Attribute.compound([Attribute])` is recursively flattened by
//      `applyAttributes` — i.e. a single modifier can produce multiple
//      bag effects in one go (property + handler).
//   2. The binding's get/set contract round-trips correctly when wired
//      to a synthetic `(EventInfo) -> Void` closure shaped exactly the
//      way `.value(_:)` will shape it inside SwiflowWeb.
//
// We deliberately avoid invoking SwiflowWeb's `.value(_:)` directly
// because `_registerAmbientHandler` requires a mounted Renderer (only
// available in WASM). Composition of the two pieces above is trivial;
// covering them independently is enough confidence.
//
// Phase 15: bindings now come from `@State`'s `$`-prefix projection on
// a `@MainActor @Component` host class, not from `State<T>(wrappedValue:)`
// directly (the class no longer exists).
import Testing
@testable import Swiflow

@MainActor @Component
private final class VB_StringHost {
    @State var value: String = "initial"
    var body: VNode { .text("") }
}

@MainActor @Component
private final class VB_IntHost {
    @State var value: Int = 0
    var body: VNode { .text("") }
}

@MainActor @Component
private final class VB_DoubleHost {
    @State var value: Double = 0.0
    var body: VNode { .text("") }
}

@MainActor
@Suite(".value(_:Binding) building blocks")
struct ValueBindingTests {

    // MARK: - .compound fold

    @Test("Attribute.compound is recursively flattened by applyAttributes")
    func compoundFlattens() {
        let node = div(.compound([
            .attr("data-foo", "bar"),
            .property(name: "title", value: .string("hi")),
        ]))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["data-foo"] == "bar")
        #expect(data.properties["title"] == .string("hi"))
    }

    @Test("Nested compounds flatten through multiple levels")
    func nestedCompoundFlattens() {
        let node = div(.compound([
            .compound([
                .attr("data-a", "1"),
                .compound([.property(name: "title", value: .string("deep"))]),
            ]),
            .style(name: "color", value: "red"),
        ]))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["data-a"] == "1")
        #expect(data.properties["title"] == .string("deep"))
        #expect(data.style["color"] == "red")
    }

    @Test("Compound containing .skip is honored by the fold")
    func compoundWithSkip() {
        let node = div(.compound([
            .attr("data-keep", "yes"),
            .attr("data-drop", false),   // emits .skip
        ]))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["data-keep"] == "yes")
        #expect(data.attributes["data-drop"] == nil)
    }

    // MARK: - String binding round-trip

    @Test(".value-shaped compound for Binding<String> contains property + input handler")
    func stringValueCompoundShape() {
        let host = VB_StringHost()
        let binding = host.$value

        // Hand-build the exact `Attribute.compound([…])` that
        // SwiflowWeb's `.value(_:Binding<String>)` will produce.
        let handler = EventHandler(id: 0) { info in
            binding.set(info.targetValue ?? "")
        }
        let attr: Attribute = .compound([
            .property(name: "value", value: .string(binding.get())),
            .handler(event: "input", value: handler),
        ])

        let node = input(attr)
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.properties["value"] == .string("initial"))
        #expect(data.handlers["input"] != nil)
    }

    @Test("String binding handler writes targetValue back into state via binding.set")
    func stringBindingRoundTrip() {
        let host = VB_StringHost()
        host.value = ""
        let binding = host.$value

        // Closure shape mirrors `.value(_:Binding<String>)` exactly.
        let invoke: (EventInfo) -> Void = { info in
            binding.set(info.targetValue ?? "")
        }
        invoke(EventInfo(type: "input", targetValue: "hello"))
        #expect(host.value == "hello")

        invoke(EventInfo(type: "input", targetValue: nil))
        #expect(host.value == "", "nil targetValue should fall back to empty string")
    }

    // MARK: - Int binding round-trip

    @Test("Int binding handler parses targetValue via targetIntValue")
    func intBindingParsesValid() {
        let host = VB_IntHost()
        let binding = host.$value

        let invoke: (EventInfo) -> Void = { info in
            if let parsed = info.targetIntValue { binding.set(parsed) }
        }
        invoke(EventInfo(type: "input", targetValue: "42"))
        #expect(host.value == 42)
    }

    @Test("Int binding leaves state unchanged on parse failure")
    func intBindingLeavesStateOnParseFail() {
        let host = VB_IntHost()
        host.value = 7
        let binding = host.$value

        let invoke: (EventInfo) -> Void = { info in
            if let parsed = info.targetIntValue { binding.set(parsed) }
        }
        invoke(EventInfo(type: "input", targetValue: "abc"))
        #expect(host.value == 7, "unparseable input must not clobber the binding")
    }

    // MARK: - Double binding round-trip

    @Test("Double binding handler parses targetValue via targetDoubleValue")
    func doubleBindingParsesValid() {
        let host = VB_DoubleHost()
        let binding = host.$value

        let invoke: (EventInfo) -> Void = { info in
            if let parsed = info.targetDoubleValue { binding.set(parsed) }
        }
        invoke(EventInfo(type: "input", targetValue: "3.14"))
        #expect(host.value == 3.14)
    }

    @Test("Double binding leaves state unchanged on parse failure")
    func doubleBindingLeavesStateOnParseFail() {
        let host = VB_DoubleHost()
        host.value = 2.5
        let binding = host.$value

        let invoke: (EventInfo) -> Void = { info in
            if let parsed = info.targetDoubleValue { binding.set(parsed) }
        }
        invoke(EventInfo(type: "input", targetValue: "nope"))
        #expect(host.value == 2.5)
    }
}
