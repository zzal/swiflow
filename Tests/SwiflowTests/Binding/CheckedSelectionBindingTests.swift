// Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift
//
// Task D — Phase 7 / Phase 15 refresh. Validates the two pieces that
// together make `.checked(_:Binding<Bool>)` and
// `.selection(_:Binding<String>)` work without depending on SwiflowDOM
// (which is gated behind `#if canImport(JavaScriptKit)` and unavailable
// to host-side tests):
//
//   1. The `Attribute.compound([…])` shape that each modifier produces —
//      hand-built here, identical to what SwiflowDOM emits, so we can
//      assert structure without a mounted Renderer.
//   2. The handler closure's get/set contract against a synthetic
//      `EventInfo`, exactly mirroring how `.checked` / `.selection`
//      shape the closure inside SwiflowDOM.
//
// Phase 15: `@State` is now a macro, so the test fixtures use
// `@MainActor @Component`-decorated host classes for state cells.
// `Binding<T>` itself is unchanged.
import Testing
@testable import Swiflow

@MainActor @Component
private final class BoolHost {
    @State var flag: Bool = false
    var body: VNode { .text("") }
}

@MainActor @Component
private final class StringHost {
    @State var value: String = "A"
    var body: VNode { .text("") }
}

@Suite("@State + .checked / .selection round-trip")
@MainActor
struct CheckedSelectionBindingTests {

    // MARK: - .checked(_:Binding<Bool>)

    @Test(".checked-shaped compound for Binding<Bool> contains `checked` property + `change` handler")
    func checkedShape() {
        let host = BoolHost()
        let binding = host.$flag

        // Hand-build the exact `Attribute.compound([…])` that
        // SwiflowDOM's `.checked(_:Binding<Bool>)` will produce.
        let handler = EventHandler(id: 0) { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        let attr: Attribute = .compound([
            .property(name: "checked", value: .bool(binding.get())),
            .handler(event: "change", value: handler),
        ])

        guard case .compound(let inner) = attr else {
            Issue.record("expected .compound"); return
        }
        var sawProperty = false
        var sawHandler = false
        for a in inner {
            switch a {
            case .property(let name, let value):
                if name == "checked", case .bool(let b) = value {
                    #expect(b == false)
                    sawProperty = true
                }
            case .handler(let event, _):
                if event == "change" { sawHandler = true }
            default: break
            }
        }
        #expect(sawProperty)
        #expect(sawHandler)
    }

    @Test(".checked handler updates the binding when targetChecked is true")
    func checkedTrueUpdate() {
        let host = BoolHost()
        let binding = host.$flag
        // Closure shape mirrors `.checked(_:Binding<Bool>)` exactly.
        let invoke: (EventInfo) -> Void = { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        invoke(EventInfo(type: "change", targetChecked: true))
        #expect(host.flag == true)
    }

    @Test(".checked handler leaves binding unchanged when targetChecked is nil")
    func checkedNilNoChange() {
        let host = BoolHost()
        let binding = host.$flag
        let invoke: (EventInfo) -> Void = { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        invoke(EventInfo(type: "change"))  // no targetChecked
        #expect(host.flag == false)
    }

    // MARK: - .selection(_:Binding<String>)

    @Test(".selection-shaped compound for Binding<String> contains `value` property + `change` handler")
    func selectionShape() {
        let host = StringHost()
        let binding = host.$value

        // Hand-build the exact `Attribute.compound([…])` that
        // SwiflowDOM's `.selection(_:Binding<String>)` will produce.
        let handler = EventHandler(id: 0) { info in
            binding.set(info.targetValue ?? "")
        }
        let attr: Attribute = .compound([
            .property(name: "value", value: .string(binding.get())),
            .handler(event: "change", value: handler),
        ])

        guard case .compound(let inner) = attr else {
            Issue.record("expected .compound"); return
        }
        var sawProperty = false
        var sawHandler = false
        for a in inner {
            switch a {
            case .property(let name, let value):
                if name == "value", case .string(let s) = value {
                    #expect(s == "A")
                    sawProperty = true
                }
            case .handler(let event, _):
                if event == "change" { sawHandler = true }
            default: break
            }
        }
        #expect(sawProperty)
        #expect(sawHandler)
    }

    @Test(".selection handler writes targetValue into the binding")
    func selectionUpdate() {
        let host = StringHost()
        let binding = host.$value
        let invoke: (EventInfo) -> Void = { info in
            binding.set(info.targetValue ?? "")
        }
        invoke(EventInfo(type: "change", targetValue: "B"))
        #expect(host.value == "B")
    }

    @Test(".selection handler writes empty string when targetValue is nil")
    func selectionNilWritesEmpty() {
        let host = StringHost()
        let binding = host.$value
        let invoke: (EventInfo) -> Void = { info in
            binding.set(info.targetValue ?? "")
        }
        invoke(EventInfo(type: "change"))
        #expect(host.value == "")
    }
}
