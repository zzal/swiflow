// Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift
//
// Task D — Phase 7. Validates the two pieces that together make
// `.checked(_:Binding<Bool>)` and `.selection(_:Binding<String>)` work
// without depending on SwiflowWeb (which is gated behind
// `#if canImport(JavaScriptKit)` and unavailable to host-side tests):
//
//   1. The `Attribute.compound([…])` shape that each modifier produces —
//      hand-built here, identical to what SwiflowWeb emits, so we can
//      assert structure without a mounted Renderer.
//   2. The handler closure's get/set contract against a synthetic
//      `EventInfo`, exactly mirroring how `.checked` / `.selection`
//      shape the closure inside SwiflowWeb.
//
// This mirrors the Option γ pattern already established by
// `ValueBindingTests`.
import Testing
@testable import Swiflow

@Suite("@State + .checked / .selection round-trip")
@MainActor
struct CheckedSelectionBindingTests {

    // MARK: - .checked(_:Binding<Bool>)

    @Test(".checked-shaped compound for Binding<Bool> contains `checked` property + `change` handler")
    func checkedShape() {
        let state = State<Bool>(wrappedValue: false)
        let binding = state.projectedValue

        // Hand-build the exact `Attribute.compound([…])` that
        // SwiflowWeb's `.checked(_:Binding<Bool>)` will produce.
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
        let state = State<Bool>(wrappedValue: false)
        let binding = state.projectedValue
        // Closure shape mirrors `.checked(_:Binding<Bool>)` exactly.
        let invoke: (EventInfo) -> Void = { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        invoke(EventInfo(type: "change", targetChecked: true))
        #expect(state.wrappedValue == true)
    }

    @Test(".checked handler leaves binding unchanged when targetChecked is nil")
    func checkedNilNoChange() {
        let state = State<Bool>(wrappedValue: false)
        let binding = state.projectedValue
        let invoke: (EventInfo) -> Void = { info in
            if let c = info.targetChecked { binding.set(c) }
        }
        invoke(EventInfo(type: "change"))  // no targetChecked
        #expect(state.wrappedValue == false)
    }

    // MARK: - .selection(_:Binding<String>)

    @Test(".selection-shaped compound for Binding<String> contains `value` property + `change` handler")
    func selectionShape() {
        let state = State<String>(wrappedValue: "A")
        let binding = state.projectedValue

        // Hand-build the exact `Attribute.compound([…])` that
        // SwiflowWeb's `.selection(_:Binding<String>)` will produce.
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
        let state = State<String>(wrappedValue: "A")
        let binding = state.projectedValue
        let invoke: (EventInfo) -> Void = { info in
            binding.set(info.targetValue ?? "")
        }
        invoke(EventInfo(type: "change", targetValue: "B"))
        #expect(state.wrappedValue == "B")
    }

    @Test(".selection handler writes empty string when targetValue is nil")
    func selectionNilWritesEmpty() {
        let state = State<String>(wrappedValue: "A")
        let binding = state.projectedValue
        let invoke: (EventInfo) -> Void = { info in
            binding.set(info.targetValue ?? "")
        }
        invoke(EventInfo(type: "change"))
        #expect(state.wrappedValue == "")
    }
}
