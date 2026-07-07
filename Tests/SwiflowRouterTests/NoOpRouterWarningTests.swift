// Tests/SwiflowRouterTests/NoOpRouterWarningTests.swift
//
// Audit IV Wave-1 #1: @Environment(\.router) is only live during body, so
// reading router.navigate from a click handler silently hits the no-op
// default — nothing navigates, no error, and the capture-in-body
// workaround carried the same warning comment in three files. The default
// router's WRITE closures now emit a DEBUG swiflowWarn naming the fix.
//
// Deliberately swiflowWarn, not swiflowDiagnostic: the no-op default is a
// tolerated degradation (snapshot tests and components rendered outside a
// router context are documented uses) — it must signal, not crash. That's
// the Part V trap-vs-warn split applied here.
import Testing
import Swiflow
import SwiflowRouter

@Suite("No-op default router warns on writes")
struct NoOpRouterWarningTests {

    /// The default router exactly as a component would receive it with no
    /// RouterRoot above.
    private var defaultRouter: Router { EnvironmentValues().router }

    private func captureWarnings(_ body: () -> Void) -> [String] {
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    @Test("navigate on the default router warns, naming the path, body, and RouterRoot")
    @MainActor
    func navigateWarns() {
        let warnings = captureWarnings { defaultRouter.navigate("/settings") }
        #expect(warnings.count == 1)
        let msg = warnings.first ?? ""
        #expect(msg.contains("/settings"), "the attempted path makes the dead click findable")
        #expect(msg.contains("body"), "the fix: read \\.router inside body (capture it there for handlers)")
        #expect(msg.contains("RouterRoot"), "the other cause: no RouterRoot above the component")
    }

    @Test("replace on the default router warns")
    @MainActor
    func replaceWarns() {
        let warnings = captureWarnings { defaultRouter.replace("/login") }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("/login"))
    }

    @Test("back on the default router warns")
    @MainActor
    func backWarns() {
        let warnings = captureWarnings { defaultRouter.back() }
        #expect(warnings.count == 1)
        #expect((warnings.first ?? "").contains("RouterRoot"))
    }

    @Test("READS on the default router stay silent — the documented snapshot-test use")
    @MainActor
    func readsDoNotWarn() {
        let warnings = captureWarnings {
            _ = defaultRouter.path
            _ = defaultRouter.mode
            _ = defaultRouter.href(forPath: "/about")
        }
        #expect(warnings.isEmpty, "rendering outside a router context is tolerated; only dead WRITES warn")
    }

    @Test("a real router's writes never warn")
    @MainActor
    func realRouterDoesNotWarn() {
        // Box because Router's closures are @Sendable and can't capture a
        // mutable local; the test is single-threaded.
        final class Box: @unchecked Sendable { var value: String? }
        let navigated = Box()
        let real = Router(
            path: "/",
            navigate: { navigated.value = $0 },
            replace: { _ in },
            back: {}
        )
        let warnings = captureWarnings { real.navigate("/ok") }
        #expect(warnings.isEmpty)
        #expect(navigated.value == "/ok")
    }
}
