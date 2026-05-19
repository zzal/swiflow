// Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift
import Testing
@testable import Swiflow

@Suite("Diagnostics (debug-only)")
@MainActor
struct DiagnosticsTests {

    final class CounterStub: Component {
        var body: VNode { .text("0") }
    }

    /// Component whose body returns another component anchor — infinite
    /// anchor cycle. Exists only to exercise the depth-guard diagnostic.
    final class CycleComponent: Component {
        var body: VNode { component({ CycleComponent() }) }
    }

    // Exit tests verify only that the subprocess exits non-zero — Swift
    // Testing's `processExitsWith: .failure` API does NOT capture stderr.
    // The crash MESSAGE substring is asserted by code reading only; if
    // the diagnostic message text matters for a regression, add a
    // separate test that calls the helper and matches the produced
    // string against the source-of-truth (currently the only
    // call sites in Diff.swift / KeyedChildrenDiff.swift).

    @Test(
        "Duplicate keys among siblings crash in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func duplicateKeysCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let parent = div {
                span(.key("a"))
                span(.key("a"))
            }
            await MainActor.run {
                _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
            }
        }
    }

    @Test(
        "Mixed keyed/unkeyed siblings crash in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func mixedKeyedUnkeyedCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let parent = ul {
                li(.key("a"))
                li()
            }
            await MainActor.run {
                _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
            }
        }
    }

    @Test(
        "Component body cycle (depth >= 32) crashes in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func componentCycleCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let v = VNode.component(.init(CycleComponent.self) { CycleComponent() })
            await MainActor.run {
                _ = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
            }
        }
    }

    @Test(
        "Duplicate keys on sibling component anchors crash in DEBUG",
        .disabled(if: !isDebugBuild)
    )
    func duplicateKeysOnComponentSiblingsCrash() async {
        await #expect(processExitsWith: .failure) {
            let handles = HandleAllocator()
            let handlers = HandlerRegistry()
            let parent = div {
                component({ CounterStub() }, key: "a")
                component({ CounterStub() }, key: "a")
            }
            await MainActor.run {
                _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
            }
        }
    }

    @Test("URLSanitizer rejection drops the attribute but does NOT crash (in DEBUG or release)")
    func urlSanitizerDoesNotCrash() {
        // URL rejection is a LOG, not a crash. Pages must render even
        // when an attacker injects javascript: into href.
        let element = applyAttributes(tag: "a", [
            .attr("href", "javascript:alert(1)"),
        ])
        #expect(element.attributes["href"] == nil)
    }

    @Test("Diagnostics module exposes the swiflowDiagnostic symbol")
    func diagnosticSymbolExists() {
        let fn: (@autoclosure () -> String) -> Void = swiflowDiagnostic
        _ = fn
    }
}

/// Helper for `.disabled(if:)` on the exit-test crash cases.
/// Release-mode runs would not crash (the diagnostic compiles to nothing),
/// so the test would fail spuriously — skip it instead.
private var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
