// Tests/SwiflowTests/DSL/ComponentDSLTests.swift
import Testing
@testable import Swiflow

#if DEBUG
@MainActor
@Suite("embed { } reused-instance diagnostic (debug-only)")
struct EmbedReusedInstanceTests {

    /// A trivial component whose body is a leaf element. Two `embed { }`
    /// call sites returning the same instance of this class exercise the
    /// reused-instance check.
    final class Counter: Component {
        var body: VNode { span { VNode.text("0") } }
    }

    @Test("swiflowDiagnostic fires when a factory returns an already-mounted Component instance")
    func diagnosticFiresOnReuse() {
        // Install a capture override so the diagnostic doesn't trap. The
        // override is process-global — save and restore the prior value
        // to play nice with any other test that may install one.
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        // Construct ONE Counter instance and embed it twice. The first
        // embed registers the instance with MountedInstances; the second
        // tries to insert the same ObjectIdentifier and triggers the
        // diagnostic.
        let shared = Counter()
        let tree = div {
            embed { shared }
            embed { shared }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let result = diff(mounted: nil, next: tree, handles: handles, handlers: handlers)

        #expect(
            captured.contains { $0.contains("embed") },
            "Expected a diagnostic mentioning 'embed' to fire when the same Component instance is embedded twice; captured: \(captured)"
        )

        // Tear down: re-diff against a trivial tree so the test's
        // MountedInstances entries are removed. Without this, the
        // `shared` instance's ObjectIdentifier would linger in the
        // module-global Set; after ARC frees `shared`, an unrelated
        // test's freshly-allocated Component could land at the SAME
        // address and spuriously trip the diagnostic — i.e. cross-test
        // pollution. The override stays installed (defer'd to nil) so
        // any spurious diagnostic during teardown wouldn't trap either.
        _ = diff(
            mounted: result.newMountTree,
            next: VNode.text("done"),
            handles: handles,
            handlers: handlers
        )
    }
}
#endif

// MARK: - text() free functions
@MainActor
@Suite("text() free functions")
struct TextBuilderTests {
    @Test("text(String) creates VNode.text with the string")
    func testTextString() {
        #expect(text("hello") == VNode.text("hello"))
    }

    @Test("text(Int) converts integer to string")
    func testTextInt() {
        #expect(text(42) == VNode.text("42"))
    }

    @Test("text(Double) converts double to string")
    func testTextDouble() {
        #expect(text(3.14) == VNode.text("3.14"))
    }

    @Test("text(Bool) converts true to string")
    func testTextBoolTrue() {
        #expect(text(true) == VNode.text("true"))
    }

    @Test("text(Bool) converts false to string")
    func testTextBoolFalse() {
        #expect(text(false) == VNode.text("false"))
    }
}
