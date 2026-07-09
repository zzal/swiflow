import Testing
@testable import SwiflowRouter
import Swiflow

@Suite("Router + EnvironmentValues")
@MainActor
struct RouterTests {

    /// The no-op default router WARNS by design (PR #174) — capture those
    /// expected warns locally so they can't leak into another suite's
    /// `_swiflowWarnOverride` window. This suite used to be non-@MainActor:
    /// its warns fired from a background thread mid-way through
    /// ContentKeyGuardrailTests' synchronous capture and polluted its count.
    /// NoOpRouterWarningTests owns asserting the warning's CONTENT.
    private func silencingExpectedWarns(_ body: () -> Void) {
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { _ in }
        defer { _swiflowWarnOverride = prior }
        body()
    }

    @Test("default Router path is /")
    func defaultRouterPath() {
        let env = EnvironmentValues()
        #expect(env.router.path == "/")
    }

    @Test("default Router navigate is a no-op")
    func defaultNavigateIsNoOp() {
        let env = EnvironmentValues()
        // Should not crash
        silencingExpectedWarns { env.router.navigate("/test") }
    }

    @Test("default Router replace is a no-op")
    func defaultReplaceIsNoOp() {
        let env = EnvironmentValues()
        silencingExpectedWarns { env.router.replace("/test") }
    }

    @Test("default Router back is a no-op")
    func defaultBackIsNoOp() {
        let env = EnvironmentValues()
        silencingExpectedWarns { env.router.back() }
    }

    @Test("EnvironmentValues router can be overridden")
    func routerCanBeOverridden() {
        var env = EnvironmentValues()
        let customRouter = Router(path: "/custom", navigate: { _ in }, replace: { _ in }, back: {})
        env.router = customRouter
        #expect(env.router.path == "/custom")
    }
}
