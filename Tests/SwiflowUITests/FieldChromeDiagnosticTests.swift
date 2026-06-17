// Tests/SwiflowUITests/FieldChromeDiagnosticTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

// The FOOTGUN guard in FieldChrome (`assertNoReservedBindingAttributes`) fires a
// `swiflowDiagnostic`, which is compiled out of release builds — so this whole suite
// lives behind `#if DEBUG`. It asserts that driving a form control's value through the
// trailing attribute bag (instead of its `text:`/`isOn:` parameter) is caught loudly in
// development, and that ordinary caller attributes pass through untouched.
#if DEBUG
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

/// Runs `body` with the diagnostic override installed (so diagnostics are captured
/// instead of trapping the process) and returns the captured messages.
@MainActor private func capturingDiagnostics(_ body: () -> Void) -> [String] {
    var captured: [String] = []
    let prior = _swiflowDiagnosticOverride
    _swiflowDiagnosticOverride = { captured.append($0) }
    defer { _swiflowDiagnosticOverride = prior }
    body()
    return captured
}

@Suite("FieldChrome reserved-attribute guard")
@MainActor
struct FieldChromeDiagnosticTests {
    private let text = Binding<String>(get: { "" }, set: { _ in })
    private let flag = Binding<Bool>(get: { false }, set: { _ in })

    @Test("a `.value` binding smuggled through trailing attributes is caught") func valueBindingCaught() {
        let stray = Binding<String>(get: { "x" }, set: { _ in })
        let msgs = capturingDiagnostics {
            building { _ = TextField("Name", text: text, .value(stray)) }
        }
        #expect(msgs.contains { $0.contains("value") })
    }

    @Test("a stray `.on(.input)` handler is caught") func inputHandlerCaught() {
        let msgs = capturingDiagnostics {
            building { _ = TextField("Name", text: text, .on(.input) {}) }
        }
        #expect(msgs.contains { $0.contains("input") })
    }

    @Test("a `.checked` binding smuggled into Checkbox is caught") func checkedBindingCaught() {
        let stray = Binding<Bool>(get: { true }, set: { _ in })
        let msgs = capturingDiagnostics {
            building { _ = Checkbox("Accept", isOn: flag, .checked(stray)) }
        }
        #expect(msgs.contains { $0.contains("checked") })
    }

    @Test("ordinary caller attributes do not trip the guard") func ordinaryAttrsClean() {
        let msgs = capturingDiagnostics {
            building { _ = TextField("Name", text: text, .attr("name", "n"), .class("mine")) }
        }
        #expect(msgs.isEmpty)
    }
}
#endif
