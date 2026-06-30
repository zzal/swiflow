// Tests/SwiflowTests/DiffTests/MemoKeyTests.swift
import Testing
@testable import Swiflow

@Suite("memoKey")
@MainActor
struct MemoKeyTests {

    @Test("modifier stores the key on the element")
    func modifierSetsKey() {
        guard case .element(let d) = div().memoKey("row-1") else {
            Issue.record("expected element"); return
        }
        #expect(d.memoKey == AnyHashable("row-1"))
    }

    @Test("memoKey is excluded from ElementData equality")
    func excludedFromEquality() {
        guard case .element(let a) = div(.class("r")).memoKey("a"),
              case .element(let b) = div(.class("r")).memoKey("b") else {
            Issue.record("expected elements"); return
        }
        // Same rendered shape, different memoKey → still equal (== ignores it).
        #expect(a == b)
    }

    @Test("modifier on a non-element is a no-op passthrough")
    func nonElementPassthrough() {
        // Suppress the DEBUG diagnostic trap so we can assert the return value.
        let prior = _swiflowDiagnosticOverride
        var diagnosticFired = false
        _swiflowDiagnosticOverride = { _ in diagnosticFired = true }
        defer { _swiflowDiagnosticOverride = prior }

        let t = VNode.text("hi").memoKey("x")
        #expect(t == .text("hi"))
        #expect(diagnosticFired)
    }
}
