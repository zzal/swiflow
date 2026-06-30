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

    @Test("equal memoKey → diff skips the subtree (zero patches, mounted reused)")
    func equalKeyBails() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        // Mount a row whose child text is "A".
        let v1 = div(.class("row")) { p("A") }.memoKey("k1")
        let first = diff(mounted: nil, next: v1, handles: h, handlers: hr)
        // Next render: SAME memoKey but DIFFERENT child content ("B"). The bail
        // must win — equal key is the contract that content is unchanged.
        let v2 = div(.class("row")) { p("B") }.memoKey("k1")
        let second = diff(mounted: first.newMountTree, next: v2, handles: h, handlers: hr)
        #expect(second.patches.isEmpty)
        #expect(second.newMountTree === first.newMountTree)
    }

    @Test("different memoKey → normal diff (patches emitted)")
    func differentKeyDiffs() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        let first = diff(mounted: nil, next: div(.class("row")) { p("A") }.memoKey("k1"),
                         handles: h, handlers: hr)
        let second = diff(mounted: first.newMountTree, next: div(.class("row")) { p("B") }.memoKey("k2"),
                          handles: h, handlers: hr)
        let hasSetText = second.patches.contains { if case .setText(_, "B") = $0 { return true }; return false }
        #expect(hasSetText)
    }

    @Test("nil memoKey on either side → normal diff")
    func nilKeyDiffs() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        let first = diff(mounted: nil, next: div(.class("row")) { p("A") }.memoKey("k1"),
                         handles: h, handlers: hr)
        // new side has no memoKey → must not bail.
        let second = diff(mounted: first.newMountTree, next: div(.class("row")) { p("B") },
                          handles: h, handlers: hr)
        let hasSetText = second.patches.contains { if case .setText(_, "B") = $0 { return true }; return false }
        #expect(hasSetText)
    }
}
